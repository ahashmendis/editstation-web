-- Phase 12D part 1 (3/3): editor milestone creation, payable rules, late-balance protection,
-- partial-dispute splits and the editor-safe earnings list. Spec §4.2 (12D note), §4.3, §4.5, §5,
-- call 9; decisions KB9, KB9a-1, KB9a-4, KB9a-5, KB9b-3.
-- Lock order: project, then assignments, then payments (Phase 9). Audit rows hold ids, enum names
-- and field names only. Errors: ES401/ES403 from the helpers, ES409 state, ES422 input.
-- The Phase 9 hold-on-close trigger is unchanged (cancellation settlement replaces it in part 2).

-- ---------------------------------------------------------------------------
-- Client money flags (admin-only facts; editors see only waiting_on_client)
-- ---------------------------------------------------------------------------

-- §4.2 note: a verified deposit counts only while its amount plus its refund rows is above 0.
create or replace function private.client_deposit_verified(p_project_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.client_milestones m
    where m.project_id = p_project_id and m.kind = 'deposit' and m.voided_at is null
      and m.verification_status = 'verified'
      and m.amount + coalesce((select sum(r.amount) from public.client_milestones r
                               where r.reverses_id = m.id and r.voided_at is null), 0) > 0);
$$;

-- The client balance is in: the deposit counts (above) and every current balance row is verified
-- and not refunded to 0. With no balance rows (e.g. 100% upfront) the deposit alone suffices.
create function private.client_balance_verified(p_project_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.client_deposit_verified(p_project_id)
    and not exists (
      select 1 from public.client_milestones m
      where m.project_id = p_project_id and m.kind = 'balance' and m.voided_at is null
        and (m.verification_status <> 'verified'
             or m.amount + coalesce((select sum(r.amount) from public.client_milestones r
                                     where r.reverses_id = m.id and r.voided_at is null), 0) <= 0));
$$;

-- Editor pay days from the agreed terms (KB9b-3 default 7).
create function private.editor_pay_days(p_project_id uuid)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select t.editor_pay_days from public.project_terms t
                   where t.project_id = p_project_id and t.status = 'agreed'), 7);
$$;

-- ---------------------------------------------------------------------------
-- private.sync_editor_milestones: makes not_due milestones of live assignments payable when their
-- client condition holds, and keeps waiting_on_client current. Milestone 1: the client deposit is
-- verified (the row exists only once the assignment is confirmed). Milestones 2..n: the project
-- is approved (or completed) and the client balance is verified. Payable = pending_approval with
-- payable_at = p_now and due_date = business date of p_now + editor_pay_days. Idempotent.
-- Callers hold the project lock or take it here first.
-- ---------------------------------------------------------------------------
create function private.sync_editor_milestones(p_project_id uuid, p_now timestamptz)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_project public.projects;
  v_deposit boolean;
  v_balance boolean;
  v_approved boolean;
  v_due date;
  v_payable boolean;
  v_wait boolean;
  v_reason public.payment_payable_reason;
  v_count int := 0;
  r record;
begin
  select * into v_project from public.projects where id = p_project_id for update;
  if v_project.id is null then
    return 0;
  end if;
  perform 1 from public.assignments
  where project_id = p_project_id and status in ('confirmed', 'in_progress') order by id for update;

  v_deposit := private.client_deposit_verified(p_project_id);
  v_balance := private.client_balance_verified(p_project_id);
  v_approved := v_project.status in ('approved', 'completed');
  v_due := private.business_date(p_now) + private.editor_pay_days(p_project_id);

  for r in
    select p.id, p.milestone_seq, p.waiting_on_client from public.payments p
    join public.assignments a on a.id = p.assignment_id
    where p.project_id = p_project_id and p.kind = 'assignment' and p.status = 'not_due'
      and a.status in ('confirmed', 'in_progress')
    order by p.id
    for update of p
  loop
    if r.milestone_seq = 1 then
      v_payable := v_deposit;
      v_wait := not v_deposit;
      v_reason := 'client_deposit_verified';
    else
      v_payable := v_approved and v_balance;
      v_wait := v_approved and not v_balance;
      v_reason := 'client_balance_verified';
    end if;
    if v_payable then
      update public.payments
      set status = 'pending_approval', payable_reason = v_reason, payable_at = p_now, due_date = v_due
      where id = r.id;
      v_count := v_count + 1;
    elsif r.waiting_on_client is distinct from v_wait then
      update public.payments set waiting_on_client = v_wait where id = r.id;
    end if;
  end loop;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Confirmation: N editor milestone rows from the agreed terms shares (default 50/50 of the agreed
-- amount; the last row takes the rounding remainder, call 9), all not_due; then the payable rules
-- run (the deposit may already be verified).
-- ---------------------------------------------------------------------------
create or replace function private.create_assignment_payment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_shares smallint[];
  v_amount numeric(12, 2);
  v_sum numeric(12, 2) := 0;
  n int;
  i int;
