-- Phase 8 (3/3): Phase 4/6/7 functions widened for the review statuses. Spec §4. Each body is a
-- copy of 20261114121138_phase7_phase6_changes.sql / 20261114120611_phase7_interpretations.sql
-- with only the status lists changed. Same signatures, same privileges.

-- in_review and revision_requested may be cancelled (on_hold stays refused, as for in_progress).
create or replace function private.project_transition_allowed(
  p_from public.project_status, p_to public.project_status, p_before_hold public.project_status)
returns boolean
language sql
immutable
security definer
set search_path = ''
as $$
  select case
    when p_from = 'draft' then p_to in ('open', 'cancelled', 'on_hold')
    when p_from = 'open' then p_to in ('draft', 'cancelled', 'on_hold')
    when p_from = 'on_hold' then p_before_hold is not null and p_to = p_before_hold
    when p_from in ('assigned', 'in_progress', 'in_review', 'revision_requested') then p_to = 'cancelled'
    else false
  end;
$$;

-- The editor of a project in review or revision can still be reassigned (history stays with the
-- old assignment).
create or replace function public.admin_reassign(p_assignment_id uuid, p_message text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v public.assignments;
  v_message text;
begin
  v := private.lock_assignment(p_assignment_id);
  if v.status not in ('confirmed', 'in_progress')
     or not exists (select 1 from public.projects
                    where id = v.project_id and status in ('assigned', 'in_progress', 'in_review', 'revision_requested')
                      and archived_at is null) then
    raise exception 'Only the confirmed editor of an assigned or in-progress project can be reassigned.'
      using errcode = 'ES409';
  end if;
  v_message := private.clean_text(p_message, 2000, 'message');
  update public.assignments set status = 'reassigned', closed_at = now() where id = v.id;
  perform private.add_negotiation(v.id, 'admin', 'withdraw', null, null, v_message, v_admin);
  update public.projects set status = 'open' where id = v.project_id;
  perform private.revoke_live_access(v.project_id, v_admin, v.editor_id);
end;
$$;

-- Archive guard (20261114143056_phase7_archive_guard.sql): the assignment stays in_progress after
-- completion (spec §7 call 3), so a completed or cancelled project is archivable regardless.
create or replace function public.admin_archive_project(p_project_id uuid, p_archive boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_archived_at timestamptz;
  v_status public.project_status;
  v_found boolean;
begin
  if p_archive is null then
    raise exception 'Please choose whether to archive or restore the project.' using errcode = 'ES422';
  end if;

  select true, archived_at, status into v_found, v_archived_at, v_status
  from public.projects where id = p_project_id for update;
  if v_found is null then
    raise exception 'Project not found.' using errcode = 'ES422';
  end if;
  if p_archive and v_archived_at is not null then
    raise exception 'This project is already archived.' using errcode = 'ES409';
  end if;
  if not p_archive and v_archived_at is null then
    raise exception 'This project is not archived.' using errcode = 'ES409';
  end if;
  if p_archive and v_status not in ('completed', 'cancelled') and exists (
      select 1 from public.assignments a
      where a.project_id = p_project_id and a.status in ('confirmed', 'in_progress')) then
    raise exception 'Cancel or finish the assignment before archiving.' using errcode = 'ES409';
  end if;

  update public.projects set archived_at = case when p_archive then now() end where id = p_project_id;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, case when p_archive then 'project.archived' else 'project.restored' end,
          'project', p_project_id::text, jsonb_build_object('project_id', p_project_id));
end;
$$;

-- Interpretation and brief confirmation stay available while the work is in review or revision
-- (a material brief change then needs re-confirmation before the next submission).
create or replace function private.require_working_assignment(p_assignment public.assignments)
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
  if v_project.status not in ('assigned', 'in_progress', 'in_review', 'revision_requested')
     or v_project.archived_at is not null then
    raise exception 'This project is not active, so this step is not available.' using errcode = 'ES409';
  end if;
  return v_project;
end;
$$;
