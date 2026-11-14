-- Phase 6 (2/5): editor authorisation helper, editor stage and tiered editor read policies.
-- Spec §6 (decision B). Plan calls 4, 5, 6.
-- Stage per (caller, project): none / opportunity / assigned. A suspended or revoked editor is
-- `none` everywhere and loses even their own history (private.is_active_editor()).

-- ---------------------------------------------------------------------------
-- require_active_editor: first statement of every public.editor_* function.
-- ---------------------------------------------------------------------------
create function private.require_active_editor()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
begin
  if not private.is_active_editor() then
    raise exception 'Your editor access is not active.' using errcode = 'ES403';
  end if;
  return v_uid;
end;
$$;

revoke all on function private.require_active_editor() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- editor_project_stage. Cancelled and archived projects are `none` in every case, a confirmed
-- editor included (plan call 4); restoring an archived project restores visibility.
-- ---------------------------------------------------------------------------
create function private.editor_project_stage(p_project_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when not private.is_active_editor() then 'none'
    when not exists (
      select 1 from public.projects p
      where p.id = p_project_id and p.status <> 'cancelled' and p.archived_at is null) then 'none'
    when exists (
      select 1 from public.assignments a
      where a.project_id = p_project_id and a.editor_id = (select auth.uid()) and a.status = 'confirmed')
      then 'assigned'
    when exists (
      select 1 from public.project_access pa
      where pa.project_id = p_project_id and pa.editor_id = (select auth.uid()) and pa.revoked_at is null)
      or exists (
      select 1 from public.assignments a
      where a.project_id = p_project_id and a.editor_id = (select auth.uid())
        and a.status in ('offered', 'counteroffer_pending', 'accepted'))
      then 'opportunity'
    else 'none'
  end;
$$;

-- RLS policies call it as the API role. anon has no select grant on any table that uses it.
-- Grant first, then revoke PUBLIC (a missing EXECUTE in a policy crashes this Postgres image).
grant execute on function private.editor_project_stage(uuid) to authenticated;
revoke all on function private.editor_project_stage(uuid) from public, anon;

-- ---------------------------------------------------------------------------
-- Read policies: one combined select policy per table (admin or editor), replacing the
-- admin-only ones, as in Phase 2 (`... or (select private.is_admin())`); two permissive
-- policies per table would trip the multiple_permissive_policies advisor. The per-row stage
-- call takes a column argument, so it cannot be wrapped in (select ...).
-- ---------------------------------------------------------------------------
drop policy projects_select_admin on public.projects;
create policy projects_select on public.projects
  for select to authenticated
  using ((select private.is_admin())
         or private.editor_project_stage(id) in ('opportunity', 'assigned'));

drop policy project_deliverables_select_admin on public.project_deliverables;
create policy project_deliverables_select on public.project_deliverables
  for select to authenticated
  using ((select private.is_admin())
         or private.editor_project_stage(project_id) in ('opportunity', 'assigned'));

drop policy project_references_select_admin on public.project_references;
create policy project_references_select on public.project_references
  for select to authenticated
  using ((select private.is_admin())
         or private.editor_project_stage(project_id) = 'assigned'
         or (early_access and private.editor_project_stage(project_id) = 'opportunity'));

drop policy project_assets_select_admin on public.project_assets;
create policy project_assets_select on public.project_assets
  for select to authenticated
  using ((select private.is_admin())
         or private.editor_project_stage(project_id) = 'assigned'
         or (early_access and private.editor_project_stage(project_id) = 'opportunity'));

drop policy brief_versions_select_admin on public.brief_versions;
create policy brief_versions_select on public.brief_versions
  for select to authenticated
  using ((select private.is_admin()) or private.editor_project_stage(project_id) = 'assigned');

drop policy assignments_select_admin on public.assignments;
create policy assignments_select on public.assignments
  for select to authenticated
  using ((select private.is_admin())
         or (editor_id = (select auth.uid()) and (select private.is_active_editor())));

drop policy project_access_select_admin on public.project_access;
create policy project_access_select on public.project_access
  for select to authenticated
  using ((select private.is_admin())
         or (editor_id = (select auth.uid()) and (select private.is_active_editor())));

drop policy negotiation_offers_select_admin on public.negotiation_offers;
create policy negotiation_offers_select on public.negotiation_offers
  for select to authenticated
  using ((select private.is_admin())
         or ((select private.is_active_editor())
             and exists (select 1 from public.assignments a
                         where a.id = assignment_id and a.editor_id = (select auth.uid()))));
