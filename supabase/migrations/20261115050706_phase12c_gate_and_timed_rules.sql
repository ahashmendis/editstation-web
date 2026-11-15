-- Phase 12C (4/4): the deposit start gate (KB9b-4), assigned -> on_hold for the unpaid-deposit rule
-- only (call 3), and the timed rules sweep (KB9a-2, call 7). Spec §5.
--
-- private.assignment_gate gains client_deposit_verified, so its return type changes and it is
-- dropped and recreated. Catalog check before writing (pg_depend has no rows for it: plpgsql
-- bodies are resolved by name at run time). Functions whose bodies reference it or
-- private.gate_refusal: private.gate_refusal, private.guard_assignment_start (trigger),
-- public.get_assignment_gate, public.editor_submit_interpretation, private.start_work,
-- public.editor_confirm_brief, public.editor_submit_work. Only public.get_assignment_gate shares
-- the return type, so it is dropped and recreated with its grants; gate_refusal is replaced in place
-- (same signature) to name the new condition; the others read named columns and keep working.

drop function public.get_assignment_gate(uuid);
drop function private.assignment_gate(uuid);

-- A verified client deposit exists for the project (voided rows are never verified).
create function private.client_deposit_verified(p_project_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.client_milestones m
                 where m.project_id = p_project_id and m.kind = 'deposit' and m.voided_at is null
                   and m.verification_status = 'verified');
$$;

-- ---------------------------------------------------------------------------
-- The gate (Phase 7 spec §7 + Phase 12 §5). Unchanged except client_deposit_verified, which ready
-- now requires.
-- ---------------------------------------------------------------------------
create function private.assignment_gate(p_assignment_id uuid)
returns table (compensation_approved boolean, interpretation_required boolean, interpretation_accepted boolean,
  current_brief_version int, confirmed_brief_version int, reacknowledgement_required boolean,
  deadline_changed boolean, amount_changed boolean, deliverables_changed boolean, brief_confirmed boolean,
  project_active boolean, editor_active boolean, client_deposit_verified boolean, ready boolean)
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
  project_active := v_project.status not in ('on_hold', 'cancelled') and v_project.archived_at is null;
  editor_active := exists (select 1 from public.editor_profiles ep
    where ep.user_id = v_assignment.editor_id and ep.access_status = 'active');
  client_deposit_verified := private.client_deposit_verified(v_project.id);
  ready := project_active and editor_active and compensation_approved and brief_confirmed
    and (not interpretation_required or interpretation_accepted) and client_deposit_verified;
  return next;
end;
$$;

-- First unmet start condition as a user-safe sentence, or null when ready. The deposit comes last
-- so the editor first sees what they can act on; the editor wording never mentions amounts.
create or replace function private.gate_refusal(p_assignment_id uuid, p_for_editor boolean)
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
  elsif not g.brief_confirmed then
    return case when p_for_editor then 'The deadline or pay changed since you confirmed. Please confirm again.'
                else 'The deadline or pay changed since the editor confirmed. The editor needs to confirm again.' end;
  else
    return case when p_for_editor then 'Waiting for the client deposit. Work can start once it is confirmed.'
                else 'The client deposit has not been verified yet, so work cannot start.' end;
  end if;
end;
$$;

-- get_assignment_gate (Phase 7 call 11): admin (aal2) or the owning active editor; read-only. The
-- editor sees client_deposit_verified only as a yes/no status, never amounts.
create function public.get_assignment_gate(p_assignment_id uuid)
returns table (compensation_approved boolean, interpretation_required boolean, interpretation_accepted boolean,
  current_brief_version int, confirmed_brief_version int, reacknowledgement_required boolean,
  deadline_changed boolean, amount_changed boolean, deliverables_changed boolean, brief_confirmed boolean,
  project_active boolean, editor_active boolean, client_deposit_verified boolean, ready boolean)
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
-- Call 3: assigned -> on_hold exists for the unpaid-deposit rule only. The transition table allows
-- it (and, for that hold, on_hold -> cancelled: the admin "extends or cancels"), but the manual
-- status function refuses to put an assigned project on hold: only private.apply_timed_rules does.
-- Releasing returns to status_before_hold (assigned).
-- ---------------------------------------------------------------------------
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
    when p_from = 'on_hold' then p_before_hold is not null
      and (p_to = p_before_hold or (p_before_hold = 'assigned' and p_to = 'cancelled'))
    when p_from = 'assigned' then p_to in ('cancelled', 'on_hold')
    when p_from in ('in_progress', 'in_review', 'revision_requested') then p_to = 'cancelled'
    else false
  end;
$$;

