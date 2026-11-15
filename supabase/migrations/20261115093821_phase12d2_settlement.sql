-- Phase 12D part 2 (5/5): cancellation settlement. Spec §4.6, §4.3 (cancelled), §8 item 4, call 2;
-- decisions F2 (c), KB9a-3.
--
-- admin_settle_cancellation cancels the project and settles it in one transaction:
--   stage    the project status now (on hold from assigned counts as assigned)
--   editor   earned = agreed amount x editor_earned_percent of that stage (rounded to cents) plus
--            accepted extra pay (extra rounds, scope changes) in full, or the admin's figure with a
--            recorded reason (never below the accepted extra pay). Extra pay rows are untouched:
--            paid stays paid, unpaid stays payable. Unpaid milestone rows become cancelled; a
--            settlement row pays any milestone shortfall; a milestone overpayment is reconciled by
--            settlement reversals of paid milestone rows (recovering money is outside the app)
--   client   charge = deposit + balance milestones x client_charge_percent; refund rows (negative,
--            verified like any transfer) return verified money above the charge; an amount still
--            owed is only recorded
-- When it is required (minimal rule, documented in WORKFLOWS 3a): the project has a confirmed or
-- in-progress assignment AND the agreed terms have a schedule row for the current stage. Then the
-- plain status change to cancelled is refused. Otherwise (nothing confirmed, or no schedule, e.g.
-- backfilled terms) the plain cancel keeps the Phase 9 behaviour: unpaid rows go on hold for the
-- admin. Lock order: project, assignments, payments, client milestones.

-- The cancellation stage of a project as it is now, or null.
create function private.cancellation_stage(p_project_id uuid)
returns public.terms_stage
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p.status in ('assigned', 'in_progress', 'in_review', 'revision_requested') then p.status::text::public.terms_stage
    when p.status = 'on_hold' and p.status_before_hold = 'assigned' then 'assigned'::public.terms_stage
  end
  from public.projects p where p.id = p_project_id;
$$;

