-- Phase 7 (5/6): brief confirmation and start. Spec §8, §9; plan calls 2, 8, 9, 10, 12.
-- editor_confirm_brief copies the exact version, deadline, deliverables and agreed pay into an
-- immutable row, optimistically: the editor sends the values they were shown and a mismatch is
-- refused. Start (editor or admin) moves the assignment and then the project to in_progress only
-- when the gate is ready; the guard triggers enforce the same gate for every other path.

-- ---------------------------------------------------------------------------
-- editor_confirm_brief
-- ---------------------------------------------------------------------------
create function public.editor_confirm_brief(
  p_assignment_id uuid, p_brief_version int, p_deadline date, p_amount numeric, p_currency text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_editor uuid := private.require_active_editor();
  v public.assignments;
  v_project public.projects;
  v_version public.brief_versions;
  v_amount numeric;
  v_currency char(3);
  g record;
  v_id uuid;
begin
  if not exists (select 1 from public.assignments where id = p_assignment_id and editor_id = v_editor) then
    raise exception 'Assignment not found.' using errcode = 'ES422';
  end if;
  v := private.lock_assignment(p_assignment_id);
  v_project := private.require_working_assignment(v);
  if v_project.deadline is null then
    raise exception 'This project has no deadline yet.' using errcode = 'ES409';
  end if;
  if p_brief_version is null or p_brief_version < 1 then
    raise exception 'Please say which brief version you are confirming.' using errcode = 'ES422';
  end if;
  if p_deadline is null then
    raise exception 'Please include the deadline you are confirming.' using errcode = 'ES422';
  end if;
  v_amount := private.check_amount(p_amount, 'agreed pay');
  if nullif(btrim(p_currency), '') is null then
    raise exception 'Please include the currency of the agreed pay.' using errcode = 'ES422';
  end if;
  v_currency := private.check_currency(p_currency, null);
  if p_brief_version <> v_project.current_brief_version
     or p_deadline <> v_project.deadline
     or v_amount <> v.agreed_amount
     or v_currency <> v.agreed_currency then
    raise exception 'The brief, deadline or pay changed while you were reviewing. Please review it again.'
      using errcode = 'ES409';
  end if;
  select * into g from private.assignment_gate(v.id);
  if g.interpretation_required and not g.interpretation_accepted then
    raise exception 'Your interpretation needs to be accepted first.' using errcode = 'ES409';
  end if;
  if g.brief_confirmed then
    raise exception 'You have already confirmed this brief.' using errcode = 'ES409';
  end if;

  select * into v_version from public.brief_versions
  where project_id = v.project_id and version = v_project.current_brief_version;
  -- confirmed_at is clock_timestamp() so several confirmations in one transaction stay ordered
  -- (private.latest_confirmation orders by it).
  insert into public.brief_confirmations (assignment_id, project_id, editor_id, brief_version_id, brief_version,
    kind, confirmed_deadline, confirmed_deliverables, confirmed_amount, confirmed_currency, created_by,
    confirmed_at)
  values (v.id, v.project_id, v.editor_id, v_version.id, v_version.version, 'confirmed', v_project.deadline,
    v_version.deliverables, v.agreed_amount, v.agreed_currency, v_editor, clock_timestamp())
  returning id into v_id;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_editor, 'brief_confirmation.confirmed', 'brief_confirmation', v_id::text,
    jsonb_build_object('confirmation_id', v_id, 'assignment_id', v.id, 'brief_version', v_version.version,
      'carried_from_id', null));
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Start: shared body (private) behind the editor and admin entry points.
-- ---------------------------------------------------------------------------
create function private.start_work(p_assignment public.assignments, p_actor uuid, p_for_editor boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_project public.projects;
  v_refusal text;
begin
  select * into v_project from public.projects where id = p_assignment.project_id;
  if p_assignment.status = 'in_progress' then
    raise exception 'Work has already started.' using errcode = 'ES409';
  end if;
  if p_assignment.status <> 'confirmed' then
    raise exception 'Work can start only on a confirmed assignment.' using errcode = 'ES409';
  end if;
  if v_project.status <> 'assigned' or v_project.archived_at is not null then
    raise exception 'Work can start only on an assigned project that is not on hold, cancelled or archived.'
      using errcode = 'ES409';
  end if;
  -- The gate also checks the project and the editor's access (same rule as the guard trigger).
  v_refusal := private.gate_refusal(p_assignment.id, p_for_editor);
  if v_refusal is not null then
    raise exception '%', v_refusal using errcode = 'ES409';
  end if;
  update public.assignments set status = 'in_progress', started_at = now(), started_by = p_actor
  where id = p_assignment.id;
  update public.projects set status = 'in_progress' where id = p_assignment.project_id;
end;
$$;

create function public.editor_start_work(p_assignment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_editor uuid := private.require_active_editor();
  v public.assignments;
begin
  if not exists (select 1 from public.assignments where id = p_assignment_id and editor_id = v_editor) then
    raise exception 'Assignment not found.' using errcode = 'ES422';
  end if;
  v := private.lock_assignment(p_assignment_id);
  perform private.start_work(v, v_editor, true);
end;
$$;

create function public.admin_start_work(p_assignment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v public.assignments;
begin
  if not exists (select 1 from public.assignments where id = p_assignment_id) then
    raise exception 'Assignment not found.' using errcode = 'ES422';
  end if;
  v := private.lock_assignment(p_assignment_id);
  perform private.start_work(v, v_admin, false);
end;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges
-- ---------------------------------------------------------------------------
revoke all on function private.start_work(public.assignments, uuid, boolean) from public, anon, authenticated;

revoke all on function
  public.editor_confirm_brief(uuid, int, date, numeric, text),
  public.editor_start_work(uuid),
  public.admin_start_work(uuid)
from public, anon, authenticated;
grant execute on function
  public.editor_confirm_brief(uuid, int, date, numeric, text),
  public.editor_start_work(uuid),
  public.admin_start_work(uuid)
to anon, authenticated;
