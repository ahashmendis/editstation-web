-- Phase 7 (3/6): the gate. Spec §7, §8 (carry-forward trigger); plan calls 4, 5, 6, 7, 10, 11.
-- private.assignment_gate is the only place that encodes "may this assignment be in progress";
-- the start functions, the in_progress guard triggers and (Phase 8) submissions all call it.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- The highest brief version that is 1 or needs re-acknowledgement (material baseline, call 7).
create function private.material_brief_version(p_project_id uuid)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select max(bv.version) filter (where bv.version = 1 or bv.requires_reacknowledgement)
  from public.brief_versions bv
  where bv.project_id = p_project_id;
$$;

-- Latest confirmation of an assignment (call 5): highest (brief_version, confirmed_at, id).
create function private.latest_confirmation(p_assignment_id uuid)
returns public.brief_confirmations
language sql
stable
security definer
set search_path = ''
as $$
  select c.* from public.brief_confirmations c
  where c.assignment_id = p_assignment_id
  order by c.brief_version desc, c.confirmed_at desc, c.id desc
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- The gate (spec §7). One row per known assignment; an unknown id returns no row.
-- ---------------------------------------------------------------------------
create function private.assignment_gate(p_assignment_id uuid)
returns table (compensation_approved boolean, interpretation_required boolean, interpretation_accepted boolean,
  current_brief_version int, confirmed_brief_version int, reacknowledgement_required boolean,
  deadline_changed boolean, amount_changed boolean, deliverables_changed boolean, brief_confirmed boolean,
  project_active boolean, editor_active boolean, ready boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_assignment public.assignments;
  v_project public.projects;
  v_latest public.brief_confirmations;
  v_deliverables jsonb;
  v_material int;
begin
  select * into v_assignment from public.assignments a where a.id = p_assignment_id;
  if v_assignment.id is null then
    return;
  end if;
  select * into v_project from public.projects p where p.id = v_assignment.project_id;
  v_latest := private.latest_confirmation(p_assignment_id);
  select bv.deliverables into v_deliverables from public.brief_versions bv
  where bv.project_id = v_project.id and bv.version = v_project.current_brief_version;
  v_material := coalesce(private.material_brief_version(v_project.id), 1);

  compensation_approved := v_assignment.status in ('confirmed', 'in_progress')
    and v_assignment.agreed_amount is not null and v_assignment.confirmed_at is not null;
  interpretation_required := v_project.requires_interpretation;
  interpretation_accepted := exists (
    select 1 from public.editor_interpretations i
    join public.brief_versions bv on bv.id = i.brief_version_id
    where i.assignment_id = v_assignment.id and i.status = 'accepted' and bv.version >= v_material);
  current_brief_version := v_project.current_brief_version;
  confirmed_brief_version := v_latest.brief_version;
  reacknowledgement_required := v_latest.id is null or v_latest.brief_version < v_project.current_brief_version;
  deadline_changed := v_latest.id is not null and v_latest.confirmed_deadline is distinct from v_project.deadline;
  amount_changed := v_latest.id is not null
    and (v_latest.confirmed_amount, v_latest.confirmed_currency)
        is distinct from (v_assignment.agreed_amount, v_assignment.agreed_currency);
  deliverables_changed := v_latest.id is not null
    and v_latest.confirmed_deliverables is distinct from coalesce(v_deliverables, '[]'::jsonb);
  brief_confirmed := v_latest.id is not null
    and not reacknowledgement_required and not deadline_changed and not amount_changed;
  -- Work may be (or stay) in progress only on a live project for an editor whose access is active.
  project_active := v_project.status not in ('on_hold', 'cancelled') and v_project.archived_at is null;
  editor_active := exists (select 1 from public.editor_profiles ep
    where ep.user_id = v_assignment.editor_id and ep.access_status = 'active');
  ready := project_active and editor_active and compensation_approved and brief_confirmed
    and (not interpretation_required or interpretation_accepted);
  return next;
end;
$$;

-- First unmet start condition as a user-safe sentence (project and editor first, then the call 10
-- order), or null when ready.
create function private.gate_refusal(p_assignment_id uuid, p_for_editor boolean)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  g record;
begin
  select * into g from private.assignment_gate(p_assignment_id);
  if g.ready is null then
    return 'Assignment not found.';
  elsif g.ready then
    return null;
  elsif not g.project_active then
    return 'Work cannot continue while the project is on hold, cancelled or archived.';
  elsif not g.editor_active then
    return case when p_for_editor then 'Your editor access is not active.'
                else 'This editor''s access is not active, so work cannot start.' end;
  elsif not g.compensation_approved then
    return 'The agreed pay has not been approved yet.';
  elsif g.interpretation_required and not g.interpretation_accepted then
    return case when p_for_editor then 'Your interpretation needs to be accepted first.'
                else 'The editor''s interpretation needs to be accepted first.' end;
  elsif g.reacknowledgement_required then
    return case when p_for_editor then 'Please confirm the current brief first.'
                else 'The editor needs to confirm the current brief first.' end;
  else
    return case when p_for_editor then 'The deadline or pay changed since you confirmed. Please confirm again.'
                else 'The deadline or pay changed since the editor confirmed. The editor needs to confirm again.' end;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Enforcement triggers (BEFORE UPDATE only, call 4): whoever updates, the gate holds. The gate
-- includes the project (not on hold, cancelled or archived) and editor access checks.
-- ---------------------------------------------------------------------------
create function private.guard_assignment_start()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_refusal text;
begin
  if new.status = 'in_progress' and old.status is distinct from 'in_progress' then
    -- The gate reads the stored row, so the pay and confirmation stamp may not change here.
    if (new.agreed_amount, new.agreed_currency, new.confirmed_at)
       is distinct from (old.agreed_amount, old.agreed_currency, old.confirmed_at) then
      raise exception 'The agreed pay cannot change when work starts.' using errcode = 'ES409';
    end if;
    v_refusal := private.gate_refusal(new.id, false);
    if v_refusal is not null then
      raise exception '%', v_refusal using errcode = 'ES409';
    end if;
  end if;
  return new;
end;
$$;

create trigger guard_assignment_start
  before update on public.assignments
  for each row execute function private.guard_assignment_start();

create function private.guard_project_in_progress()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'in_progress' and old.status is distinct from 'in_progress'
     and not exists (select 1 from public.assignments a where a.project_id = new.id and a.status = 'in_progress') then
    raise exception 'A project starts only when its editor starts work.' using errcode = 'ES409';
  end if;
  return new;
end;
$$;

create trigger guard_project_in_progress
  before update of status on public.projects
  for each row execute function private.guard_project_in_progress();

-- ---------------------------------------------------------------------------
-- Editor stage: `assigned` for confirmed and in_progress (spec §6). Otherwise unchanged.
-- ---------------------------------------------------------------------------
create or replace function private.editor_project_stage(p_project_id uuid)
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
      where a.project_id = p_project_id and a.editor_id = (select auth.uid())
        and a.status in ('confirmed', 'in_progress'))
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