begin
  select t.editor_milestone_shares into v_shares from public.project_terms t
  where t.project_id = new.project_id and t.status = 'agreed';
  if v_shares is null or not private.terms_shares_valid(v_shares) then
    v_shares := '{50,50}';
  end if;
  n := cardinality(v_shares);
  begin
    for i in 1 .. n loop
      v_amount := case when i = n then new.agreed_amount - v_sum
                       else round(new.agreed_amount * v_shares[i] / 100, 2) end;
      v_sum := v_sum + v_amount;
      insert into public.payments (assignment_id, project_id, editor_id, kind, milestone_seq, amount, currency,
        status, created_by)
      values (new.id, new.project_id, new.editor_id, 'assignment', i, v_amount, new.agreed_currency, 'not_due',
        new.confirmed_by);
    end loop;
  exception
    when check_violation then
      raise exception 'The agreed amount is too small to split into the editor pay milestones.' using errcode = 'ES422';
  end;
  perform private.sync_editor_milestones(new.project_id, now());
  return null;
end;
$$;

-- Client payment verified, corrected or refunded: re-run the payable rules for the project. The
-- 12C functions already hold the project lock.
create function private.sync_milestones_on_client_payment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.sync_editor_milestones(new.project_id, now());
  return null;
end;
$$;

create trigger client_milestones_sync_editor_pay
  after update of verification_status on public.client_milestones
  for each row
  when (old.verification_status is distinct from new.verification_status)
  execute function private.sync_milestones_on_client_payment();

create trigger client_milestones_sync_editor_pay_refund
  after insert on public.client_milestones
  for each row
  when (new.kind = 'refund')
  execute function private.sync_milestones_on_client_payment();

-- Project approved: later milestones may become payable (replaces the Phase 8 update that moved
-- every not_due payment of the assignment).
create function private.sync_milestones_on_approval()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.sync_editor_milestones(new.id, now());
  return null;
end;
$$;

create trigger projects_sync_editor_pay
  after update of status on public.projects
  for each row
  when (new.status = 'approved' and old.status is distinct from new.status)
  execute function private.sync_milestones_on_approval();