-- admin_set_project_status (Phase 6 body) + the manual refusal of assigned -> on_hold.
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
  if v_project.status = 'assigned' and p_status = 'on_hold' then
    raise exception 'An assigned project goes on hold only automatically, when the client deposit is overdue.'
      using errcode = 'ES409';
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

  -- Releasing the unpaid-deposit hold by hand ends it (auto_held_for_due stays, so the rule does
  -- not hold the project again for the same due date).
  if v_project.status = 'on_hold' and p_status <> 'on_hold' then
    update public.client_milestones set auto_held_at = null
    where project_id = p_project_id and kind = 'deposit' and voided_at is null and auto_held_at is not null;
  end if;

  if p_status = 'cancelled' then
    perform private.close_live_assignments(p_project_id, 'withdrawn', v_admin);
    perform private.revoke_live_access(p_project_id, v_admin);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Timed rules (call 7). Idempotent; every action is audited and notifies the admins.
-- KB9a-2: a deposit still unverified after its due date (invoice date + deposit_days, or the
-- extended date), on an assigned project with a confirmed editor, puts the project on hold with
-- the deposit-unpaid reason (open projects have no editor to protect). A calendar day ends in the
-- business timezone (call 4): the rule acts from the day after the due date. It acts once per due
-- date (auto_held_for_due).
-- Late-balance protection (KB9a-1) arrives in 12D. Returns the number of actions taken.
-- ---------------------------------------------------------------------------
create function private.apply_timed_rules(p_now timestamptz)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select p.id from public.profiles p where p.id = (select auth.uid()));
  v_today date;
  r record;
  v_project public.projects;
  v_m public.client_milestones;
  v_count int := 0;
begin
  if p_now is null then
    raise exception 'A time is required.' using errcode = 'ES422';
  end if;
  v_today := private.business_date(p_now);

  for r in
    select m.id, m.project_id from public.client_milestones m
    join public.projects p on p.id = m.project_id
    where m.kind = 'deposit' and m.voided_at is null and m.verification_status <> 'verified'
      and m.invoice_issued_at is not null and m.auto_held_for_due is distinct from m.due_date
      and m.due_date < v_today and p.status = 'assigned' and p.archived_at is null
    order by m.project_id
  loop
    -- Project first, then the milestone; re-check under the locks (a concurrent run or admin
    -- action may have changed either).
    select * into v_project from public.projects where id = r.project_id for update;
    select * into v_m from public.client_milestones where id = r.id for update;
    if v_m.voided_at is not null or v_m.verification_status = 'verified'
       or v_m.auto_held_for_due is not distinct from v_m.due_date
       or v_m.due_date is null or v_m.due_date >= v_today
       or v_project.status <> 'assigned' or v_project.archived_at is not null
       or not exists (select 1 from public.assignments a where a.project_id = r.project_id and a.status = 'confirmed') then
      continue;
    end if;

    update public.client_milestones set auto_held_at = p_now, auto_held_for_due = v_m.due_date where id = v_m.id;
    update public.projects set status = 'on_hold', status_before_hold = 'assigned' where id = v_project.id;

    insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
    values (v_actor, 'project.auto_held', 'project', v_project.id::text,
      jsonb_build_object('project_id', v_project.id, 'milestone_id', v_m.id, 'reason', 'deposit_unpaid'));
    perform private.notify(private.active_admin_ids(), 'project_auto_held', 'project', v_project.id,
      'Project put on hold',
      format('"%s" was put on hold automatically: the client deposit is overdue. Extend the due date, resume or cancel the project.',
        v_project.title));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- admin_run_timed_rules: the admin backstop the dashboard and /admin/earnings call on load (works
-- locally; pg_cron calls private.apply_timed_rules on hosted). A run that takes action is audited
-- (each action also has its own audit row); a run with nothing to do writes nothing, so page loads
-- do not flood the activity log.
create function public.admin_run_timed_rules()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_count int;
begin
  v_count := private.apply_timed_rules(now());
  if v_count > 0 then
    insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
    values (v_admin, 'timed_rules.run', 'timed_rules', 'apply_timed_rules', jsonb_build_object('actions', v_count));
  end if;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges
-- ---------------------------------------------------------------------------
revoke all on function
  private.client_deposit_verified(uuid), private.assignment_gate(uuid), private.apply_timed_rules(timestamptz)
from public, anon, authenticated;

revoke all on function public.get_assignment_gate(uuid), public.admin_run_timed_rules() from public, anon, authenticated;
grant execute on function public.get_assignment_gate(uuid), public.admin_run_timed_rules() to anon, authenticated;
