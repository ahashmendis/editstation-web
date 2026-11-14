-- Phase 7 (6/6): Phase 6 and Phase 4 functions updated for in_progress. Spec §8, §9; plan calls
-- 13, 14, 15. Each body is a copy of 20261114062924_phase6_admin_negotiation.sql /
-- 20261114063650_phase6_project_status_changes.sql with only the status lists (and the reassign
-- message) changed. Same signatures, same privileges.

-- Withdrawn also closes in_progress (project cancellation).
create or replace function private.close_live_assignments(
  p_project_id uuid, p_to public.assignment_status, p_actor uuid, p_editor_id uuid default null,
  p_except_assignment uuid default null)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  n int := 0;
begin
  if p_to is null or p_to not in ('withdrawn', 'not_selected') then
    raise exception 'Offers can only be closed as withdrawn or not selected.' using errcode = 'ES422';
  end if;
  for r in
    select a.id from public.assignments a
    where a.project_id = p_project_id
      and (p_editor_id is null or a.editor_id = p_editor_id)
      and (p_except_assignment is null or a.id <> p_except_assignment)
      and (a.status in ('offered', 'counteroffer_pending', 'accepted')
           or (p_to = 'withdrawn' and a.status in ('confirmed', 'in_progress')))
    order by a.id
    for update
  loop
    update public.assignments set status = p_to, closed_at = now() where id = r.id;
    if p_to = 'withdrawn' then
      perform private.add_negotiation(r.id, 'admin', 'withdraw', null, null, null, p_actor);
    end if;
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- Adds in_progress -> cancelled (call 15). in_progress stays refused as a target here.
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
    when p_from = 'in_progress' then p_to = 'cancelled'
    else false
  end;
$$;

