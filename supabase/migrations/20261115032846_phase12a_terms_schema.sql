-- Phase 12A (1/2): project terms agreement. Spec docs/superpowers/specs/2026-11-15-phase12-commercial-terms-design.md
-- §4.1, §5 (confirm gate), calls 6, 9, 10. Owner decisions F, F2, F3, KB9, KB9a.
-- project_terms and project_terms_stages are admin-only (client charges and client kill-fee shares
-- are client pricing). No write grants: every write goes through security definer functions.
-- Versioned and append-only: an agreed row is never edited; a change is version n+1 and n becomes
-- superseded. projects.revision_allowance becomes a cache of the agreed included_rounds.

create type public.project_terms_status as enum ('draft', 'agreed', 'superseded');
-- The project status at cancellation (§4.1).
create type public.terms_stage as enum ('assigned', 'in_progress', 'in_review', 'revision_requested');

-- Editor milestone shares: 1..10 whole percentages, each 1..100, summing to 100.
create function private.terms_shares_valid(p_shares smallint[])
returns boolean
language sql
immutable
security definer
set search_path = ''
as $$
  select p_shares is not null
    and cardinality(p_shares) between 1 and 10
    and array_position(p_shares, null) is null
    and (select bool_and(s between 1 and 100) and sum(s) = 100 from unnest(p_shares) s);
$$;

-- ---------------------------------------------------------------------------
-- project_terms
-- ---------------------------------------------------------------------------
create table public.project_terms (
  id uuid primary key default gen_random_uuid(),
  -- Cascade only matters for an unused draft project deleted by the owner; projects with any
  -- workflow history are kept by other restrict keys.
  project_id uuid not null references public.projects (id) on delete cascade,
  version int not null check (version >= 1),
  status public.project_terms_status not null default 'draft',
  -- Revision policy (F, F3): 0 means client revisions are chargeable from round 1.
  included_rounds smallint not null default 3 check (included_rounds between 0 and 20),
  -- Client pricing, admin-only; nullable until known (never defaulted).
  extra_round_charge numeric(12, 2) check (extra_round_charge >= 0),
  charge_currency char(3) check (charge_currency ~ '^[A-Z]{3}$'),
  -- Day counts: owner defaults (KB9, KB9a), changeable before the project starts.
  deposit_days smallint not null default 14 check (deposit_days between 0 and 365),
  balance_days smallint not null default 7 check (balance_days between 0 and 365),
  editor_pay_days smallint not null default 7 check (editor_pay_days between 0 and 365),
  late_balance_days smallint not null default 14 check (late_balance_days between 0 and 365),
  -- Editor pay milestones as percentages of the agreed amount (default 50/50).
  editor_milestone_shares smallint[] not null default '{50,50}'
    check (cardinality(editor_milestone_shares) between 1 and 10),
  change_reason text check (char_length(change_reason) between 1 and 2000),
  created_by uuid references public.profiles (id) on delete set null,
  agreed_by uuid references public.profiles (id) on delete set null,
  agreed_at timestamptz,
  superseded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint project_terms_version_key unique (project_id, version),
  constraint project_terms_charge_chk check ((extra_round_charge is null) = (charge_currency is null)),
  constraint project_terms_state_chk check (
    (status = 'draft') = (agreed_at is null)
    and (status = 'superseded') = (superseded_at is not null)),
  constraint project_terms_agreed_shares_chk check (
    status = 'draft' or private.terms_shares_valid(editor_milestone_shares))
);
create unique index project_terms_one_draft_key on public.project_terms (project_id) where status = 'draft';
create unique index project_terms_one_agreed_key on public.project_terms (project_id) where status = 'agreed';
create index project_terms_created_by_idx on public.project_terms (created_by);
create index project_terms_agreed_by_idx on public.project_terms (agreed_by);
create trigger project_terms_set_updated_at
  before update on public.project_terms
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- project_terms_stages: cancellation / kill-fee schedule. No default values (§4.1).
-- ---------------------------------------------------------------------------
create table public.project_terms_stages (
  id uuid primary key default gen_random_uuid(),
  terms_id uuid not null references public.project_terms (id) on delete cascade,
  stage public.terms_stage not null,
  editor_earned_percent numeric(5, 2) not null check (editor_earned_percent between 0 and 100),
  client_charge_percent numeric(5, 2) not null check (client_charge_percent between 0 and 100),
  created_at timestamptz not null default now(),
  constraint project_terms_stages_key unique (terms_id, stage)
);

-- ---------------------------------------------------------------------------
-- RLS: admin select only; no write grants for any API role
-- ---------------------------------------------------------------------------
alter table public.project_terms enable row level security;
alter table public.project_terms_stages enable row level security;
revoke all on public.project_terms, public.project_terms_stages from anon, authenticated;
grant select on public.project_terms, public.project_terms_stages to authenticated;
create policy project_terms_select_admin on public.project_terms
  for select to authenticated using ((select private.is_admin()));
create policy project_terms_stages_select_admin on public.project_terms_stages
  for select to authenticated using ((select private.is_admin()));

-- ---------------------------------------------------------------------------
-- Guards (hold for every caller, including the table owner)
-- ---------------------------------------------------------------------------
-- Insert: next version only. Delete: never. Update of a draft: content only (project and version
-- fixed; may become agreed). Agreed: only -> superseded, nothing else. Superseded: frozen. The
-- actor columns may still be cleared by on delete set null.
create function private.guard_project_terms()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old jsonb;
  v_new jsonb;
