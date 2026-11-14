-- Phase 8 (1/3): submissions and revision requests. Spec
-- docs/superpowers/specs/2026-11-14-phase8-submissions-design.md §2, §3, §5, §6.
-- Both tables: select-only grants, one admin-or-own-editor policy, no write grants; every write
-- goes through security definer functions (next migration). Neither table holds client data,
-- client pricing or money. Facts only (F, KB5): rounds, beyond-allowance flag, late flag.

create type public.submission_outcome as enum (
  'approved', 'revision_requested', 'rejected_needs_discussion', 'scope_change_required');
create type public.revision_type as enum ('client_revision', 'editor_correction', 'scope_change');
create type public.revision_status as enum (
  'requested', 'acknowledged', 'in_progress', 'resubmitted', 'approved', 'disputed');

-- ---------------------------------------------------------------------------
-- Submissions (append-only; one row per version; KB §6.2)
-- ---------------------------------------------------------------------------
create table public.submissions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments (id) on delete restrict,
  project_id uuid not null references public.projects (id) on delete restrict,
  editor_id uuid not null references public.editor_profiles (user_id) on delete restrict,
  -- Numbered per project (spec call 1).
  version int not null check (version >= 1),
  link text not null check (link ~ '^https://[^\s]+$' and char_length(link) <= 2048),
  notes text check (char_length(notes) between 1 and 4000),
  export_details text check (char_length(export_details) between 1 and 2000),
  -- The change request this submission answers (FK added below).
  revision_request_id uuid,
  -- Copied from the editor's latest brief confirmation; is_late compares the Asia/Colombo date.
  confirmed_deadline date not null,
  is_late boolean not null,
  submitted_by uuid references public.profiles (id) on delete set null,
  submitted_at timestamptz not null default clock_timestamp(),
  outcome public.submission_outcome,
  -- Written for the editor.
  feedback text check (char_length(feedback) between 1 and 4000),
  reviewed_by uuid references public.profiles (id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint submissions_version_key unique (project_id, version),
  constraint submissions_review_chk check (
    (outcome is null) = (reviewed_at is null)
    and (outcome is null or outcome = 'approved' or feedback is not null)
    and (outcome is not null or (feedback is null and reviewed_by is null)))
);
create unique index submissions_pending_key on public.submissions (assignment_id) where outcome is null;
create index submissions_assignment_idx on public.submissions (assignment_id, version);
create index submissions_editor_idx on public.submissions (editor_id);
create index submissions_revision_request_idx on public.submissions (revision_request_id);
create index submissions_submitted_by_idx on public.submissions (submitted_by);
create index submissions_reviewed_by_idx on public.submissions (reviewed_by);

-- ---------------------------------------------------------------------------
-- Revision requests (KB §6.1, §10.3). Classification and status change only through functions.
-- ---------------------------------------------------------------------------
create table public.revision_requests (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  assignment_id uuid not null references public.assignments (id) on delete restrict,
  -- The reviewed submission that led to this request.
  submission_id uuid not null references public.submissions (id) on delete restrict,
  type public.revision_type not null,
  counts_against_allowance boolean generated always as (type = 'client_revision') stored,
  round_number int check (round_number >= 1),
  beyond_allowance boolean not null default false,
  -- Written for the editor.
  reason text not null check (char_length(reason) between 1 and 4000),
  status public.revision_status not null default 'requested',
  acknowledged_at timestamptz,
  resubmitted_at timestamptz,
  resolved_at timestamptz,
  created_by uuid references public.profiles (id) on delete set null,
  classified_by uuid references public.profiles (id) on delete set null,
  classified_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default now(),
  constraint revision_requests_round_chk check (
    (type = 'client_revision') = (round_number is not null)
    and (not beyond_allowance or type = 'client_revision')),
  constraint revision_requests_status_chk check (
    (status not in ('resubmitted', 'approved') or resubmitted_at is not null)
    and ((status = 'approved') = (resolved_at is not null)))
);
create unique index revision_requests_open_key on public.revision_requests (assignment_id)
  where status in ('requested', 'acknowledged', 'in_progress', 'disputed');
create index revision_requests_project_idx on public.revision_requests (project_id, created_at);
create index revision_requests_submission_idx on public.revision_requests (submission_id);
create index revision_requests_created_by_idx on public.revision_requests (created_by);
create index revision_requests_classified_by_idx on public.revision_requests (classified_by);
create trigger revision_requests_set_updated_at
  before update on public.revision_requests
  for each row execute function private.set_updated_at();

