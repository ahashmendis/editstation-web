-- Open opportunities (2/3): schema. Spec docs/superpowers/specs/2026-11-16-open-opportunities-design.md
-- §3-§4, owner approval 2026-11-16 with every recommended §7 call (decisions log "B/C amended").
--
-- project_opportunities is EDITOR-VISIBLE: it holds only the summary the admin writes for editors
-- (never a copy of brief or client columns), no client identity and no client pricing. The pay
-- shown to editors is stored only when the admin chooses to show it (null = hidden), because RLS
-- cannot hide a column.
-- opportunity_interests: an editor reads only their own rows; admins read all. Rows are never
-- deleted and only the status moves forward (interested -> withdrawn | selected | not_selected);
-- registering again after a withdrawal adds a new row. The proposed rate is only a signal: it never
-- sets pay (pay is agreed through the existing offer flow).
-- No API write grants: every write goes through the functions in the next migration.

create type public.opportunity_status as enum ('open', 'closed', 'filled');
create type public.opportunity_interest_status as enum ('interested', 'withdrawn', 'selected', 'not_selected');

-- Notifications about an opportunity an editor was not chosen for point at the opportunity.
alter table public.notifications drop constraint notifications_entity_type_check;
alter table public.notifications add constraint notifications_entity_type_check
  check (entity_type in ('client_inquiry', 'editor_application', 'project', 'payment', 'editor_profile',
    'project_opportunity'));

