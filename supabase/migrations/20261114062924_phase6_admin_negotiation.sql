-- Phase 6 (3/5): admin access, offer, negotiation, confirmation, reassign and note functions,
-- and the revoke checklist v2. Spec §7. Plan calls 3, 9-20, 25.
-- Lock order everywhere: the projects row (for update) first, then the assignments row
-- (private.lock_assignment). Assignment audit rows come from the assignments_audit trigger;
-- access and note audits are written here. Audit details never hold amounts or messages.

-- ---------------------------------------------------------------------------
-- Helpers (private, security definer, no API grants)
-- ---------------------------------------------------------------------------

-- Required, > 0, at most 2 decimals, fits numeric(12,2).
create function private.check_amount(p_amount numeric, p_label text)
returns numeric
language plpgsql
immutable
security definer
set search_path = ''
as $$
begin
  if p_amount is null then
    raise exception 'Please enter the %.', p_label using errcode = 'ES422';
  end if;
  if p_amount <= 0 or p_amount <> round(p_amount, 2) or p_amount > 9999999999.99 then
    raise exception 'The % must be above zero, have at most two decimals and be below 10,000,000,000.', p_label
      using errcode = 'ES422';
  end if;
  return p_amount;
end;
$$;

-- Three-letter code, upper-cased; null or blank -> p_default.
create function private.check_currency(p_currency text, p_default char(3))
returns char(3)
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v text := upper(nullif(btrim(p_currency), ''));
begin
  if v is null then
    return p_default;
  end if;
  if v !~ '^[A-Z]{3}$' then
    raise exception 'Please give the currency as a three-letter code such as LKR.' using errcode = 'ES422';
  end if;
  return v;
end;
$$;

-- Locks the parent project, then the assignment (the only lock order used). Editor callers must
-- check ownership before calling this, so they never lock another editor's project row.
create function private.lock_assignment(p_assignment_id uuid)
returns public.assignments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_project uuid;
  v public.assignments;
begin
  select project_id into v_project from public.assignments where id = p_assignment_id;
  if v_project is null then
    raise exception 'Offer not found.' using errcode = 'ES422';
  end if;
  perform 1 from public.projects where id = v_project for update;
  select * into v from public.assignments where id = p_assignment_id for update;
  return v;
end;
$$;

