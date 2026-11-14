-- Phase 7 (2/6): interpretation and brief confirmation schema, assignments widened for
-- in_progress. Spec docs/superpowers/specs/2026-11-14-phase7-confirmation-gate-design.md §5, §6.
-- Plan calls 2, 3, 4, 16. Both new tables: select-only grants, one combined admin-or-own-editor
-- policy, no write grants; every write goes through security definer functions (later
-- migrations). Neither table holds client data or client pricing.

create type public.interpretation_status as enum ('submitted', 'accepted', 'changes_requested');
create type public.brief_confirmation_kind as enum ('confirmed', 'carried_forward');

-- ---------------------------------------------------------------------------
-- assignments: start columns, widened constraints, one active editor per project (call 2, 3)
-- ---------------------------------------------------------------------------
alter table public.assignments
  add column started_at timestamptz,
  add column started_by uuid references public.profiles (id) on delete set null;
create index assignments_started_by_idx on public.assignments (started_by);

alter table public.assignments
  drop constraint assignments_agreed_chk,
  drop constraint assignments_confirmed_chk;
alter table public.assignments
  add constraint assignments_agreed_chk check (
    (agreed_amount is null) = (agreed_currency is null)
    and (agreed_currency is null or agreed_currency = currency)
    and (status not in ('accepted', 'confirmed', 'in_progress') or agreed_amount is not null)
    and (status not in ('offered', 'counteroffer_pending') or agreed_amount is null)),
  add constraint assignments_confirmed_chk check (
    (status in ('confirmed', 'in_progress')) <= (confirmed_at is not null)),
  add constraint assignments_started_chk check ((status = 'in_progress') <= (started_at is not null));

drop index public.assignments_live_key;
create unique index assignments_live_key on public.assignments (project_id, editor_id)
  where status in ('offered', 'counteroffer_pending', 'accepted', 'confirmed', 'in_progress');
drop index public.assignments_one_confirmed_key;
create unique index assignments_one_active_key on public.assignments (project_id)
  where status in ('confirmed', 'in_progress');

-- Phase 6 rules plus confirmed -> in_progress and in_progress -> reassigned | withdrawn (18 pairs).
-- confirmed -> in_progress is further gated by private.guard_assignment_start (gate migration).
create or replace function private.assignment_transition_allowed(
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
    when p_from = 'confirmed' then p_to in ('in_progress', 'reassigned', 'withdrawn')
    when p_from = 'in_progress' then p_to in ('reassigned', 'withdrawn')
    else false
  end, false);
$$;

