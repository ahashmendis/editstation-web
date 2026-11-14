-- Phase 6 (5/5): Phase 4 project status changes. Spec §7 "Phase 4 change"; plan calls 15, 16.
-- - open -> draft is refused once any project_access row or assignment exists (an editor has
--   seen the project), revoked and closed ones included.
-- - cancelled becomes allowed from assigned; cancellation (from draft, open or assigned) closes
--   every live assignment as withdrawn and revokes every live access row. Pay consequences stay
--   question F. assigned stays refused as a target (only admin_confirm_assignment sets it).

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
    when p_from = 'assigned' then p_to = 'cancelled'
    else false
  end;
$$;

create or replace function public.admin_set_project_status(
  p_project_id uuid, p_status public.project_status, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_project public.projects%rowtype;
begin
  if p_status is null then
    raise exception 'Please choose a status.' using errcode = 'ES422';
  end if;

  select * into v_project from public.projects where id = p_project_id for update;
  if v_project.id is null then
    raise exception 'Project not found.' using errcode = 'ES422';
  end if;
  if v_project.archived_at is not null then
    raise exception 'This project is archived. Restore it first.' using errcode = 'ES409';
  end if;
  if not private.project_transition_allowed(v_project.status, p_status, v_project.status_before_hold) then
    raise exception 'A project cannot move from % to % here.',
      replace(v_project.status::text, '_', ' '), replace(p_status::text, '_', ' ')
      using errcode = 'ES409';
  end if;

  if v_project.status = 'open' and p_status = 'draft'
     and (exists (select 1 from public.project_access where project_id = p_project_id)
          or exists (select 1 from public.assignments where project_id = p_project_id)) then
    raise exception 'Editors have already been given access to this project, so it cannot go back to draft.'
      using errcode = 'ES409';
  end if;

  if p_status = 'open' then
    perform private.check_ready_to_open(p_project_id);
  end if;

  update public.projects set
    status = p_status,
    status_before_hold = case when p_status = 'on_hold' then v_project.status end,
    first_opened_at = case when p_status = 'open' then coalesce(first_opened_at, now()) else first_opened_at end
  where id = p_project_id;

  if p_status = 'cancelled' then
    perform private.close_live_assignments(p_project_id, 'withdrawn', v_admin);
    perform private.revoke_live_access(p_project_id, v_admin);
  end if;
end;
$$;

revoke all on function
  private.project_transition_allowed(public.project_status, public.project_status, public.project_status)
from public, anon, authenticated;

revoke all on function public.admin_set_project_status(uuid, public.project_status, text)
from public, anon, authenticated;
grant execute on function public.admin_set_project_status(uuid, public.project_status, text)
to anon, authenticated;