-- Grant first, then revoke PUBLIC (a missing EXECUTE in a policy crashes this Postgres image).
grant execute on function private.editor_project_stage(uuid) to authenticated;
revoke all on function private.editor_project_stage(uuid) from public, anon;

-- ---------------------------------------------------------------------------
-- Carry-forward (spec §8, call 6): a new version with requires_reacknowledgement = false records
-- a carried_forward row for every confirmed / in_progress assignment whose latest confirmation
-- is for the previous version. Drift is not checked here: it stays visible through the gate.
-- ---------------------------------------------------------------------------
create function private.carry_forward_confirmations()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_id uuid;
begin
  if new.version <= 1 or new.requires_reacknowledgement then
    return null;
  end if;
  for r in
    select c.* from public.assignments a
    cross join lateral private.latest_confirmation(a.id) c
    where a.project_id = new.project_id and a.status in ('confirmed', 'in_progress')
      and c.id is not null and c.brief_version = new.version - 1
    order by a.id
  loop
    insert into public.brief_confirmations (assignment_id, project_id, editor_id, brief_version_id, brief_version,
      kind, carried_from_id, confirmed_deadline, confirmed_deliverables, confirmed_amount, confirmed_currency,
      created_by, confirmed_at)
    values (r.assignment_id, r.project_id, r.editor_id, new.id, new.version, 'carried_forward', r.id,
      r.confirmed_deadline, new.deliverables, r.confirmed_amount, r.confirmed_currency, new.created_by,
      clock_timestamp())
    returning id into v_id;
    insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
    values (new.created_by, 'brief_confirmation.carried_forward', 'brief_confirmation', v_id::text,
      jsonb_build_object('confirmation_id', v_id, 'assignment_id', r.assignment_id, 'brief_version', new.version,
        'carried_from_id', r.id));
  end loop;
  return null;
end;
$$;

create trigger carry_forward_confirmations
  after insert on public.brief_versions
  for each row execute function private.carry_forward_confirmations();

-- ---------------------------------------------------------------------------
-- get_assignment_gate (call 11): admin (aal2) or the owning active editor; read-only.
-- ---------------------------------------------------------------------------
create function public.get_assignment_gate(p_assignment_id uuid)
returns table (compensation_approved boolean, interpretation_required boolean, interpretation_accepted boolean,
  current_brief_version int, confirmed_brief_version int, reacknowledgement_required boolean,
  deadline_changed boolean, amount_changed boolean, deliverables_changed boolean, brief_confirmed boolean,
  project_active boolean, editor_active boolean, ready boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
begin
  if not (private.is_admin()
          or (private.is_active_editor()
              and exists (select 1 from public.assignments a where a.id = p_assignment_id and a.editor_id = v_uid))) then
    raise exception 'Assignment not found.' using errcode = 'ES422';
  end if;
  return query select * from private.assignment_gate(p_assignment_id);
  if not found then
    raise exception 'Assignment not found.' using errcode = 'ES422';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges
-- ---------------------------------------------------------------------------
revoke all on function
  private.material_brief_version(uuid), private.latest_confirmation(uuid), private.assignment_gate(uuid),
  private.gate_refusal(uuid, boolean), private.guard_assignment_start(), private.guard_project_in_progress(),
  private.carry_forward_confirmations()
from public, anon, authenticated;

revoke all on function public.get_assignment_gate(uuid) from public, anon, authenticated;
grant execute on function public.get_assignment_gate(uuid) to anon, authenticated;