-- ---------------------------------------------------------------------------
-- Editor interpretations (append-only history; one row per submission; KB §4.2)
-- ---------------------------------------------------------------------------
create table public.editor_interpretations (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments (id) on delete restrict,
  -- The project's current brief version when submitted.
  brief_version_id uuid not null references public.brief_versions (id) on delete restrict,
  will_reproduce text check (char_length(will_reproduce) between 1 and 4000),
  will_adapt text check (char_length(will_adapt) between 1 and 4000),
  questions_limitations text check (char_length(questions_limitations) between 1 and 4000),
  status public.interpretation_status not null default 'submitted',
  -- Written for the editor; admin-only remarks go to project_notes.
  admin_feedback text check (char_length(admin_feedback) between 1 and 4000),
  submitted_by uuid references public.profiles (id) on delete set null,
  submitted_at timestamptz not null default now(),
  reviewed_by uuid references public.profiles (id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint editor_interpretations_content_chk check (num_nonnulls(will_reproduce, will_adapt) >= 1),
  constraint editor_interpretations_review_chk check (
    (status = 'submitted') = (reviewed_at is null)
    and (status <> 'changes_requested' or admin_feedback is not null)
    and (status <> 'submitted' or (admin_feedback is null and reviewed_by is null)))
);
create unique index editor_interpretations_pending_key on public.editor_interpretations (assignment_id)
  where status = 'submitted';
create index editor_interpretations_assignment_idx on public.editor_interpretations (assignment_id, submitted_at);
create index editor_interpretations_brief_version_idx on public.editor_interpretations (brief_version_id);
create index editor_interpretations_submitted_by_idx on public.editor_interpretations (submitted_by);
create index editor_interpretations_reviewed_by_idx on public.editor_interpretations (reviewed_by);

-- ---------------------------------------------------------------------------
-- Brief confirmations (immutable; KB §5.1; Phase 4 spec §8, §15)
-- ---------------------------------------------------------------------------
create table public.brief_confirmations (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments (id) on delete restrict,
  project_id uuid not null references public.projects (id) on delete restrict,
  editor_id uuid not null references public.editor_profiles (user_id) on delete restrict,
  brief_version_id uuid not null references public.brief_versions (id) on delete restrict,
  brief_version int not null check (brief_version >= 1),
  kind public.brief_confirmation_kind not null,
  carried_from_id uuid references public.brief_confirmations (id) on delete restrict,
  confirmed_deadline date not null,
  confirmed_deliverables jsonb not null check (jsonb_typeof(confirmed_deliverables) = 'array'),
  confirmed_amount numeric(12, 2) not null check (confirmed_amount > 0),
  confirmed_currency char(3) not null check (confirmed_currency ~ '^[A-Z]{3}$'),
  -- The editor for `confirmed`; the admin who saved the brief for `carried_forward`.
  created_by uuid references public.profiles (id) on delete set null,
  confirmed_at timestamptz not null default clock_timestamp(),
  constraint brief_confirmations_kind_chk check ((kind = 'carried_forward') = (carried_from_id is not null))
);
create unique index brief_confirmations_carried_key on public.brief_confirmations (assignment_id, brief_version_id)
  where kind = 'carried_forward';
create index brief_confirmations_assignment_idx
  on public.brief_confirmations (assignment_id, brief_version desc, confirmed_at desc);
create index brief_confirmations_project_idx on public.brief_confirmations (project_id);
create index brief_confirmations_editor_idx on public.brief_confirmations (editor_id);
create index brief_confirmations_brief_version_idx on public.brief_confirmations (brief_version_id);
create index brief_confirmations_carried_from_idx on public.brief_confirmations (carried_from_id);
create index brief_confirmations_created_by_idx on public.brief_confirmations (created_by);

-- ---------------------------------------------------------------------------
-- Guard triggers (hold for every caller, including the table owner)
-- ---------------------------------------------------------------------------

-- Insert check for both tables: the brief version belongs to the assignment's project; for
-- confirmations also project_id, editor_id and the copied version number match.
create function private.check_phase7_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_assignment public.assignments;
  v_version public.brief_versions;
begin
  select * into v_assignment from public.assignments where id = new.assignment_id;
  select * into v_version from public.brief_versions where id = new.brief_version_id;
  if v_assignment.id is null or v_version.id is null or v_version.project_id <> v_assignment.project_id then
    raise exception 'This brief version does not belong to the assignment''s project.' using errcode = 'ES409';
  end if;
  if tg_table_name = 'brief_confirmations' then
    if new.project_id is distinct from v_assignment.project_id
       or new.editor_id is distinct from v_assignment.editor_id
       or new.brief_version is distinct from v_version.version then
      raise exception 'This confirmation does not match its assignment and brief version.' using errcode = 'ES409';
    end if;
  end if;
  return new;
end;
$$;

create trigger editor_interpretations_check
  before insert on public.editor_interpretations
  for each row execute function private.check_phase7_row();
create trigger brief_confirmations_check
  before insert on public.brief_confirmations
  for each row execute function private.check_phase7_row();

-- Interpretations: content is immutable. Allowed updates: one review (submitted -> accepted |
-- changes_requested with reviewed_at, only the review columns changing), or clearing exactly one
-- actor column to null (on delete set null). Delete is refused.
create function private.guard_interpretations()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_review_cols text[] := array['status', 'admin_feedback', 'reviewed_by', 'reviewed_at'];
begin
  if tg_op = 'DELETE' then
    raise exception 'This history cannot be deleted.' using errcode = 'ES409';
  end if;
  if old.status = 'submitted' and new.status in ('accepted', 'changes_requested') and new.reviewed_at is not null
     and (to_jsonb(new) - v_review_cols) = (to_jsonb(old) - v_review_cols) then
    return new;
  end if;
  if (old.submitted_by is not null and new.submitted_by is null
      and (to_jsonb(new) - 'submitted_by') = (to_jsonb(old) - 'submitted_by'))
     or (old.reviewed_by is not null and new.reviewed_by is null
      and (to_jsonb(new) - 'reviewed_by') = (to_jsonb(old) - 'reviewed_by')) then
    return new;
  end if;
  raise exception 'This interpretation cannot be changed.' using errcode = 'ES409';
end;
$$;

create trigger editor_interpretations_guard
  before update or delete on public.editor_interpretations
  for each row execute function private.guard_interpretations();
create trigger brief_confirmations_append_only
  before update or delete on public.brief_confirmations
  for each row execute function private.guard_append_only('created_by');

-- ---------------------------------------------------------------------------
-- RLS and privileges: admin, or the owning active editor; select only
-- ---------------------------------------------------------------------------
alter table public.editor_interpretations enable row level security;
alter table public.brief_confirmations enable row level security;

revoke all on public.editor_interpretations, public.brief_confirmations from anon, authenticated;
grant select on public.editor_interpretations, public.brief_confirmations to authenticated;

create policy editor_interpretations_select on public.editor_interpretations
  for select to authenticated
  using ((select private.is_admin())
         or ((select private.is_active_editor())
             and exists (select 1 from public.assignments a
                         where a.id = assignment_id and a.editor_id = (select auth.uid()))));

create policy brief_confirmations_select on public.brief_confirmations
  for select to authenticated
  using ((select private.is_admin())
         or (editor_id = (select auth.uid()) and (select private.is_active_editor())
             and private.editor_project_stage(project_id) <> 'none'));

revoke all on function
  private.assignment_transition_allowed(public.assignment_status, public.assignment_status),
  private.check_phase7_row(), private.guard_interpretations()
from public, anon, authenticated;