-- ---------------------------------------------------------------------------
-- project_opportunities: one per project (reopened in place)
-- ---------------------------------------------------------------------------
create table public.project_opportunities (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null unique references public.projects (id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  service_type_code text references public.service_types (code),
  deliverables_summary text not null check (char_length(deliverables_summary) between 1 and 1000),
  deadline date,
  format_notes text check (char_length(format_notes) between 1 and 1000),
  -- Editor pay the admin chooses to show; null = hidden (the editor may propose a rate).
  shown_pay_amount numeric(12, 2) check (shown_pay_amount > 0),
  shown_pay_currency char(3) check (shown_pay_currency ~ '^[A-Z]{3}$'),
  -- Optional: no new interest after this moment (the admin can still choose an editor).
  closes_at timestamptz,
  status public.opportunity_status not null default 'open',
  close_reason text check (close_reason in ('selected', 'admin', 'project_closed')),
  published_by uuid references public.profiles (id) on delete set null,
  published_at timestamptz not null default now(),
  closed_by uuid references public.profiles (id) on delete set null,
  closed_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint project_opportunities_pay_pair check ((shown_pay_amount is null) = (shown_pay_currency is null)),
  constraint project_opportunities_closed_state check (
    (status = 'open') = (closed_at is null)
    and (status = 'open') = (close_reason is null)
    and ((status = 'filled') = (close_reason = 'selected') or status = 'open'))
);
create index project_opportunities_status_idx on public.project_opportunities (status, published_at desc);
create index project_opportunities_service_type_idx on public.project_opportunities (service_type_code);
create index project_opportunities_published_by_idx on public.project_opportunities (published_by);
create index project_opportunities_closed_by_idx on public.project_opportunities (closed_by);
create trigger project_opportunities_set_updated_at
  before update on public.project_opportunities
  for each row execute function private.set_updated_at();
comment on table public.project_opportunities is
  'Editor-visible opportunity summary written by an admin. Never client identity, client pricing, brief text, files or links.';

-- ---------------------------------------------------------------------------
-- opportunity_interests
-- ---------------------------------------------------------------------------
create table public.opportunity_interests (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references public.project_opportunities (id) on delete cascade,
  editor_id uuid not null references public.editor_profiles (user_id) on delete cascade,
  -- A signal only; never sets pay.
  proposed_amount numeric(12, 2) check (proposed_amount > 0),
  proposed_currency char(3) check (proposed_currency ~ '^[A-Z]{3}$'),
  note text check (char_length(note) between 1 and 500),
  status public.opportunity_interest_status not null default 'interested',
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  constraint opportunity_interests_rate_pair check ((proposed_amount is null) = (proposed_currency is null)),
  constraint opportunity_interests_decided check ((status = 'interested') = (decided_at is null))
);
-- One live row (interested or selected) per editor per opportunity. (The limit of 10 is separate:
-- it counts only `interested` rows on opportunities still taking interest; see the functions.)
create unique index opportunity_interests_live_key on public.opportunity_interests (opportunity_id, editor_id)
  where status in ('interested', 'selected');
create index opportunity_interests_opportunity_idx on public.opportunity_interests (opportunity_id, created_at);
create index opportunity_interests_editor_idx on public.opportunity_interests (editor_id, status);
comment on table public.opportunity_interests is
  'Editor interest in an opportunity. Append-style: never deleted, status only moves forward. Editors read their own rows.';

-- ---------------------------------------------------------------------------
-- Guards (hold for the table owner too)
-- ---------------------------------------------------------------------------
create function private.guard_project_opportunities()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if not exists (select 1 from public.projects p where p.id = old.project_id) then
      return old;
    end if;
    raise exception 'An opportunity cannot be deleted. Close it instead.' using errcode = 'ES409';
  end if;
  if new.project_id <> old.project_id then
    raise exception 'An opportunity cannot move to another project.' using errcode = 'ES409';
  end if;
  return new;
end;
$$;

create trigger project_opportunities_guard
  before update or delete on public.project_opportunities
  for each row execute function private.guard_project_opportunities();

create function private.guard_opportunity_interests()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'interested' or new.decided_at is not null then
      raise exception 'A new interest starts as interested.' using errcode = 'ES409';
    end if;
    return new;
  end if;
  if tg_op = 'DELETE' then
    -- Only the cascade from deleting the editor or the opportunity.
    if not exists (select 1 from public.editor_profiles e where e.user_id = old.editor_id)
       or not exists (select 1 from public.project_opportunities o where o.id = old.opportunity_id) then
      return old;
    end if;
    raise exception 'Interest history cannot be deleted.' using errcode = 'ES409';
  end if;
  if old.status <> 'interested' or new.status = 'interested'
     or (to_jsonb(new) - 'status' - 'decided_at') <> (to_jsonb(old) - 'status' - 'decided_at') then
    raise exception 'Interest history cannot be changed.' using errcode = 'ES409';
  end if;
  return new;
end;
$$;

create trigger opportunity_interests_guard
  before insert or update or delete on public.opportunity_interests
  for each row execute function private.guard_opportunity_interests();

-- ---------------------------------------------------------------------------
-- RLS helper: an active editor sees an opportunity that takes interest now, or one they have an
-- interest row on. Executable by authenticated because the policy runs as the caller.
-- ---------------------------------------------------------------------------
create function private.editor_can_see_opportunity(p_opportunity_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_active_editor() and (
    exists (select 1 from public.project_opportunities o
            join public.projects p on p.id = o.project_id
            where o.id = p_opportunity_id and o.status = 'open'
              and (o.closes_at is null or o.closes_at > now())
              and p.status = 'open' and p.archived_at is null)
    or exists (select 1 from public.opportunity_interests i
               where i.opportunity_id = p_opportunity_id and i.editor_id = (select auth.uid())));
$$;

-- ---------------------------------------------------------------------------
-- RLS on, default deny, read-only grants (writes through functions only)
-- ---------------------------------------------------------------------------
alter table public.project_opportunities enable row level security;
alter table public.opportunity_interests enable row level security;
revoke all on public.project_opportunities, public.opportunity_interests from public, anon, authenticated;
-- Column-level grant enforces the projection for direct API reads: project_id, published_by and
-- closed_by are not readable by the API role (admins read them through admin_get_opportunity).
grant select (id, title, service_type_code, deliverables_summary, deadline, format_notes, shown_pay_amount,
  shown_pay_currency, closes_at, status, close_reason, published_at, closed_at, updated_at)
  on public.project_opportunities to authenticated;
grant select on public.opportunity_interests to authenticated;

create policy project_opportunities_select on public.project_opportunities
  for select to authenticated
  using ((select private.is_admin()) or private.editor_can_see_opportunity(id));

create policy opportunity_interests_select on public.opportunity_interests
  for select to authenticated
  using ((select private.is_admin())
         or (editor_id = (select auth.uid()) and (select private.is_active_editor())));

revoke all on function private.guard_project_opportunities(), private.guard_opportunity_interests(),
  private.editor_can_see_opportunity(uuid)
from public, anon, authenticated;
grant execute on function private.editor_can_see_opportunity(uuid) to authenticated;