alter table public.submissions
  add constraint submissions_revision_request_fkey
  foreign key (revision_request_id) references public.revision_requests (id) on delete restrict;

-- ---------------------------------------------------------------------------
-- Insert checks: rows match their assignment (and the request its submission).
-- ---------------------------------------------------------------------------
create function private.check_submission_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.assignments;
begin
  select * into v from public.assignments where id = new.assignment_id;
  if v.id is null or v.project_id <> new.project_id or v.editor_id <> new.editor_id then
    raise exception 'A submission must match its assignment.' using errcode = 'ES409';
  end if;
  if new.revision_request_id is not null and not exists (
    select 1 from public.revision_requests r where r.id = new.revision_request_id and r.assignment_id = new.assignment_id) then
    raise exception 'A submission can only answer a change request of its own assignment.' using errcode = 'ES409';
  end if;
  return new;
end;
$$;

create trigger submissions_check_row
  before insert on public.submissions
  for each row execute function private.check_submission_row();

create function private.check_revision_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.submissions s
                 where s.id = new.submission_id and s.assignment_id = new.assignment_id
                   and s.project_id = new.project_id) then
    raise exception 'A change request must match its submission.' using errcode = 'ES409';
  end if;
  return new;
end;
$$;

create trigger revision_requests_check_row
  before insert on public.revision_requests
  for each row execute function private.check_revision_row();

-- ---------------------------------------------------------------------------
-- Guards (hold for every caller, including the table owner)
-- ---------------------------------------------------------------------------

-- Submissions: content immutable. Allowed: one review (outcome null -> set, only the review
-- columns changing) or clearing one actor column (on delete set null).
create function private.guard_submissions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_review_cols text[] := array['outcome', 'feedback', 'reviewed_by', 'reviewed_at'];
begin
  if tg_op = 'DELETE' then
    raise exception 'This history cannot be deleted.' using errcode = 'ES409';
  end if;
  if old.outcome is null and new.outcome is not null and new.reviewed_at is not null
     and (to_jsonb(new) - v_review_cols) = (to_jsonb(old) - v_review_cols) then
    return new;
  end if;
  if (old.submitted_by is not null and new.submitted_by is null
      and (to_jsonb(new) - 'submitted_by') = (to_jsonb(old) - 'submitted_by'))
     or (old.reviewed_by is not null and new.reviewed_by is null
      and (to_jsonb(new) - 'reviewed_by') = (to_jsonb(old) - 'reviewed_by')) then
    return new;
  end if;
  raise exception 'This submission cannot be changed.' using errcode = 'ES409';
end;
$$;

create trigger submissions_guard
  before update or delete on public.submissions
  for each row execute function private.guard_submissions();

-- Revision lifecycle (spec §5). in_progress may be reached straight from requested.
create function private.revision_transition_allowed(p_from public.revision_status, p_to public.revision_status)
returns boolean
language sql
immutable
security definer
set search_path = ''
as $$
  select coalesce(case
    when p_from = 'requested' then p_to in ('acknowledged', 'in_progress', 'resubmitted')
    when p_from = 'acknowledged' then p_to in ('in_progress', 'resubmitted')
    when p_from = 'in_progress' then p_to = 'resubmitted'
    when p_from = 'resubmitted' then p_to = 'approved'
    when p_from = 'disputed' then p_to = 'requested'
    else false
  end, false);
$$;

create function private.guard_revision_requests()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'This history cannot be deleted.' using errcode = 'ES409';
  end if;
  if (new.id, new.project_id, new.assignment_id, new.submission_id, new.created_at)
     is distinct from (old.id, old.project_id, old.assignment_id, old.submission_id, old.created_at)
     or (new.created_by is distinct from old.created_by and new.created_by is not null) then
    raise exception 'This part of a revision request cannot change.' using errcode = 'ES409';
  end if;
  if new.status is distinct from old.status and not private.revision_transition_allowed(old.status, new.status) then
    raise exception 'This change request cannot move from % to %.',
      replace(old.status::text, '_', ' '), replace(new.status::text, '_', ' ') using errcode = 'ES409';
  end if;
  return new;
end;
$$;

create trigger revision_requests_guard
  before update or delete on public.revision_requests
  for each row execute function private.guard_revision_requests();

