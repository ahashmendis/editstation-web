-- Phase 7 follow-up: admin_archive_project (Phase 4) refuses to archive a project while one of its
-- assignments is confirmed or in progress, so live work is never hidden by an archive. Restore is
-- unchanged. Same signature, body otherwise identical to 20261114051417_phase4_project_status.sql.
create or replace function public.admin_archive_project(p_project_id uuid, p_archive boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_archived_at timestamptz;
  v_found boolean;
begin
  if p_archive is null then
    raise exception 'Please choose whether to archive or restore the project.' using errcode = 'ES422';
  end if;

  select true, archived_at into v_found, v_archived_at
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
  if p_archive and exists (
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

revoke all on function public.admin_archive_project(uuid, boolean) from public, anon, authenticated;
grant execute on function public.admin_archive_project(uuid, boolean) to anon, authenticated;