create or replace function public.admin_revoke_project_access(p_project_id uuid, p_editor_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_closed int;
  v_revoked int;
begin
  perform 1 from public.projects where id = p_project_id for update;
  if not found then
    raise exception 'Project not found.' using errcode = 'ES422';
  end if;
  if exists (select 1 from public.assignments
             where project_id = p_project_id and editor_id = p_editor_id and status in ('confirmed', 'in_progress')) then
    raise exception 'This editor is confirmed on the project. Use reassign instead.' using errcode = 'ES409';
  end if;
  v_closed := private.close_live_assignments(p_project_id, 'withdrawn', v_admin, p_editor_id);
  v_revoked := private.revoke_live_access(p_project_id, v_admin, p_editor_id);
  if v_closed + v_revoked = 0 then
    raise exception 'This editor has no access to this project.' using errcode = 'ES409';
  end if;
end;
$$;

create or replace function public.admin_make_offer(
  p_project_id uuid, p_editor_id uuid, p_amount numeric, p_currency text default null,
  p_message text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_project public.projects;
  v_live public.assignments;
  v_amount numeric;
  v_currency char(3);
  v_message text;
  v_id uuid;
begin
  select * into v_project from public.projects where id = p_project_id for update;
  if v_project.id is null then
    raise exception 'Project not found.' using errcode = 'ES422';
  end if;
  perform private.require_negotiable_project(p_project_id);
  if p_editor_id = v_admin then
    raise exception 'You cannot make an offer to yourself.' using errcode = 'ES422';
  end if;
  if not exists (select 1 from public.editor_profiles where user_id = p_editor_id and access_status = 'active') then
    raise exception 'Choose an active editor.' using errcode = 'ES422';
  end if;
  v_amount := private.check_amount(p_amount, 'offer amount');
  v_message := private.clean_text(p_message, 2000, 'message');

  select * into v_live from public.assignments
  where project_id = p_project_id and editor_id = p_editor_id
    and status in ('offered', 'counteroffer_pending', 'accepted', 'confirmed', 'in_progress')
  for update;
  if v_live.id is not null then
    if v_live.status <> 'counteroffer_pending' then
      raise exception 'This editor already has a live offer on this project.' using errcode = 'ES409';
    end if;
    perform private.admin_counter(v_live, v_amount, p_currency, v_message, v_admin);
    return v_live.id;
  end if;

  v_currency := private.check_currency(p_currency, v_project.proposed_currency);
  perform private.ensure_access(p_project_id, p_editor_id, 'invited', v_admin);
  begin
    insert into public.assignments (project_id, editor_id, status, proposed_amount, currency)
    values (p_project_id, p_editor_id, 'offered', v_amount, v_currency)
    returning id into v_id;
  exception
    when unique_violation then
      raise exception 'This editor already has a live offer on this project.' using errcode = 'ES409';
  end;
  perform private.add_negotiation(v_id, 'admin', 'offer', v_amount, v_currency, v_message, v_admin);
  return v_id;
end;
$$;

create or replace function public.admin_withdraw_offer(p_assignment_id uuid, p_message text default null)
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
  if v.status in ('confirmed', 'in_progress') then
    raise exception 'This editor is confirmed. Use reassign instead.' using errcode = 'ES409';
  end if;
  if v.status not in ('offered', 'counteroffer_pending', 'accepted') then
    raise exception 'This offer is already closed.' using errcode = 'ES409';
  end if;
  v_message := private.clean_text(p_message, 2000, 'message');
  update public.assignments set status = 'withdrawn', closed_at = now() where id = v.id;
  perform private.add_negotiation(v.id, 'admin', 'withdraw', null, null, v_message, v_admin);
end;
$$;

-- Reassign from confirmed or in_progress (call 13); project assigned or in_progress -> open.
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
                    where id = v.project_id and status in ('assigned', 'in_progress') and archived_at is null) then
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

-- Revoke checklist: the active set includes in_progress (call 14).
create or replace function public.admin_pending_revocations()
returns table (grant_id uuid, project_id uuid, editor_id uuid, shared_with_email text,
  provider public.asset_provider, folder_url text, shared_at timestamptz, reason text)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_admin uuid := private.require_admin();
begin
  return query
  select x.id, x.project_id, x.editor_id, x.shared_with_email, x.provider, x.folder_url, x.shared_at, x.reason
  from (
    select g.id, g.project_id, g.editor_id, g.shared_with_email, g.provider, g.folder_url, g.shared_at,
      case
        when ep.access_status is distinct from 'active' then 'editor_not_active'
        when p.status in ('cancelled', 'completed') or p.archived_at is not null then 'project_closed'
        when not exists (
          select 1 from public.assignments a
          where a.project_id = g.project_id and a.editor_id = g.editor_id
            and a.status in ('offered', 'counteroffer_pending', 'accepted', 'confirmed', 'in_progress'))
          then 'no_active_assignment'
      end as reason
    from public.asset_access_grants g
    join public.projects p on p.id = g.project_id
    left join public.editor_profiles ep on ep.user_id = g.editor_id
    where g.revoked_at is null
  ) x
  where x.reason is not null
  order by x.shared_at, x.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges (as the originals)
-- ---------------------------------------------------------------------------
revoke all on function
  private.close_live_assignments(uuid, public.assignment_status, uuid, uuid, uuid),
  private.project_transition_allowed(public.project_status, public.project_status, public.project_status)
from public, anon, authenticated;

revoke all on function
  public.admin_revoke_project_access(uuid, uuid),
  public.admin_make_offer(uuid, uuid, numeric, text, text),
  public.admin_withdraw_offer(uuid, text),
  public.admin_reassign(uuid, text),
  public.admin_pending_revocations()
from public, anon, authenticated;
grant execute on function
  public.admin_revoke_project_access(uuid, uuid),
  public.admin_make_offer(uuid, uuid, numeric, text, text),
  public.admin_withdraw_offer(uuid, text),
  public.admin_reassign(uuid, text),
  public.admin_pending_revocations()
to anon, authenticated;
