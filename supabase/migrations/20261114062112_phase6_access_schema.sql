-- Phase 6 (1/5): project access, assignments, negotiation history and admin notes.
-- Spec docs/superpowers/specs/2026-11-14-phase5-6-editor-access-design.md §5, §7.
-- Decisions C (one confirmed editor, others not_selected), KB6 (admin notes log).
-- Admin-read-only here; editor own-row policies arrive in the visibility migration. No
-- insert/update/delete grants or policies: all writes go through security definer functions.
-- Editor-readable tables (project_access, assignments, negotiation_offers) hold no client data.

create type public.project_access_reason as enum ('invited', 'available');
create type public.assignment_status as enum (
  'offered', 'counteroffer_pending', 'accepted', 'confirmed', 'declined', 'withdrawn', 'not_selected',
  'reassigned');
create type public.negotiation_role as enum ('admin', 'editor');
create type public.negotiation_action as enum ('offer', 'counter', 'accept', 'decline', 'withdraw');

-- ---------------------------------------------------------------------------
-- Project access: the named list of editors who may see a project's opportunity summary
-- ---------------------------------------------------------------------------
create table public.project_access (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  editor_id uuid not null references public.editor_profiles (user_id) on delete restrict,
  reason public.project_access_reason not null,
  granted_by uuid references public.profiles (id) on delete set null,
  granted_at timestamptz not null default now(),
  revoked_by uuid references public.profiles (id) on delete set null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index project_access_live_key on public.project_access (project_id, editor_id)
  where revoked_at is null;
create index project_access_editor_idx on public.project_access (editor_id);
create index project_access_granted_by_idx on public.project_access (granted_by);
create index project_access_revoked_by_idx on public.project_access (revoked_by);
create trigger project_access_set_updated_at
  before update on public.project_access
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- Assignments: one row per offer thread (project, editor); history is never overwritten
-- ---------------------------------------------------------------------------
create table public.assignments (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  editor_id uuid not null references public.editor_profiles (user_id) on delete restrict,
  status public.assignment_status not null default 'offered',
  -- The offer currently on the table.
  proposed_amount numeric(12, 2) not null check (proposed_amount > 0),
  currency char(3) not null default 'LKR' check (currency ~ '^[A-Z]{3}$'),
  -- Set only when an offer is accepted (spec §1: pay is an explicit agreed amount).
  agreed_amount numeric(12, 2) check (agreed_amount > 0),
  agreed_currency char(3) check (agreed_currency ~ '^[A-Z]{3}$'),
  confirmed_by uuid references public.profiles (id) on delete set null,
  confirmed_at timestamptz,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint assignments_agreed_chk check (
    (agreed_amount is null) = (agreed_currency is null)
    and (agreed_currency is null or agreed_currency = currency)
    and (status not in ('accepted', 'confirmed') or agreed_amount is not null)
    and (status not in ('offered', 'counteroffer_pending') or agreed_amount is null)),
  constraint assignments_confirmed_chk check ((status = 'confirmed') <= (confirmed_at is not null)),
  constraint assignments_closed_chk check (
    (status in ('declined', 'withdrawn', 'not_selected', 'reassigned')) = (closed_at is not null))
);
create unique index assignments_live_key on public.assignments (project_id, editor_id)
  where status in ('offered', 'counteroffer_pending', 'accepted', 'confirmed');
create unique index assignments_one_confirmed_key on public.assignments (project_id)
  where status = 'confirmed';
create index assignments_editor_idx on public.assignments (editor_id);
create index assignments_confirmed_by_idx on public.assignments (confirmed_by);
create trigger assignments_set_updated_at
  before update on public.assignments
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- Negotiation history (append-only)
-- ---------------------------------------------------------------------------
create table public.negotiation_offers (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments (id) on delete restrict,
  from_role public.negotiation_role not null,
  action public.negotiation_action not null,
  amount numeric(12, 2) check (amount > 0),
  currency char(3) check (currency ~ '^[A-Z]{3}$'),
  message text check (char_length(message) between 1 and 2000),
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint negotiation_offers_amount_chk check (
    (action in ('decline', 'withdraw')) = (amount is null)
    and (amount is null) = (currency is null))
);
create index negotiation_offers_assignment_idx on public.negotiation_offers (assignment_id, created_at);
create index negotiation_offers_created_by_idx on public.negotiation_offers (created_by);

-- ---------------------------------------------------------------------------
-- Admin notes log (KB6; admin-only, append-only)
-- ---------------------------------------------------------------------------
create table public.project_notes (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  author_id uuid references public.profiles (id) on delete set null,
  note text not null check (char_length(note) between 1 and 4000),
  created_at timestamptz not null default now()
);
create index project_notes_project_idx on public.project_notes (project_id, created_at desc);
create index project_notes_author_idx on public.project_notes (author_id);

-- ---------------------------------------------------------------------------
-- RLS and privileges: admin select only
-- ---------------------------------------------------------------------------
alter table public.project_access enable row level security;
alter table public.assignments enable row level security;
alter table public.negotiation_offers enable row level security;
alter table public.project_notes enable row level security;

revoke all on public.project_access, public.assignments, public.negotiation_offers, public.project_notes
  from anon, authenticated;
grant select on public.project_access, public.assignments, public.negotiation_offers, public.project_notes
  to authenticated;

create policy project_access_select_admin on public.project_access
  for select to authenticated using ((select private.is_admin()));
create policy assignments_select_admin on public.assignments
  for select to authenticated using ((select private.is_admin()));
create policy negotiation_offers_select_admin on public.negotiation_offers
  for select to authenticated using ((select private.is_admin()));
create policy project_notes_select_admin on public.project_notes
  for select to authenticated using ((select private.is_admin()));

-- ---------------------------------------------------------------------------
-- Assignment transition table (spec §7). Function-level "from" checks add who may act.
-- ---------------------------------------------------------------------------
create function private.assignment_transition_allowed(
  p_from public.assignment_status, p_to public.assignment_status)
returns boolean
language sql
immutable
security definer
set search_path = ''
as $$
  select coalesce(case
    when p_from = 'offered' then p_to in ('accepted', 'declined', 'counteroffer_pending', 'withdrawn', 'not_selected')
    when p_from = 'counteroffer_pending' then p_to in ('accepted', 'offered', 'declined', 'withdrawn', 'not_selected')
    when p_from = 'accepted' then p_to in ('confirmed', 'withdrawn', 'not_selected')
    when p_from = 'confirmed' then p_to in ('reassigned', 'withdrawn')
    else false
  end, false);
$$;

-- ---------------------------------------------------------------------------
-- Guard triggers (hold for every caller, including the table owner). BEFORE UPDATE only on
-- assignments so tests can seed any status directly.
-- ---------------------------------------------------------------------------
create function private.guard_assignments()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.project_id <> old.project_id or new.editor_id <> old.editor_id then
    raise exception 'The project or editor of an offer cannot change.' using errcode = 'ES409';
  end if;
  if new.status is distinct from old.status
     and not private.assignment_transition_allowed(old.status, new.status) then
    raise exception 'An offer cannot move from % to %.',
      replace(old.status::text, '_', ' '), replace(new.status::text, '_', ' ')
      using errcode = 'ES409';
  end if;
  return new;
end;
$$;

create trigger assignments_guard
  before update on public.assignments
  for each row execute function private.guard_assignments();

-- Append-only: DELETE is refused; UPDATE is refused except clearing the actor column (named in
-- TG_ARGV[0]) from a value to null with every other column unchanged (on delete set null).
create function private.guard_append_only()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_col text := tg_argv[0];
begin
  if tg_op = 'DELETE' then
    raise exception 'This history cannot be deleted.' using errcode = 'ES409';
  end if;
  if (to_jsonb(old) ->> v_col) is not null
     and (to_jsonb(new) ->> v_col) is null
     and (to_jsonb(new) - v_col) = (to_jsonb(old) - v_col) then
    return new;
  end if;
  raise exception 'This history cannot be changed.' using errcode = 'ES409';
end;
$$;

create trigger negotiation_offers_append_only
  before update or delete on public.negotiation_offers
  for each row execute function private.guard_append_only('created_by');
create trigger project_notes_append_only
  before update or delete on public.project_notes
  for each row execute function private.guard_append_only('author_id');

-- ---------------------------------------------------------------------------
-- Audit: assignment creation and status changes (ids and status names only, no amounts)
-- ---------------------------------------------------------------------------
create function private.audit_assignments()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or old.status is distinct from new.status then
    insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
    values (
      (select p.id from public.profiles p where p.id = (select auth.uid())),
      'assignment.' || new.status::text,
      'assignment',
      new.id::text,
      jsonb_build_object(
        'assignment_id', new.id,
        'project_id', new.project_id,
        'editor_id', new.editor_id,
        'from', case when tg_op = 'INSERT' then null else old.status end,
        'to', new.status));
  end if;
  return new;
end;
$$;

create trigger assignments_audit
  after insert or update of status on public.assignments
  for each row execute function private.audit_assignments();

revoke all on function
  private.assignment_transition_allowed(public.assignment_status, public.assignment_status),
  private.guard_assignments(), private.guard_append_only(), private.audit_assignments()
from public, anon, authenticated;