begin
  if tg_op = 'DELETE' then
    -- Only the cascade from deleting the project itself (the parent row is already gone).
    if not exists (select 1 from public.projects p where p.id = old.project_id) then
      return old;
    end if;
    raise exception 'Project terms cannot be deleted.' using errcode = 'ES409';
  end if;
  if tg_op = 'INSERT' then
    if new.version <> coalesce((select max(t.version) from public.project_terms t
                                where t.project_id = new.project_id), 0) + 1 then
      raise exception 'Project terms must be added as the next version.' using errcode = 'ES409';
    end if;
    return new;
  end if;

  if new.project_id <> old.project_id or new.version <> old.version then
    raise exception 'Project terms cannot move to another project or version.' using errcode = 'ES409';
  end if;
  v_old := to_jsonb(old) - 'updated_at';
  v_new := to_jsonb(new) - 'updated_at';
  -- on delete set null of an actor column, everything else unchanged.
  if (v_old ->> 'created_by' is not null and v_new ->> 'created_by' is null
      and (v_new - 'created_by') = (v_old - 'created_by'))
     or (v_old ->> 'agreed_by' is not null and v_new ->> 'agreed_by' is null
      and (v_new - 'agreed_by') = (v_old - 'agreed_by')) then
    return new;
  end if;

  if old.status = 'draft' then
    if new.status = 'superseded' then
      raise exception 'A draft cannot be superseded.' using errcode = 'ES409';
    end if;
    return new;
  elsif old.status = 'agreed' and new.status = 'superseded'
        and (v_new - 'status' - 'superseded_at') = (v_old - 'status' - 'superseded_at') then
    return new;
  end if;
  raise exception 'Agreed project terms cannot be changed. Agree a new version instead.' using errcode = 'ES409';
end;
$$;

create trigger project_terms_guard
  before insert or update or delete on public.project_terms
  for each row execute function private.guard_project_terms();

-- Stage rows change only while their terms are a draft.
create function private.guard_project_terms_stages()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_terms uuid := case when tg_op = 'DELETE' then old.terms_id else new.terms_id end;
begin
  if tg_op = 'UPDATE' and new.terms_id <> old.terms_id then
    raise exception 'A cancellation stage cannot move to other terms.' using errcode = 'ES409';
  end if;
  if tg_op = 'DELETE' and not exists (select 1 from public.project_terms t where t.id = v_terms) then
    return old;  -- cascade from deleting the terms' project
  end if;
  if not exists (select 1 from public.project_terms t where t.id = v_terms and t.status = 'draft') then
    raise exception 'Agreed project terms cannot be changed. Agree a new version instead.' using errcode = 'ES409';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger project_terms_stages_guard
  before insert or update or delete on public.project_terms_stages
  for each row execute function private.guard_project_terms_stages();

-- projects.revision_allowance is a cache: it may change only to the included_rounds of the
-- project's agreed terms (written by public.admin_agree_terms).
create function private.guard_revision_allowance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.revision_allowance is distinct from old.revision_allowance
     and not exists (select 1 from public.project_terms t
                     where t.project_id = new.id and t.status = 'agreed'
                       and t.included_rounds = new.revision_allowance) then
    raise exception 'The revision allowance changes only when new project terms are agreed.'
      using errcode = 'ES409';
  end if;
  return new;
end;
$$;

create trigger projects_guard_revision_allowance
  before update of revision_allowance on public.projects
  for each row execute function private.guard_revision_allowance();

-- ---------------------------------------------------------------------------
-- Backfill (call 10, local data only): terms v1 from revision_allowance, no stages. Projects
-- where an editor was confirmed or work began get agreed terms (the allowance already applied);
-- the rest get a draft. Runs before the insert trigger below exists.
-- ---------------------------------------------------------------------------
insert into public.project_terms (project_id, version, status, included_rounds, agreed_at, created_by)
select p.id, 1,
  case when exists (select 1 from public.assignments a where a.project_id = p.id
                    and (a.status in ('confirmed', 'in_progress') or a.confirmed_at is not null))
       then 'agreed'::public.project_terms_status else 'draft' end,
  p.revision_allowance,
  case when exists (select 1 from public.assignments a where a.project_id = p.id
                    and (a.status in ('confirmed', 'in_progress') or a.confirmed_at is not null))
       then now() end,
  p.created_by
from public.projects p
where not exists (select 1 from public.project_terms t where t.project_id = p.id);

-- ---------------------------------------------------------------------------
-- Every new project gets draft terms v1 with the owner defaults and its included rounds
-- (pre-filled 3 on the form). Covers admin_create_project and admin_convert_inquiry.
-- ---------------------------------------------------------------------------
create function private.create_initial_terms()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.project_terms (project_id, version, status, included_rounds, created_by)
  values (new.id, 1, 'draft', new.revision_allowance, new.created_by);
  return null;
end;
$$;

create trigger projects_create_initial_terms
  after insert on public.projects
  for each row execute function private.create_initial_terms();

revoke all on function private.terms_shares_valid(smallint[]), private.guard_project_terms(),
  private.guard_project_terms_stages(), private.guard_revision_allowance(), private.create_initial_terms()
from public, anon, authenticated;