create function private.add_negotiation(
  p_assignment_id uuid, p_role public.negotiation_role, p_action public.negotiation_action,
  p_amount numeric, p_currency char(3), p_message text, p_actor uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.negotiation_offers (assignment_id, from_role, action, amount, currency, message, created_by)
  values (p_assignment_id, p_role, p_action, p_amount, p_currency, p_message, p_actor);
end;
$$;

-- Closes live assignments on a project as withdrawn or not_selected. Live = offered,
-- counteroffer_pending, accepted, and confirmed only when closing as withdrawn. A withdrawn row
-- gets an admin withdraw negotiation row (no message); not_selected gets none.
create function private.close_live_assignments(
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
           or (p_to = 'withdrawn' and a.status = 'confirmed'))
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

-- Revokes live access rows on a project (optionally one editor, or all but one editor).
create function private.revoke_live_access(
  p_project_id uuid, p_actor uuid, p_editor_id uuid default null, p_except_editor uuid default null)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  n int;
begin
  with revoked as (
    update public.project_access pa
    set revoked_at = now(), revoked_by = p_actor
    where pa.project_id = p_project_id and pa.revoked_at is null
      and (p_editor_id is null or pa.editor_id = p_editor_id)
      and (p_except_editor is null or pa.editor_id <> p_except_editor)
    returning pa.id, pa.editor_id
  )
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  select p_actor, 'project_access.revoked', 'project_access', r.id::text,
         jsonb_build_object('project_id', p_project_id, 'editor_id', r.editor_id)
  from revoked r;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- Live access row for an editor, created as `invited` if missing (audited).
create function private.ensure_access(p_project_id uuid, p_editor_id uuid, p_reason public.project_access_reason,
  p_actor uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if exists (select 1 from public.project_access
             where project_id = p_project_id and editor_id = p_editor_id and revoked_at is null) then
    return false;
  end if;
  insert into public.project_access (project_id, editor_id, reason, granted_by)
  values (p_project_id, p_editor_id, p_reason, p_actor)
  returning id into v_id;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (p_actor, 'project_access.granted', 'project_access', v_id::text,
          jsonb_build_object('project_id', p_project_id, 'editor_id', p_editor_id, 'reason', p_reason));
  return true;
end;
$$;

-- Offers, counters, responses and confirmation need an open, unarchived project (call 10).
create function private.require_negotiable_project(p_project_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.projects
                 where id = p_project_id and status = 'open' and archived_at is null) then
    raise exception 'Offers can be made and answered only while the project is open.' using errcode = 'ES409';
  end if;
end;
$$;

-- Admin re-offer on a counteroffer: same currency only (call 11); status back to offered.
create function private.admin_counter(p_assignment public.assignments, p_amount numeric, p_currency text,
  p_message text, p_actor uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_amount numeric := private.check_amount(p_amount, 'offer amount');
begin
  if private.check_currency(p_currency, p_assignment.currency) <> p_assignment.currency then
    raise exception 'An offer stays in one currency. Withdraw it and make a new offer to change currency.'
      using errcode = 'ES422';
  end if;
  update public.assignments set status = 'offered', proposed_amount = v_amount where id = p_assignment.id;
  perform private.add_negotiation(p_assignment.id, 'admin', 'counter', v_amount, p_assignment.currency,
    p_message, p_actor);
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_grant_project_access (call 17): all-or-nothing, dedups, max 100, never the caller.
-- ---------------------------------------------------------------------------
create function public.admin_grant_project_access(
  p_project_id uuid, p_editor_ids uuid[], p_reason public.project_access_reason)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_project public.projects;
  v_ids uuid[];
  n int;
begin
  if p_reason is null then
    raise exception 'Please choose how the editors are given access.' using errcode = 'ES422';
  end if;
  select * into v_project from public.projects where id = p_project_id for update;
  if v_project.id is null then
    raise exception 'Project not found.' using errcode = 'ES422';
  end if;
  if v_project.first_opened_at is null or v_project.status <> 'open' or v_project.archived_at is not null then
    raise exception 'Editors can be given access only while the project is open.' using errcode = 'ES409';
  end if;
  if p_editor_ids is null or cardinality(p_editor_ids) = 0 then
    raise exception 'Choose at least one editor.' using errcode = 'ES422';
  end if;
  if array_position(p_editor_ids, null) is not null then
    raise exception 'The editor list is not valid.' using errcode = 'ES422';
  end if;
  v_ids := array(select distinct u from unnest(p_editor_ids) u);
  if cardinality(v_ids) > 100 then
    raise exception 'You can give access to up to 100 editors at a time.' using errcode = 'ES422';
  end if;
  if v_admin = any (v_ids) then
    raise exception 'You cannot give yourself editor access.' using errcode = 'ES422';
  end if;
  if exists (select 1 from unnest(v_ids) u(id)
             where not exists (select 1 from public.editor_profiles ep
                               where ep.user_id = u.id and ep.access_status = 'active')) then
    raise exception 'Choose active editors only.' using errcode = 'ES422';
  end if;

  with ins as (
    insert into public.project_access (project_id, editor_id, reason, granted_by)
    select p_project_id, u.id, p_reason, v_admin
    from unnest(v_ids) u(id)
    where not exists (select 1 from public.project_access pa
                      where pa.project_id = p_project_id and pa.editor_id = u.id and pa.revoked_at is null)
    returning id, editor_id
  )
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  select v_admin, 'project_access.granted', 'project_access', ins.id::text,
         jsonb_build_object('project_id', p_project_id, 'editor_id', ins.editor_id, 'reason', p_reason)
  from ins;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_revoke_project_access (call 18). Allowed on any project state.
-- ---------------------------------------------------------------------------
create function public.admin_revoke_project_access(p_project_id uuid, p_editor_id uuid)
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
             where project_id = p_project_id and editor_id = p_editor_id and status = 'confirmed') then
    raise exception 'This editor is confirmed on the project. Use reassign instead.' using errcode = 'ES409';
  end if;
  v_closed := private.close_live_assignments(p_project_id, 'withdrawn', v_admin, p_editor_id);
  v_revoked := private.revoke_live_access(p_project_id, v_admin, p_editor_id);
  if v_closed + v_revoked = 0 then
    raise exception 'This editor has no access to this project.' using errcode = 'ES409';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_make_offer (calls 10, 11, 19)
-- ---------------------------------------------------------------------------
create function public.admin_make_offer(
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
    and status in ('offered', 'counteroffer_pending', 'accepted', 'confirmed')
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

-- ---------------------------------------------------------------------------
-- admin_respond_counter: accept / counter / decline a counteroffer (call 12)
-- ---------------------------------------------------------------------------
create function public.admin_respond_counter(
  p_assignment_id uuid, p_action text, p_amount numeric default null, p_currency text default null,
  p_message text default null)
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
  if p_action is null or p_action not in ('accept', 'counter', 'decline') then
    raise exception 'Please choose accept, counter or decline.' using errcode = 'ES422';
  end if;
  v := private.lock_assignment(p_assignment_id);
  perform private.require_negotiable_project(v.project_id);
  if v.status <> 'counteroffer_pending' then
    raise exception 'There is no counteroffer to respond to.' using errcode = 'ES409';
  end if;
  v_message := private.clean_text(p_message, 2000, 'message');

  if p_action = 'accept' then
    update public.assignments
    set status = 'accepted', agreed_amount = proposed_amount, agreed_currency = currency
    where id = v.id;
    perform private.add_negotiation(v.id, 'admin', 'accept', v.proposed_amount, v.currency, v_message, v_admin);
  elsif p_action = 'counter' then
    perform private.admin_counter(v, p_amount, p_currency, v_message, v_admin);
  else
    update public.assignments set status = 'declined', closed_at = now() where id = v.id;
    perform private.add_negotiation(v.id, 'admin', 'decline', null, null, v_message, v_admin);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_withdraw_offer: from offered, counteroffer_pending or accepted (any project state).
-- ---------------------------------------------------------------------------
create function public.admin_withdraw_offer(p_assignment_id uuid, p_message text default null)
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
  if v.status = 'confirmed' then
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

-- ---------------------------------------------------------------------------
-- admin_confirm_assignment (decision C, call 13): one confirmed editor per project; every other
-- live assignment becomes not_selected and every other live access row is revoked.
-- ---------------------------------------------------------------------------
create function public.admin_confirm_assignment(p_assignment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v public.assignments;
  v_project public.projects;
begin
  v := private.lock_assignment(p_assignment_id);
  -- Already locked by lock_assignment (project first); read it under the same lock.
  select * into v_project from public.projects where id = v.project_id for update;
  if v.status <> 'accepted' or v.agreed_amount is null then
    raise exception 'Only an accepted offer can be confirmed.' using errcode = 'ES409';
  end if;
  if v_project.status <> 'open' or v_project.archived_at is not null then
    raise exception 'An editor can be confirmed only while the project is open.' using errcode = 'ES409';
  end if;
  if not exists (select 1 from public.editor_profiles where user_id = v.editor_id and access_status = 'active') then
    raise exception 'This editor''s access is not active, so they cannot be confirmed.' using errcode = 'ES409';
  end if;

  begin
    update public.assignments
    set status = 'confirmed', confirmed_by = v_admin, confirmed_at = now()
    where id = v.id;
  exception
    when unique_violation then
      raise exception 'Another editor is already confirmed for this project.' using errcode = 'ES409';
  end;
  update public.projects set status = 'assigned' where id = v.project_id;
  perform private.close_live_assignments(v.project_id, 'not_selected', v_admin, null, v.id);
  perform private.revoke_live_access(v.project_id, v_admin, null, v.editor_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_reassign (call 14): confirmed -> reassigned, project back to open, that editor's access
-- revoked; the reason is stored as an admin withdraw row the editor can read.
-- ---------------------------------------------------------------------------
create function public.admin_reassign(p_assignment_id uuid, p_message text default null)
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
  if v.status <> 'confirmed'
     or not exists (select 1 from public.projects
                    where id = v.project_id and status = 'assigned' and archived_at is null) then
    raise exception 'Only the confirmed editor of an assigned project can be reassigned.' using errcode = 'ES409';
  end if;
  v_message := private.clean_text(p_message, 2000, 'message');
  update public.assignments set status = 'reassigned', closed_at = now() where id = v.id;
  perform private.add_negotiation(v.id, 'admin', 'withdraw', null, null, v_message, v_admin);
  update public.projects set status = 'open' where id = v.project_id;
  perform private.revoke_live_access(v.project_id, v_admin, v.editor_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_add_project_note (KB6, call 25): any project, archived and cancelled included.
-- ---------------------------------------------------------------------------
create function public.admin_add_project_note(p_project_id uuid, p_note text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_note text := private.clean_text(p_note, 4000, 'note');
  v_id uuid;
begin
  if v_note is null then
    raise exception 'Please write a note.' using errcode = 'ES422';
  end if;
  if not exists (select 1 from public.projects where id = p_project_id) then
    raise exception 'Project not found.' using errcode = 'ES422';
  end if;
  insert into public.project_notes (project_id, author_id, note)
  values (p_project_id, v_admin, v_note)
  returning id into v_id;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'project.note_added', 'project', p_project_id::text,
          jsonb_build_object('project_id', p_project_id, 'note_id', v_id));
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Revoke checklist v2 (call 3): adds no_active_assignment. First matching reason wins.
-- ---------------------------------------------------------------------------
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
            and a.status in ('offered', 'counteroffer_pending', 'accepted', 'confirmed'))
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
-- Function privileges
-- ---------------------------------------------------------------------------
revoke all on function
  private.check_amount(numeric, text), private.check_currency(text, char),
  private.lock_assignment(uuid),
  private.add_negotiation(uuid, public.negotiation_role, public.negotiation_action, numeric, char, text, uuid),
  private.close_live_assignments(uuid, public.assignment_status, uuid, uuid, uuid),
  private.revoke_live_access(uuid, uuid, uuid, uuid),
  private.ensure_access(uuid, uuid, public.project_access_reason, uuid),
  private.require_negotiable_project(uuid),
  private.admin_counter(public.assignments, numeric, text, text, uuid)
from public, anon, authenticated;

revoke all on function
  public.admin_grant_project_access(uuid, uuid[], public.project_access_reason),
  public.admin_revoke_project_access(uuid, uuid),
  public.admin_make_offer(uuid, uuid, numeric, text, text),
  public.admin_respond_counter(uuid, text, numeric, text, text),
  public.admin_withdraw_offer(uuid, text),
  public.admin_confirm_assignment(uuid),
  public.admin_reassign(uuid, text),
  public.admin_add_project_note(uuid, text),
  public.admin_pending_revocations()
from public, anon, authenticated;
grant execute on function
  public.admin_grant_project_access(uuid, uuid[], public.project_access_reason),
  public.admin_revoke_project_access(uuid, uuid),
  public.admin_make_offer(uuid, uuid, numeric, text, text),
  public.admin_respond_counter(uuid, text, numeric, text, text),
  public.admin_withdraw_offer(uuid, text),
  public.admin_confirm_assignment(uuid),
  public.admin_reassign(uuid, text),
  public.admin_add_project_note(uuid, text),
  public.admin_pending_revocations()
to anon, authenticated;
