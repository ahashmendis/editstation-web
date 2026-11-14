-- Phase 7 (4/6): interpretations. Spec §8; plan calls 7, 8, 9, 12.
-- The editor writes what they will reproduce, what they will adapt and any questions (KB §4.2);
-- the admin accepts or asks for changes. Every submission is a new row; content never changes.
-- Audit details hold ids and the version number only, never the text.

-- Call 9: interpretation and brief confirmation need an assignment that is confirmed or in
-- progress on a project that is assigned or in progress and not archived.
create function private.require_working_assignment(p_assignment public.assignments)
returns public.projects
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_project public.projects;
begin
  select * into v_project from public.projects where id = p_assignment.project_id;
  if p_assignment.status not in ('confirmed', 'in_progress') then
    raise exception 'This assignment is not confirmed.' using errcode = 'ES409';
  end if;
  if v_project.status not in ('assigned', 'in_progress') or v_project.archived_at is not null then
    raise exception 'This project is not active, so this step is not available.' using errcode = 'ES409';
  end if;
  return v_project;
end;
$$;

-- ---------------------------------------------------------------------------
-- editor_submit_interpretation
-- ---------------------------------------------------------------------------
create function public.editor_submit_interpretation(
  p_assignment_id uuid, p_brief_version int, p_will_reproduce text, p_will_adapt text, p_questions text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_editor uuid := private.require_active_editor();
  v public.assignments;
  v_project public.projects;
  v_version_id uuid;
  v_reproduce text;
  v_adapt text;
  v_questions text;
  v_id uuid;
begin
  -- Ownership first, without locks (same message for another editor's and an unknown id).
  if not exists (select 1 from public.assignments where id = p_assignment_id and editor_id = v_editor) then
    raise exception 'Assignment not found.' using errcode = 'ES422';
  end if;
  v := private.lock_assignment(p_assignment_id);
  v_project := private.require_working_assignment(v);
  if not v_project.requires_interpretation then
    raise exception 'This project does not need an interpretation.' using errcode = 'ES409';
  end if;
  if p_brief_version is null or p_brief_version < 1 then
    raise exception 'Please say which brief version you reviewed.' using errcode = 'ES422';
  end if;
  if p_brief_version <> v_project.current_brief_version then
    raise exception 'The brief changed; review it again.' using errcode = 'ES409';
  end if;
  v_reproduce := private.clean_text(p_will_reproduce, 4000, 'description of what you will reproduce');
  v_adapt := private.clean_text(p_will_adapt, 4000, 'description of what you will adapt');
  v_questions := private.clean_text(p_questions, 4000, 'questions or limitations');
  if v_reproduce is null and v_adapt is null then
    raise exception 'Please describe what you will reproduce or what you will adapt.' using errcode = 'ES422';
  end if;
  if exists (select 1 from public.editor_interpretations where assignment_id = v.id and status = 'submitted') then
    raise exception 'Your interpretation is waiting for review.' using errcode = 'ES409';
  end if;
  if (select g.interpretation_accepted from private.assignment_gate(v.id) g) then
    raise exception 'Your interpretation has already been accepted.' using errcode = 'ES409';
  end if;

  select id into v_version_id from public.brief_versions
  where project_id = v.project_id and version = v_project.current_brief_version;
  begin
    insert into public.editor_interpretations (assignment_id, brief_version_id, will_reproduce, will_adapt,
      questions_limitations, submitted_by)
    values (v.id, v_version_id, v_reproduce, v_adapt, v_questions, v_editor)
    returning id into v_id;
  exception
    when check_violation then
      raise exception 'Please check your entries: some values are invalid or too long.' using errcode = 'ES422';
    when unique_violation then
      raise exception 'Your interpretation is waiting for review.' using errcode = 'ES409';
  end;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_editor, 'interpretation.submitted', 'interpretation', v_id::text,
    jsonb_build_object('interpretation_id', v_id, 'assignment_id', v.id, 'brief_version', p_brief_version));
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_review_interpretation
-- ---------------------------------------------------------------------------
create function public.admin_review_interpretation(
  p_interpretation_id uuid, p_decision text, p_feedback text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_assignment_id uuid;
  v public.assignments;
  v_row public.editor_interpretations;
  v_version int;
  v_feedback text;
  v_status public.interpretation_status;
begin
  if p_decision is null or p_decision not in ('accept', 'request_changes') then
    raise exception 'Please choose accept or request changes.' using errcode = 'ES422';
  end if;
  select assignment_id into v_assignment_id from public.editor_interpretations where id = p_interpretation_id;
  if v_assignment_id is null then
    raise exception 'Interpretation not found.' using errcode = 'ES422';
  end if;
  -- Lock order: project, assignment, then the interpretation row.
  v := private.lock_assignment(v_assignment_id);
  select * into v_row from public.editor_interpretations where id = p_interpretation_id for update;
  if v_row.status <> 'submitted' then
    raise exception 'This interpretation has already been reviewed.' using errcode = 'ES409';
  end if;
  if v.status not in ('confirmed', 'in_progress') then
    raise exception 'This assignment is no longer active.' using errcode = 'ES409';
  end if;
  v_feedback := private.clean_text(p_feedback, 4000, 'feedback');
  if p_decision = 'request_changes' then
    if v_feedback is null then
      raise exception 'Please explain what the editor should change.' using errcode = 'ES422';
    end if;
    v_status := 'changes_requested';
  else
    select version into v_version from public.brief_versions where id = v_row.brief_version_id;
    if v_version < coalesce(private.material_brief_version(v.project_id), 1) then
      raise exception 'The brief changed after this interpretation was written. Ask the editor for a new one.'
        using errcode = 'ES409';
    end if;
    v_status := 'accepted';
  end if;

  update public.editor_interpretations
  set status = v_status, admin_feedback = v_feedback, reviewed_by = v_admin, reviewed_at = now()
  where id = v_row.id;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'interpretation.' || v_status::text, 'interpretation', v_row.id::text,
    jsonb_build_object('interpretation_id', v_row.id, 'assignment_id', v.id,
      'brief_version', (select version from public.brief_versions where id = v_row.brief_version_id)));
end;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges
-- ---------------------------------------------------------------------------
revoke all on function private.require_working_assignment(public.assignments) from public, anon, authenticated;

revoke all on function
  public.editor_submit_interpretation(uuid, int, text, text, text),
  public.admin_review_interpretation(uuid, text, text)
from public, anon, authenticated;
grant execute on function
  public.editor_submit_interpretation(uuid, int, text, text, text),
  public.admin_review_interpretation(uuid, text, text)
to anon, authenticated;