-- The project's live (confirmed or in-progress) assignment, if any.
create function private.live_assignment_id(p_project_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select a.id from public.assignments a
  where a.project_id = p_project_id and a.status in ('confirmed', 'in_progress')
  order by a.confirmed_at desc nulls last, a.id limit 1;
$$;

create function private.cancellation_settlement_required(p_project_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.live_assignment_id(p_project_id) is not null
    and exists (select 1 from public.project_terms t
                join public.project_terms_stages s on s.terms_id = t.id
                where t.project_id = p_project_id and t.status = 'agreed'
                  and s.stage = private.cancellation_stage(p_project_id));
$$;

-- ---------------------------------------------------------------------------
-- private.settlement_figures: every number of a settlement, or a clean refusal. p_adjusted is the
-- admin's editor-earned figure (null = the schedule's); p_reason is required when it differs.
-- Read-only: the preview calls it directly, the settle function under its locks.
-- ---------------------------------------------------------------------------
create function private.settlement_figures(p_project_id uuid, p_adjusted numeric, p_reason text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_project public.projects;
  v_stage public.terms_stage;
  v public.assignments;
  t public.project_terms;
  s public.project_terms_stages;
  v_reason text := private.clean_text(p_reason, 2000, 'reason');
  v_computed numeric(12, 2);
  v_extra numeric(12, 2);
  v_base_earned numeric(12, 2);
  v_earned numeric(12, 2);
  v_cap numeric(12, 2);
  v_paid numeric(12, 2);
  v_base numeric(12, 2);
  v_currency char(3);
  v_received numeric(12, 2);
  v_charge numeric(12, 2);
begin
  select * into v_project from public.projects where id = p_project_id;
  if v_project.id is null then
    raise exception 'Project not found.' using errcode = 'ES422';
  end if;
  if v_project.archived_at is not null then
    raise exception 'This project is archived. Restore it first.' using errcode = 'ES409';
  end if;
  if exists (select 1 from public.cancellation_settlements cs where cs.project_id = p_project_id) then
    raise exception 'This cancellation was already settled.' using errcode = 'ES409';
  end if;
  v_stage := private.cancellation_stage(p_project_id);
  if v_stage is null then
    raise exception 'Only an assigned or started project is settled here.' using errcode = 'ES409';
  end if;
  select * into v from public.assignments where id = private.live_assignment_id(p_project_id);
  if v.id is null then
    raise exception 'No editor has a confirmed assignment, so there is nothing to settle. Cancel the project from its status instead.'
      using errcode = 'ES409';
  end if;
  select * into t from public.project_terms where project_id = p_project_id and status = 'agreed';
  select * into s from public.project_terms_stages where terms_id = t.id and stage = v_stage;
  if s.id is null then
    raise exception 'The agreed terms have no cancellation schedule for this stage, so it cannot be settled here. Cancel the project from its status instead; unpaid editor payments then go on hold for you to resolve.'
      using errcode = 'ES409';
  end if;
  if exists (select 1 from public.client_milestones m where m.project_id = p_project_id and m.voided_at is null
             and m.verification_status = 'received_unverified') then
    raise exception 'Verify or correct the recorded client payments before settling.' using errcode = 'ES409';
  end if;

  -- Editor side.
  -- Accepted extra pay (extra rounds, scope changes) counts as earned in full.
  v_extra := coalesce((select sum(c.amount) from public.compensation_adjustments c
                       where c.assignment_id = v.id and c.status = 'accepted'
                         and c.kind in ('extra_round', 'scope_change')), 0);
  v_computed := round(v.agreed_amount * s.editor_earned_percent / 100, 2) + v_extra;
  v_cap := v.agreed_amount + v_extra;
  if p_adjusted is null or p_adjusted = v_computed then
    v_earned := v_computed;
  else
    if p_adjusted < v_extra or p_adjusted <> round(p_adjusted, 2) or p_adjusted > v_cap then
      raise exception 'The editor''s earned amount must be in whole cents, at least the accepted extra pay and at most the agreed pay plus accepted extra pay.'
        using errcode = 'ES422';
    end if;
    if v_reason is null then
      raise exception 'Please give the reason for changing the editor''s earned amount.' using errcode = 'ES422';
    end if;
    v_earned := p_adjusted;
  end if;
  v_base_earned := v_earned - v_extra;
  -- Net paid on the milestones (extra pay rows are settled on their own).
  v_paid := coalesce((select sum(p.amount) from public.payments p
                      where p.assignment_id = v.id and p.status = 'paid' and p.milestone_seq is not null), 0);

  -- Client side (deposit and balance only; extra-work charges are handled separately).
  select coalesce(sum(m.amount), 0), min(m.currency) into v_base, v_currency
  from public.client_milestones m
  where m.project_id = p_project_id and m.voided_at is null and m.kind in ('deposit', 'balance');
  v_received := coalesce((select sum(m.amount + coalesce((select sum(r.amount) from public.client_milestones r
                                                          where r.reverses_id = m.id and r.voided_at is null), 0))
                          from public.client_milestones m
                          where m.project_id = p_project_id and m.voided_at is null
                            and m.kind in ('deposit', 'balance') and m.verification_status = 'verified'), 0);
  v_charge := round(v_base * s.client_charge_percent / 100, 2);

  return jsonb_build_object(
    'project_id', p_project_id, 'assignment_id', v.id, 'terms_id', t.id, 'stage', v_stage,
    'editor_earned_percent', s.editor_earned_percent, 'client_charge_percent', s.client_charge_percent,
    'agreed_amount', v.agreed_amount, 'editor_currency', v.agreed_currency,
    'computed_editor_earned', v_computed, 'editor_earned', v_earned, 'editor_earned_cap', v_cap,
    'adjustment_reason', case when v_earned <> v_computed then v_reason end,
    'editor_extra_pay', v_extra, 'editor_paid_before', v_paid,
    'editor_settlement_amount', greatest(v_base_earned - v_paid, 0),
    'editor_overpayment', greatest(v_paid - v_base_earned, 0),
    'unpaid_count', (select count(*) from public.payments p
                     where p.assignment_id = v.id and p.kind = 'assignment' and p.milestone_seq is not null
                       and p.status not in ('paid', 'cancelled')),
    'client_base', v_base, 'client_currency', v_currency, 'client_received', v_received,
    'client_charge', v_charge,
    'client_refund', greatest(v_received - v_charge, 0),
    'client_owes', greatest(v_charge - v_received, 0));
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_preview_cancellation_settlement: the proposed figures for the settlement panel.
-- ---------------------------------------------------------------------------
create function public.admin_preview_cancellation_settlement(p_project_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
begin
  return private.settlement_figures(p_project_id, null, null);
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_settle_cancellation: cancels the project and settles both sides. Returns the settlement id.
-- ---------------------------------------------------------------------------
create function public.admin_settle_cancellation(p_project_id uuid, p_adjusted_editor_earned numeric default null,
  p_reason text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_project public.projects;
  f jsonb;
  v_assignment uuid;
  v_settlement uuid;
  v_cancelled int;
  v_remaining numeric(12, 2);
  v_part numeric(12, 2);
  v_seq int;
  v_due date;
  r record;
  v_refunds uuid[] := '{}';
  v_keep uuid[];
  v_id uuid;
begin
  select * into v_project from public.projects where id = p_project_id for update;
  if v_project.id is null then
    raise exception 'Project not found.' using errcode = 'ES422';
  end if;
  perform 1 from public.assignments where project_id = p_project_id order by id for update;
  v_assignment := private.live_assignment_id(p_project_id);
  if v_assignment is not null then
    perform 1 from public.payments where assignment_id = v_assignment order by id for update;
  end if;
  perform 1 from public.client_milestones where project_id = p_project_id and voided_at is null order by id for update;

  f := private.settlement_figures(p_project_id, p_adjusted_editor_earned, p_reason);

  -- Unpaid extra pay rows not on hold stay payable: the close below holds them, so they are
  -- released again right after.
  select coalesce(array_agg(id), '{}') into v_keep from public.payments
  where assignment_id = v_assignment and kind = 'assignment' and adjustment_id is not null
    and status not in ('paid', 'cancelled', 'on_hold');

  -- Cancel the project (as admin_set_project_status does), closing the assignment and access.
  update public.projects set status = 'cancelled', status_before_hold = null where id = p_project_id;
  update public.client_milestones set auto_held_at = null
  where project_id = p_project_id and kind = 'deposit' and voided_at is null and auto_held_at is not null;
  perform private.close_live_assignments(p_project_id, 'withdrawn', v_admin);
  perform private.revoke_live_access(p_project_id, v_admin);
  update public.compensation_adjustments set status = 'withdrawn', withdrawn_by = v_admin, withdrawn_at = now()
  where assignment_id = v_assignment and status = 'offered';

  update public.payments set status = held_from_status, held_from_status = null, on_hold_reason = null
  where id = any (v_keep) and status = 'on_hold';

  -- Editor side: void unpaid milestone rows (the close above put them on hold).
  perform set_config('es.payment_cancel', p_project_id::text, true);
  update public.payments set status = 'cancelled', held_from_status = null, on_hold_reason = null
  where assignment_id = v_assignment and kind = 'assignment' and milestone_seq is not null
    and status not in ('paid', 'cancelled');
  get diagnostics v_cancelled = row_count;
  perform set_config('es.payment_cancel', '', true);

  insert into public.cancellation_settlements (project_id, assignment_id, terms_id, stage, editor_earned_percent,
    client_charge_percent, agreed_amount, editor_currency, computed_editor_earned, editor_earned, adjustment_reason,
    editor_extra_pay, editor_paid_before, editor_settlement_amount, editor_overpayment, cancelled_payment_count, client_base,
    client_currency, client_received, client_charge, client_refund, client_owes, settled_by)
  values (p_project_id, v_assignment, (f ->> 'terms_id')::uuid, (f ->> 'stage')::public.terms_stage,
    (f ->> 'editor_earned_percent')::numeric, (f ->> 'client_charge_percent')::numeric,
    (f ->> 'agreed_amount')::numeric, f ->> 'editor_currency', (f ->> 'computed_editor_earned')::numeric,
    (f ->> 'editor_earned')::numeric, f ->> 'adjustment_reason', (f ->> 'editor_extra_pay')::numeric,
    (f ->> 'editor_paid_before')::numeric,
    (f ->> 'editor_settlement_amount')::numeric, (f ->> 'editor_overpayment')::numeric, v_cancelled,
    (f ->> 'client_base')::numeric, f ->> 'client_currency', (f ->> 'client_received')::numeric,
    (f ->> 'client_charge')::numeric, (f ->> 'client_refund')::numeric, (f ->> 'client_owes')::numeric, v_admin)
  returning id into v_settlement;

  -- Shortfall: one settlement row, payable now.
  if (f ->> 'editor_settlement_amount')::numeric > 0 then
    v_due := private.business_date(now()) + private.editor_pay_days(p_project_id);
    insert into public.payments (assignment_id, project_id, editor_id, kind, milestone_seq, settlement_id, amount,
      currency, status, payable_reason, payable_at, due_date, created_by)
    select a.id, a.project_id, a.editor_id, 'assignment', null, v_settlement,
      (f ->> 'editor_settlement_amount')::numeric, a.agreed_currency, 'pending_approval', 'cancellation_settlement',
      now(), v_due, v_admin
    from public.assignments a where a.id = v_assignment;
  end if;

  -- Overpayment: reverse it from the newest paid rows (audited reconciliation).
  v_remaining := (f ->> 'editor_overpayment')::numeric;
  for r in
    select p.* from public.payments p
    where p.assignment_id = v_assignment and p.kind = 'assignment' and p.status = 'paid'
      and p.milestone_seq is not null
      and not exists (select 1 from public.payments x where x.reverses_payment_id = p.id)
    order by p.marked_paid_at desc, p.id desc
  loop
    exit when v_remaining <= 0;
    v_part := least(v_remaining, r.amount);
    insert into public.payments (assignment_id, project_id, editor_id, kind, milestone_seq, adjustment_id, settlement_id,
      amount, currency, status, reverses_payment_id, reversal_reason, marked_paid_by, marked_paid_at, created_by)
    values (r.assignment_id, r.project_id, r.editor_id, 'reversal', r.milestone_seq, r.adjustment_id, v_settlement,
      -v_part, r.currency, 'paid', r.id, 'Cancellation settlement: paid more than the editor earned.', v_admin, now(),
      v_admin);
    v_remaining := v_remaining - v_part;
  end loop;

  -- Client refund: negative refund rows against the newest verified receipts.
  v_remaining := (f ->> 'client_refund')::numeric;
  for r in
    select m.id, m.currency, m.amount + coalesce((select sum(x.amount) from public.client_milestones x
                                                  where x.reverses_id = m.id and x.voided_at is null), 0) as available
    from public.client_milestones m
    where m.project_id = p_project_id and m.voided_at is null and m.kind in ('deposit', 'balance')
      and m.verification_status = 'verified'
    order by m.seq desc
  loop
    exit when v_remaining <= 0;
    continue when r.available <= 0;
    v_part := least(v_remaining, r.available);
    v_seq := coalesce((select max(seq) from public.client_milestones where project_id = p_project_id), 0) + 1;
    insert into public.client_milestones (project_id, terms_id, seq, kind, amount, currency, reverses_id, settlement_id,
      created_by)
    values (p_project_id, (f ->> 'terms_id')::uuid, v_seq, 'refund', -v_part, r.currency, r.id, v_settlement, v_admin)
    returning id into v_id;
    v_refunds := v_refunds || v_id;
    v_remaining := v_remaining - v_part;
  end loop;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'project.cancellation_settled', 'project', p_project_id::text,
    jsonb_build_object('project_id', p_project_id, 'settlement_id', v_settlement, 'assignment_id', v_assignment,
      'stage', f ->> 'stage', 'refund_ids', to_jsonb(v_refunds),
      'fields', case when f ->> 'adjustment_reason' is null then '[]'::jsonb
                     else '["editor_earned", "adjustment_reason"]'::jsonb end));
  return v_settlement;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_set_project_status (12C body) + the settlement rule: cancelling a project with a confirmed
-- editor and a schedule row for its stage must go through admin_settle_cancellation.
-- ---------------------------------------------------------------------------
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
  if p_status = 'cancelled' and private.cancellation_settlement_required(p_project_id) then
    raise exception 'This project has a confirmed editor and an agreed cancellation schedule. Use Settle cancellation instead.'
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
-- Function privileges
-- ---------------------------------------------------------------------------
revoke all on function
  private.cancellation_stage(uuid), private.live_assignment_id(uuid), private.cancellation_settlement_required(uuid),
  private.settlement_figures(uuid, numeric, text)
from public, anon, authenticated;

revoke all on function
  public.admin_preview_cancellation_settlement(uuid), public.admin_settle_cancellation(uuid, numeric, text)
from public, anon, authenticated;
grant execute on function
  public.admin_preview_cancellation_settlement(uuid), public.admin_settle_cancellation(uuid, numeric, text)
to anon, authenticated;