-- ---------------------------------------------------------------------------
-- private.review_submission (Phase 8 body) without the direct payments update: approval now moves
-- only the milestones whose client condition holds, through projects_sync_editor_pay.
-- ---------------------------------------------------------------------------
create or replace function private.review_submission(p_admin uuid, p_submission_id uuid, p_outcome text, p_feedback text,
  p_type text, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.submissions;
  v public.assignments;
  v_project public.projects;
  v_outcome public.submission_outcome;
  v_type public.revision_type;
  v_feedback text;
  v_reason text;
  v_round int;
  v_id uuid;
begin
  select * into s from public.submissions where id = p_submission_id;
  if s.id is null then
    raise exception 'Submission not found.' using errcode = 'ES422';
  end if;
  v := private.lock_assignment(s.assignment_id);
  select * into s from public.submissions where id = p_submission_id for update;
  select * into v_project from public.projects where id = s.project_id;
  if s.outcome is not null then
    raise exception 'This submission has already been reviewed.' using errcode = 'ES409';
  end if;
  if v.status <> 'in_progress' or v_project.status <> 'in_review' or v_project.archived_at is not null then
    raise exception 'This submission can no longer be reviewed.' using errcode = 'ES409';
  end if;

  if p_outcome is null or p_outcome not in ('approved', 'revision_requested', 'rejected_needs_discussion',
                                            'scope_change_required') then
    raise exception 'Please choose a review outcome.' using errcode = 'ES422';
  end if;
  v_outcome := p_outcome::public.submission_outcome;
  v_feedback := private.clean_text(p_feedback, 4000, 'feedback');
  if v_outcome <> 'approved' and v_feedback is null then
    raise exception 'Feedback for the editor is required unless you approve.' using errcode = 'ES422';
  end if;
  if v_outcome = 'revision_requested' then
    if p_type is null or p_type not in ('client_revision', 'editor_correction') then
      raise exception 'A revision request is a client revision or an editor correction.' using errcode = 'ES422';
    end if;
    v_type := p_type::public.revision_type;
  elsif v_outcome = 'scope_change_required' then
    v_type := 'scope_change';
  elsif v_outcome = 'rejected_needs_discussion' then
    if p_type is null or p_type not in ('client_revision', 'editor_correction', 'scope_change') then
      raise exception 'Please choose client revision, editor correction or scope change.' using errcode = 'ES422';
    end if;
    v_type := p_type::public.revision_type;
  end if;
  if v_outcome <> 'approved' then
    v_reason := private.clean_text(p_reason, 4000, 'reason');
    if v_reason is null then
      raise exception 'Please give the reason for this change request.' using errcode = 'ES422';
    end if;
  end if;

  update public.submissions
  set outcome = v_outcome, feedback = v_feedback, reviewed_by = p_admin, reviewed_at = clock_timestamp()
  where id = s.id;

  if v_outcome = 'approved' then
    update public.revision_requests set status = 'approved', resolved_at = clock_timestamp()
    where id = s.revision_request_id and status = 'resubmitted';
    -- Phase 12D: projects_sync_editor_pay makes the later milestones payable when the client
    -- balance is verified (otherwise they wait; see late-balance protection).
    update public.projects set status = 'approved' where id = s.project_id;
    return null;
  end if;

  if v_type = 'client_revision' then
    v_round := 1 + (select count(*) from public.revision_requests
                    where project_id = s.project_id and type = 'client_revision');
  end if;
  insert into public.revision_requests (project_id, assignment_id, submission_id, type, round_number,
    beyond_allowance, reason, status, created_by, classified_by, classified_at)
  values (s.project_id, v.id, s.id, v_type, v_round, coalesce(v_round > v_project.revision_allowance, false),
    v_reason, case when v_outcome = 'rejected_needs_discussion' then 'disputed' else 'requested' end::public.revision_status,
    p_admin, p_admin, clock_timestamp())
  returning id into v_id;
  update public.projects set status = 'revision_requested' where id = s.project_id;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Timed rules (12C body) + late-balance protection (KB9a-1, §5). A project that is approved (or
-- completed), whose remaining client balance rows are all invoiced and still unverified
-- late_balance_days (terms, default 14) after their due date, and with no payment row on hold on
-- the assignment (any hold, not only a dispute split): the not_due later milestones become payable with reason late_balance_protection
-- (Lenscape carries the risk). The day ends in the business timezone: the rule acts from the day
-- after due date + late_balance_days. Once payable a row is no longer not_due, so the rule acts
-- (and audits and notifies) once per milestone.
-- ---------------------------------------------------------------------------
create function private.late_balance_due(p_project_id uuid, p_today date)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not private.client_balance_verified(p_project_id)
    and exists (select 1 from public.client_milestones m
                where m.project_id = p_project_id and m.kind = 'balance' and m.voided_at is null
                  and m.verification_status <> 'verified')
    and not exists (
      select 1 from public.client_milestones m
      where m.project_id = p_project_id and m.kind = 'balance' and m.voided_at is null
        and m.verification_status <> 'verified'
        and (m.invoice_issued_at is null or m.due_date is null
             or m.due_date + coalesce((select t.late_balance_days from public.project_terms t
                                       where t.project_id = p_project_id and t.status = 'agreed'), 14) >= p_today));
$$;

create or replace function private.apply_timed_rules(p_now timestamptz)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select p.id from public.profiles p where p.id = (select auth.uid()));
  v_today date;
  r record;
  q record;
  v_project public.projects;
  v_m public.client_milestones;
  v_due date;
  v_count int := 0;