-- Projects: the review statuses need their facts, whoever updates (spec §5).
create function private.guard_project_review_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status is not distinct from old.status then
    return new;
  end if;
  if new.status = 'in_review' and not exists (
    select 1 from public.submissions s join public.assignments a on a.id = s.assignment_id
    where s.project_id = new.id and s.outcome is null and a.status = 'in_progress') then
    raise exception 'A project goes into review only when work is submitted.' using errcode = 'ES409';
  elsif new.status = 'revision_requested' and not exists (
    select 1 from public.revision_requests r join public.assignments a on a.id = r.assignment_id
    where r.project_id = new.id and a.status = 'in_progress'
      and r.status in ('requested', 'acknowledged', 'in_progress', 'disputed')) then
    raise exception 'A project needs an open change request to be in revision.' using errcode = 'ES409';
  elsif new.status = 'approved' and coalesce((
    select s.outcome = 'approved' from public.submissions s where s.project_id = new.id
    order by s.version desc limit 1), false) is false then
    raise exception 'A project is approved only through an approved submission.' using errcode = 'ES409';
  elsif new.status = 'completed' and old.status <> 'approved' then
    raise exception 'Only an approved project can be completed.' using errcode = 'ES409';
  end if;
  return new;
end;
$$;

create trigger guard_project_review_status
  before update of status on public.projects
  for each row execute function private.guard_project_review_status();

-- ---------------------------------------------------------------------------
-- Audit (ids, version, flags and enum names only: never links, notes, feedback, reasons, dates)
-- ---------------------------------------------------------------------------
create function private.audit_phase8()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select p.id from public.profiles p where p.id = (select auth.uid()));
begin
  if tg_table_name = 'submissions' then
    if tg_op = 'INSERT' then
      insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
      values (v_actor, 'submission.submitted', 'submission', new.id::text, jsonb_build_object(
        'submission_id', new.id, 'assignment_id', new.assignment_id, 'project_id', new.project_id,
        'version', new.version, 'is_late', new.is_late));
    elsif old.outcome is null and new.outcome is not null then
      insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
      values (v_actor, 'submission.reviewed', 'submission', new.id::text, jsonb_build_object(
        'submission_id', new.id, 'assignment_id', new.assignment_id, 'project_id', new.project_id,
        'version', new.version, 'outcome', new.outcome));
    end if;
  else
    if tg_op = 'INSERT' then
      insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
      values (v_actor, 'revision_request.created', 'revision_request', new.id::text, jsonb_build_object(
        'revision_request_id', new.id, 'submission_id', new.submission_id, 'assignment_id', new.assignment_id,
        'project_id', new.project_id, 'type', new.type, 'to', new.status, 'round_number', new.round_number));
    elsif new.classified_at is distinct from old.classified_at then
      insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
      values (v_actor, 'revision_request.classified', 'revision_request', new.id::text, jsonb_build_object(
        'revision_request_id', new.id, 'assignment_id', new.assignment_id, 'project_id', new.project_id,
        'from', old.type, 'to', new.type, 'round_number', new.round_number));
    elsif new.status is distinct from old.status then
      insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
      values (v_actor, 'revision_request.' || new.status::text, 'revision_request', new.id::text, jsonb_build_object(
        'revision_request_id', new.id, 'assignment_id', new.assignment_id, 'project_id', new.project_id,
        'from', old.status, 'to', new.status));
    end if;
  end if;
  return null;
end;
$$;

create trigger submissions_audit
  after insert or update on public.submissions
  for each row execute function private.audit_phase8();
create trigger revision_requests_audit
  after insert or update on public.revision_requests
  for each row execute function private.audit_phase8();

-- ---------------------------------------------------------------------------
-- RLS and privileges: admin, or the owning active editor while the project is visible to them
-- ---------------------------------------------------------------------------
alter table public.submissions enable row level security;
alter table public.revision_requests enable row level security;

revoke all on public.submissions, public.revision_requests from anon, authenticated;
grant select on public.submissions, public.revision_requests to authenticated;

create policy submissions_select on public.submissions
  for select to authenticated
  using ((select private.is_admin())
         or (editor_id = (select auth.uid()) and private.editor_project_stage(project_id) <> 'none'));

create policy revision_requests_select on public.revision_requests
  for select to authenticated
  using ((select private.is_admin())
         or (exists (select 1 from public.assignments a
                     where a.id = assignment_id and a.editor_id = (select auth.uid()))
             and private.editor_project_stage(project_id) <> 'none'));

revoke all on function
  private.check_submission_row(), private.check_revision_row(), private.guard_submissions(),
  private.revision_transition_allowed(public.revision_status, public.revision_status),
  private.guard_revision_requests(), private.guard_project_review_status(), private.audit_phase8()
from public, anon, authenticated;
