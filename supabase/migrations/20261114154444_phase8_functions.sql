-- Phase 8 (2/3): submit, acknowledge, review, classify, approve, complete. Spec §4, §5.
-- Locks: private.lock_assignment (project, then assignment), payments last (Phase 9 order).
-- Facts only: no pay for extra rounds or scope changes (F), no late penalties (KB5).

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Client revisions of a project numbered 1..n by creation; beyond_allowance when n > allowance.
create function private.renumber_client_rounds(p_project_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_allowance int := coalesce((select revision_allowance from public.projects where id = p_project_id), 3);
begin
  update public.revision_requests r
  set round_number = n.rn, beyond_allowance = n.rn > v_allowance
  from (select id, row_number() over (order by created_at, id)::int as rn
        from public.revision_requests where project_id = p_project_id and type = 'client_revision') n
  where r.id = n.id and (r.round_number, r.beyond_allowance) is distinct from (n.rn, n.rn > v_allowance);
end;
$$;

-- The review itself (behind admin_review_submission and admin_approve_project).
create function private.review_submission(p_admin uuid, p_submission_id uuid, p_outcome text, p_feedback text,
  p_type text, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.submissions;
  v public.assignments;
  v_project public.projects;
  v_outcome public.submission_outcome;
  v_type public.revision_type;
  v_feedback text;
  v_reason text;
  v_round int;
  v_id uuid;
begin
  select * into s from public.submissions where id = p_submission_id;
  if s.id is null then
    raise exception 'Submission not found.' using errcode = 'ES422';
  end if;
  v := private.lock_assignment(s.assignment_id);
  select * into s from public.submissions where id = p_submission_id for update;
  select * into v_project from public.projects where id = s.project_id;
  if s.outcome is not null then
    raise exception 'This submission has already been reviewed.' using errcode = 'ES409';
  end if;
  if v.status <> 'in_progress' or v_project.status <> 'in_review' or v_project.archived_at is not null then
    raise exception 'This submission can no longer be reviewed.' using errcode = 'ES409';
  end if;

  if p_outcome is null or p_outcome not in ('approved', 'revision_requested', 'rejected_needs_discussion',
                                            'scope_change_required') then
    raise exception 'Please choose a review outcome.' using errcode = 'ES422';
  end if;
  v_outcome := p_outcome::public.submission_outcome;
  v_feedback := private.clean_text(p_feedback, 4000, 'feedback');
  if v_outcome <> 'approved' and v_feedback is null then
    raise exception 'Feedback for the editor is required unless you approve.' using errcode = 'ES422';
  end if;
  if v_outcome = 'revision_requested' then
    if p_type is null or p_type not in ('client_revision', 'editor_correction') then
      raise exception 'A revision request is a client revision or an editor correction.' using errcode = 'ES422';
    end if;
    v_type := p_type::public.revision_type;
  elsif v_outcome = 'scope_change_required' then
    v_type := 'scope_change';
  elsif v_outcome = 'rejected_needs_discussion' then
    if p_type is null or p_type not in ('client_revision', 'editor_correction', 'scope_change') then
      raise exception 'Please choose client revision, editor correction or scope change.' using errcode = 'ES422';
    end if;
    v_type := p_type::public.revision_type;
  end if;
  if v_outcome <> 'approved' then
    v_reason := private.clean_text(p_reason, 4000, 'reason');
    if v_reason is null then
      raise exception 'Please give the reason for this change request.' using errcode = 'ES422';
    end if;
  end if;

  update public.submissions
  set outcome = v_outcome, feedback = v_feedback, reviewed_by = p_admin, reviewed_at = clock_timestamp()
  where id = s.id;

  if v_outcome = 'approved' then
    update public.revision_requests set status = 'approved', resolved_at = clock_timestamp()
    where id = s.revision_request_id and status = 'resubmitted';
    update public.projects set status = 'approved' where id = s.project_id;
    -- Phase 9 §9 note (spec call 4): approved work makes the agreed pay due for approval.
    update public.payments set status = 'pending_approval'
    where assignment_id = v.id and kind = 'assignment' and status = 'not_due';
    return null;
  end if;

  if v_type = 'client_revision' then
    v_round := 1 + (select count(*) from public.revision_requests
                    where project_id = s.project_id and type = 'client_revision');
  end if;
  insert into public.revision_requests (project_id, assignment_id, submission_id, type, round_number,
    beyond_allowance, reason, status, created_by, classified_by, classified_at)
  values (s.project_id, v.id, s.id, v_type, v_round, coalesce(v_round > v_project.revision_allowance, false),
    v_reason, case when v_outcome = 'rejected_needs_discussion' then 'disputed' else 'requested' end::public.revision_status,
    p_admin, p_admin, clock_timestamp())
  returning id into v_id;
  update public.projects set status = 'revision_requested' where id = s.project_id;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Editor: submit work
-- ---------------------------------------------------------------------------
create function public.editor_submit_work(p_assignment_id uuid, p_link text, p_notes text default null,
  p_export_details text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_editor uuid := private.require_active_editor();
  v public.assignments;
  v_project public.projects;
  v_link text := btrim(p_link, E' \t\r\n');
  v_notes text;
  v_export text;
  v_refusal text;
  v_deadline date;
  v_open public.revision_requests;
  v_version int;
  v_id uuid;
begin
  if not exists (select 1 from public.assignments where id = p_assignment_id and editor_id = v_editor) then
    raise exception 'Assignment not found.' using errcode = 'ES422';
  end if;
  if v_link is null or v_link !~ '^https://[^\s]+$' or char_length(v_link) > 2048 then
    raise exception 'Submission links must start with https:// and be at most 2048 characters.' using errcode = 'ES422';
  end if;
  v_notes := private.clean_text(p_notes, 4000, 'notes');
  v_export := private.clean_text(p_export_details, 2000, 'export details');

  v := private.lock_assignment(p_assignment_id);
  select * into v_project from public.projects where id = v.project_id;
  if v.status = 'confirmed' then
    raise exception 'You can submit work once work has started.' using errcode = 'ES409';
  end if;
  if v.status <> 'in_progress' then
    raise exception 'This assignment is not active.' using errcode = 'ES409';
  end if;
  if exists (select 1 from public.submissions where assignment_id = v.id and outcome is null) then
    raise exception 'Your previous submission is still being reviewed.' using errcode = 'ES409';
  end if;
  if v_project.status not in ('in_progress', 'revision_requested') or v_project.archived_at is not null then
    raise exception 'This project is not accepting submissions.' using errcode = 'ES409';
  end if;
  select * into v_open from public.revision_requests
  where assignment_id = v.id and status in ('requested', 'acknowledged', 'in_progress', 'disputed');
  if v_open.status = 'disputed' then
    raise exception 'Lenscape is still discussing this change request. Please wait before resubmitting.'
      using errcode = 'ES409';
  end if;
  -- Phase 7 gate: a material brief, deadline or pay change needs re-confirmation first.
  v_refusal := private.gate_refusal(v.id, true);
  if v_refusal is not null then
    raise exception '%', v_refusal using errcode = 'ES409';
  end if;

  v_deadline := (private.latest_confirmation(v.id)).confirmed_deadline;
  v_version := 1 + coalesce((select max(version) from public.submissions where project_id = v.project_id), 0);
  insert into public.submissions (assignment_id, project_id, editor_id, version, link, notes, export_details,
    revision_request_id, confirmed_deadline, is_late, submitted_by)
  values (v.id, v.project_id, v.editor_id, v_version, v_link, v_notes, v_export, v_open.id, v_deadline,
    (clock_timestamp() at time zone 'Asia/Colombo')::date > v_deadline, v_editor)
  returning id into v_id;
  if v_open.id is not null then
    update public.revision_requests set status = 'resubmitted', resubmitted_at = clock_timestamp()
    where id = v_open.id;
  end if;
  update public.projects set status = 'in_review' where id = v.project_id;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Editor: acknowledge (or start) a change request
-- ---------------------------------------------------------------------------
create function public.editor_acknowledge_revision(p_revision_id uuid, p_start boolean default false)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_editor uuid := private.require_active_editor();
  r public.revision_requests;
  v public.assignments;
begin
  select rr.* into r from public.revision_requests rr
  join public.assignments a on a.id = rr.assignment_id
  where rr.id = p_revision_id and a.editor_id = v_editor;
  if r.id is null then
    raise exception 'Change request not found.' using errcode = 'ES422';
  end if;
  v := private.lock_assignment(r.assignment_id);
  select * into r from public.revision_requests where id = p_revision_id for update;
  if v.status <> 'in_progress' then
    raise exception 'This assignment is not active.' using errcode = 'ES409';
  end if;
  if r.status = 'disputed' then
    raise exception 'Lenscape is still discussing this change request.' using errcode = 'ES409';
  end if;
  if coalesce(p_start, false) then
    if r.status not in ('requested', 'acknowledged') then
      raise exception 'This change request is already in progress or closed.' using errcode = 'ES409';
    end if;
    update public.revision_requests
    set status = 'in_progress', acknowledged_at = coalesce(acknowledged_at, clock_timestamp())
    where id = r.id;
  else
    if r.status in ('acknowledged', 'in_progress') then
      raise exception 'This change request has already been acknowledged.' using errcode = 'ES409';
    elsif r.status <> 'requested' then
      raise exception 'This change request is closed.' using errcode = 'ES409';
    end if;
    update public.revision_requests set status = 'acknowledged', acknowledged_at = clock_timestamp()
    where id = r.id;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin: review, approve shortcut, classify, complete
-- ---------------------------------------------------------------------------
create function public.admin_review_submission(p_submission_id uuid, p_outcome text, p_feedback text default null,
  p_revision_type text default null, p_reason text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
begin
  return private.review_submission(v_admin, p_submission_id, p_outcome, p_feedback, p_revision_type, p_reason);
end;
$$;

create function public.admin_approve_project(p_project_id uuid, p_feedback text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_id uuid;
begin
  select s.id into v_id from public.submissions s
  join public.assignments a on a.id = s.assignment_id
  where s.project_id = p_project_id and s.outcome is null and a.status = 'in_progress'
  order by s.version desc limit 1;
  if v_id is null then
    raise exception 'There is no submission waiting for review.' using errcode = 'ES409';
  end if;
  perform private.review_submission(v_admin, v_id, 'approved', p_feedback, null, null);
end;
$$;

create function public.admin_classify_revision(p_revision_id uuid, p_type text, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  r public.revision_requests;
  v_type public.revision_type;
  v_reason text;
begin
  select * into r from public.revision_requests where id = p_revision_id;
  if r.id is null then
    raise exception 'Change request not found.' using errcode = 'ES422';
  end if;
  -- Requests stay with a reassigned / withdrawn assignment as history; only live work is classified.
  if (private.lock_assignment(r.assignment_id)).status <> 'in_progress' then
    raise exception 'This change request belongs to an assignment that is no longer active.' using errcode = 'ES409';
  end if;
  select * into r from public.revision_requests where id = p_revision_id for update;
  if r.status not in ('requested', 'acknowledged', 'in_progress', 'disputed') then
    raise exception 'Only an open change request can be reclassified.' using errcode = 'ES409';
  end if;
  if p_type is null or p_type not in ('client_revision', 'editor_correction', 'scope_change') then
    raise exception 'Please choose client revision, editor correction or scope change.' using errcode = 'ES422';
  end if;
  v_type := p_type::public.revision_type;
  v_reason := private.clean_text(p_reason, 4000, 'reason');
  if v_reason is null then
    raise exception 'Please give the reason for this change request.' using errcode = 'ES422';
  end if;
  update public.revision_requests
  set type = v_type, reason = v_reason,
      round_number = case when v_type = 'client_revision' then coalesce(round_number, 1) end,
      beyond_allowance = case when v_type = 'client_revision' then beyond_allowance else false end,
      classified_by = v_admin, classified_at = clock_timestamp(),
      status = case when status = 'disputed' then 'requested'::public.revision_status else status end
  where id = r.id;
  perform private.renumber_client_rounds(r.project_id);
end;
$$;

create function public.admin_complete_project(p_project_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_project public.projects;
begin
  select * into v_project from public.projects where id = p_project_id for update;
  if v_project.id is null then
    raise exception 'Project not found.' using errcode = 'ES422';
  end if;
  if v_project.archived_at is not null then
    raise exception 'This project is archived. Restore it first.' using errcode = 'ES409';
  end if;
  if v_project.status <> 'approved' then
    raise exception 'Only an approved project can be completed.' using errcode = 'ES409';
  end if;
  update public.projects set status = 'completed' where id = p_project_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges
-- ---------------------------------------------------------------------------
revoke all on function
  private.renumber_client_rounds(uuid), private.review_submission(uuid, uuid, text, text, text, text)
from public, anon, authenticated;

revoke all on function
  public.editor_submit_work(uuid, text, text, text),
  public.editor_acknowledge_revision(uuid, boolean),
  public.admin_review_submission(uuid, text, text, text, text),
  public.admin_approve_project(uuid, text),
  public.admin_classify_revision(uuid, text, text),
  public.admin_complete_project(uuid)
from public, anon, authenticated;
grant execute on function
  public.editor_submit_work(uuid, text, text, text),
  public.editor_acknowledge_revision(uuid, boolean),
  public.admin_review_submission(uuid, text, text, text, text),
  public.admin_approve_project(uuid, text),
  public.admin_classify_revision(uuid, text, text),
  public.admin_complete_project(uuid)
to anon, authenticated;