begin
  if p_now is null then
    raise exception 'A time is required.' using errcode = 'ES422';
  end if;
  v_today := private.business_date(p_now);

  -- KB9a-2 unpaid-deposit auto-hold (12C, unchanged).
  for r in
    select m.id, m.project_id from public.client_milestones m
    join public.projects p on p.id = m.project_id
    where m.kind = 'deposit' and m.voided_at is null and m.verification_status <> 'verified'
      and m.invoice_issued_at is not null and m.auto_held_for_due is distinct from m.due_date
      and m.due_date < v_today and p.status = 'assigned' and p.archived_at is null
    order by m.project_id
  loop
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

  -- KB9a-1 late-balance protection.
  for r in
    select distinct pay.project_id from public.payments pay
    join public.projects pr on pr.id = pay.project_id
    join public.assignments a on a.id = pay.assignment_id
    where pay.kind = 'assignment' and pay.status = 'not_due' and pay.milestone_seq > 1
      and a.status in ('confirmed', 'in_progress')
      and pr.status in ('approved', 'completed') and pr.archived_at is null
    order by pay.project_id
  loop
    -- Project, then assignments, then payments; re-check under the locks.
    select * into v_project from public.projects where id = r.project_id for update;
    perform 1 from public.assignments
    where project_id = r.project_id and status in ('confirmed', 'in_progress') order by id for update;
    if v_project.status not in ('approved', 'completed') or v_project.archived_at is not null
       or not private.late_balance_due(r.project_id, v_today) then
      continue;
    end if;
    v_due := v_today + private.editor_pay_days(r.project_id);

    for q in
      select pay.id, pay.assignment_id from public.payments pay
      join public.assignments a on a.id = pay.assignment_id
      where pay.project_id = r.project_id and pay.kind = 'assignment' and pay.status = 'not_due'
        and pay.milestone_seq > 1 and a.status in ('confirmed', 'in_progress')
        -- Conservative (owner to confirm): any held row on the assignment pauses protection.
        and not exists (select 1 from public.payments d
                        where d.assignment_id = pay.assignment_id and d.status = 'on_hold')
      order by pay.id
      for update of pay
    loop
      update public.payments
      set status = 'pending_approval', payable_reason = 'late_balance_protection', payable_at = p_now, due_date = v_due
      where id = q.id;
      insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
      values (v_actor, 'payment.late_balance_payable', 'payment', q.id::text,
        jsonb_build_object('payment_id', q.id, 'assignment_id', q.assignment_id, 'project_id', r.project_id,
          'reason', 'late_balance_protection'));
      perform private.notify(private.active_admin_ids(), 'late_balance_payable', 'payment', q.id,
        'Editor milestone payable: late client balance',
        format('The client balance for "%s" is overdue, so the editor''s milestone is now payable (late-balance protection). Approve it within the editor pay days.',
          v_project.title));
      v_count := v_count + 1;
    end loop;
  end loop;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_split_payment_for_dispute (§4.5, KB9a-4): splits an unpaid milestone that is not on hold
-- into the undisputed row (this row, amount reduced) and a disputed child row on hold with the
-- admin's reason. Only the child is held; releasing it returns it to the parent's status at the
-- split. Returns the child id.
-- ---------------------------------------------------------------------------
create function public.admin_split_payment_for_dispute(p_payment_id uuid, p_disputed_amount numeric, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_project_id uuid;
  v_assignment_id uuid;
  v public.payments;
  v_reason text := private.clean_text(p_reason, 500, 'reason');
  v_id uuid;
begin
  select project_id, assignment_id into v_project_id, v_assignment_id from public.payments where id = p_payment_id;
  if v_project_id is null then
    raise exception 'Payment not found.' using errcode = 'ES422';
  end if;
  perform 1 from public.projects where id = v_project_id for update;
  perform 1 from public.assignments where id = v_assignment_id for update;
  v := private.lock_payment(p_payment_id);
  perform private.require_unpaid(v);
  if v.kind <> 'assignment' or v.status = 'on_hold' then
    raise exception 'Only an unpaid milestone that is not on hold can be split.' using errcode = 'ES409';
  end if;
  if v.split_from_payment_id is not null or v.amount_before_split is not null then
    raise exception 'This payment was already split for a dispute.' using errcode = 'ES409';
  end if;
  if p_disputed_amount is null or p_disputed_amount <= 0 or p_disputed_amount >= v.amount
     or p_disputed_amount <> round(p_disputed_amount, 2) then
    raise exception 'The disputed amount must be more than 0 and less than the payment, in whole cents.'
      using errcode = 'ES422';
  end if;
  if v_reason is null then
    raise exception 'Please give a reason for the dispute hold.' using errcode = 'ES422';
  end if;

  set constraints public.payments_split_sum deferred;
  perform set_config('es.payment_split', v.id::text, true);
  update public.payments set amount = v.amount - p_disputed_amount, amount_before_split = v.amount where id = v.id;
  perform set_config('es.payment_split', '', true);
  insert into public.payments (assignment_id, project_id, editor_id, kind, milestone_seq, amount, currency, status,
    held_from_status, on_hold_reason, split_from_payment_id, payable_reason, payable_at, due_date,
    approved_by, approved_at, created_by)
  values (v.assignment_id, v.project_id, v.editor_id, 'assignment', v.milestone_seq, p_disputed_amount, v.currency,
    'on_hold', v.status, v_reason, v.id, v.payable_reason, v.payable_at, v.due_date,
    v.approved_by, v.approved_at, v_admin)
  returning id into v_id;
  set constraints public.payments_split_sum immediate;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'payment.dispute_split', 'payment', v.id::text,
    jsonb_build_object('payment_id', v.id, 'assignment_id', v.assignment_id, 'child_payment_id', v_id,
      'fields', '["amount", "on_hold_reason"]'::jsonb));
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_set_payment_status (Phase 9 body): a not_due milestone becomes payable only through the
-- milestone rules (client money verified, approval, late-balance protection), never by hand.
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_payment_status(p_payment_id uuid, p_status text, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v public.payments;
  v_to public.payment_status;
  v_reason text;
begin
  v := private.lock_payment(p_payment_id);
  if p_status = 'paid' then
    raise exception 'Use mark as paid.' using errcode = 'ES422';
  end if;
  if p_status is null or p_status not in ('pending_approval', 'approved', 'processing', 'on_hold') then
    raise exception 'Choose a valid payment status.' using errcode = 'ES422';
  end if;
  v_to := p_status::public.payment_status;
  perform private.require_unpaid(v);
  if v.status = 'not_due' and v_to = 'pending_approval' then
    raise exception 'This milestone becomes payable automatically once its client payment is verified.'
      using errcode = 'ES409';
  end if;
  if v_to = 'on_hold' then
    v_reason := private.clean_text(p_reason, 500, 'reason');
    if v_reason is null then
      raise exception 'Please give a reason for the hold.' using errcode = 'ES422';
    end if;
  end if;
  if not private.payment_transition_allowed(v.status, v_to) then
    raise exception 'This payment cannot move from % to %.',
      replace(v.status::text, '_', ' '), replace(v_to::text, '_', ' ') using errcode = 'ES409';
  end if;

  if v_to = 'on_hold' then
    update public.payments set status = 'on_hold', held_from_status = v.status, on_hold_reason = v_reason
    where id = v.id;
  elsif v_to = 'approved' then
    update public.payments set status = 'approved', approved_by = v_admin, approved_at = now() where id = v.id;
  else
    update public.payments set status = v_to where id = v.id;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_release_payment_hold (Phase 9 body): now locks project, assignment, payment in order and
-- re-runs the payable rules (a row released to not_due may already be payable).
-- ---------------------------------------------------------------------------
create or replace function public.admin_release_payment_hold(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_project_id uuid;
  v_assignment_id uuid;
  v public.payments;
begin
  select project_id, assignment_id into v_project_id, v_assignment_id from public.payments where id = p_payment_id;
  if v_project_id is null then
    raise exception 'Payment not found.' using errcode = 'ES422';
  end if;
  perform 1 from public.projects where id = v_project_id for update;
  perform 1 from public.assignments where id = v_assignment_id for update;
  v := private.lock_payment(p_payment_id);
  perform private.require_unpaid(v);
  if v.status <> 'on_hold' then
    raise exception 'This payment is not on hold.' using errcode = 'ES409';
  end if;
  update public.payments set status = v.held_from_status, held_from_status = null, on_hold_reason = null
  where id = v.id;
  if v.held_from_status = 'not_due' then
    perform private.sync_editor_milestones(v.project_id, now());
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_reverse_payment (Phase 9 body): locks project, assignment, payment in order; the reversal
-- and any re-opened row keep the milestone; the open-row check is per milestone.
-- ---------------------------------------------------------------------------
create or replace function public.admin_reverse_payment(p_payment_id uuid, p_reason text, p_reopen boolean)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v public.payments;
  v_reason text;
  v_id uuid;
  v_project_id uuid;
  v_assignment_id uuid;
begin
  select project_id, assignment_id into v_project_id, v_assignment_id from public.payments where id = p_payment_id;
  if v_project_id is null then
    raise exception 'Payment not found.' using errcode = 'ES422';
  end if;
  perform 1 from public.projects where id = v_project_id for update;
  perform 1 from public.assignments where id = v_assignment_id for update;
  v := private.lock_payment(p_payment_id);
  if v.kind <> 'assignment' or v.status <> 'paid' then
    raise exception 'Only a paid payment can be reversed.' using errcode = 'ES409';
  end if;
  if exists (select 1 from public.payments where reverses_payment_id = v.id) then
    raise exception 'This payment has already been reversed.' using errcode = 'ES409';
  end if;
  v_reason := private.clean_text(p_reason, 500, 'reason');
  if v_reason is null then
    raise exception 'Please give a reason for the reversal.' using errcode = 'ES422';
  end if;
  if p_reopen is null then
    raise exception 'Choose whether to re-open the payment.' using errcode = 'ES422';
  end if;
  if p_reopen and exists (select 1 from public.assignments
                          where id = v.assignment_id
                            and status in ('reassigned', 'withdrawn', 'declined', 'not_selected')) then
    raise exception 'This assignment has ended, so the payment cannot be re-opened.' using errcode = 'ES409';
  end if;
  if p_reopen and exists (select 1 from public.payments
                          where assignment_id = v.assignment_id and milestone_seq = v.milestone_seq
                            and kind = 'assignment' and status <> 'paid' and split_from_payment_id is null) then
    raise exception 'This milestone already has an open payment.' using errcode = 'ES409';
  end if;

  begin
    insert into public.payments (assignment_id, project_id, editor_id, kind, milestone_seq, amount, currency, status,
      reverses_payment_id, reversal_reason, marked_paid_by, marked_paid_at, created_by)
    values (v.assignment_id, v.project_id, v.editor_id, 'reversal', v.milestone_seq, -v.amount, v.currency, 'paid',
      v.id, v_reason, v_admin, now(), v_admin)
    returning id into v_id;
    if p_reopen then
      insert into public.payments (assignment_id, project_id, editor_id, kind, milestone_seq, amount, currency, status,
        payable_reason, payable_at, created_by)
      values (v.assignment_id, v.project_id, v.editor_id, 'assignment', v.milestone_seq, v.amount, v.currency,
        'pending_approval', v.payable_reason, case when v.payable_reason is not null then now() end, v_admin);
    end if;
  exception
    when unique_violation then
      raise exception 'This payment changed at the same time. Please reload and try again.' using errcode = 'ES409';
    when check_violation then
      raise exception 'This reversal is not valid.' using errcode = 'ES422';
  end;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- editor_list_payments (return type changes: dropped and recreated; only the app calls it). Own
-- rows with the project title, the milestone, a fixed hold label and the waiting flag. Never the
-- free-text hold or reversal reason, the payable reason (it would reveal the client's payment state beyond
-- "waiting"), admin ids or any client money (KB9a-5).
-- ---------------------------------------------------------------------------
drop function public.editor_list_payments();

create function public.editor_list_payments()
returns table (id uuid, project_id uuid, project_title text, kind public.payment_kind, milestone_seq smallint,
  amount numeric, currency char(3), status public.payment_status, hold_label public.payment_hold_label,
  waiting_on_client boolean, reverses_payment_id uuid, split_from_payment_id uuid,
  due_date date, transfer_date date, transaction_reference text, approved_at timestamptz,
  marked_paid_at timestamptz, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_editor();
begin
  return query
  select p.id, p.project_id, pr.title, p.kind, p.milestone_seq, p.amount, p.currency, p.status,
    (case
       when p.status = 'on_hold' and p.split_from_payment_id is null and a.status in ('reassigned', 'withdrawn')
         then 'assignment_ended'
       when p.status = 'on_hold' then 'under_review'
       when p.status = 'not_due' and p.waiting_on_client then 'waiting_for_client_payment'
     end)::public.payment_hold_label,
    p.waiting_on_client, p.reverses_payment_id, p.split_from_payment_id, p.due_date,
    p.transfer_date, p.transaction_reference, p.approved_at, p.marked_paid_at, p.created_at
  from public.payments p
  join public.projects pr on pr.id = p.project_id
  join public.assignments a on a.id = p.assignment_id
  where p.editor_id = v_uid
  order by p.created_at desc, p.milestone_seq, p.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges
-- ---------------------------------------------------------------------------
revoke all on function
  private.client_balance_verified(uuid), private.editor_pay_days(uuid),
  private.sync_editor_milestones(uuid, timestamptz), private.sync_milestones_on_client_payment(),
  private.sync_milestones_on_approval(), private.late_balance_due(uuid, date)
from public, anon, authenticated;

revoke all on function
  public.admin_split_payment_for_dispute(uuid, numeric, text), public.editor_list_payments()
from public, anon, authenticated;
grant execute on function
  public.admin_split_payment_for_dispute(uuid, numeric, text), public.editor_list_payments()
to anon, authenticated;
