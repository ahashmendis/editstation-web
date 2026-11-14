-- Phase 9 (3/3): admin payment functions and the editor earnings list. Spec §8; plan calls 5-7.
-- Each admin function locks the target payments row (reversal: the original) before reading it.
-- Errors: ES401/ES403 from the helpers, ES409 state, ES422 input. Audit rows come from the
-- payments_audit trigger, except payment_note.added below (ids only).

-- Locks and returns the payment, or raises the shared "not found" message.
create function private.lock_payment(p_payment_id uuid)
returns public.payments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.payments;
begin
  select * into v from public.payments where id = p_payment_id for update;
  if not found then
    raise exception 'Payment not found.' using errcode = 'ES422';
  end if;
  return v;
end;
$$;

create function private.require_unpaid(p public.payments)
returns void
language plpgsql
immutable
security definer
set search_path = ''
as $$
begin
  if p.status = 'paid' then
    raise exception 'This payment has been paid and cannot be changed.' using errcode = 'ES409';
  end if;
end;
$$;

revoke all on function private.lock_payment(uuid), private.require_unpaid(public.payments)
from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- admin_set_payment_status: pending_approval, approved, processing, on_hold (with a reason)
-- ---------------------------------------------------------------------------
create function public.admin_set_payment_status(p_payment_id uuid, p_status text, p_reason text default null)
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
-- admin_release_payment_hold: back to held_from_status; the reason is cleared
-- ---------------------------------------------------------------------------
create function public.admin_release_payment_hold(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v public.payments;
begin
  v := private.lock_payment(p_payment_id);
  perform private.require_unpaid(v);
  if v.status <> 'on_hold' then
    raise exception 'This payment is not on hold.' using errcode = 'ES409';
  end if;
  update public.payments set status = v.held_from_status, held_from_status = null, on_hold_reason = null
  where id = v.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_mark_payment_paid: from approved or processing, with reference and transfer date
-- ---------------------------------------------------------------------------
create function public.admin_mark_payment_paid(p_payment_id uuid, p_transaction_reference text, p_transfer_date date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v public.payments;
  v_reference text;
  v_confirmed date;
begin
  v := private.lock_payment(p_payment_id);
  perform private.require_unpaid(v);
  if not private.payment_transition_allowed(v.status, 'paid') then
    raise exception 'This payment cannot move from % to paid.', replace(v.status::text, '_', ' ')
      using errcode = 'ES409';
  end if;
  v_reference := private.clean_text(p_transaction_reference, 120, 'transaction reference');
  if v_reference is null then
    raise exception 'Please enter the transaction reference.' using errcode = 'ES422';
  end if;
  if p_transfer_date is null then
    raise exception 'Please enter the transfer date.' using errcode = 'ES422';
  end if;
  if p_transfer_date > (now() at time zone 'Asia/Colombo')::date then
    raise exception 'The transfer date cannot be in the future.' using errcode = 'ES422';
  end if;
  select (a.confirmed_at at time zone 'Asia/Colombo')::date into v_confirmed
  from public.assignments a where a.id = v.assignment_id;
  if v_confirmed is not null and p_transfer_date < v_confirmed then
    raise exception 'The transfer date cannot be before the editor was confirmed.' using errcode = 'ES422';
  end if;
  update public.payments
  set status = 'paid', transaction_reference = v_reference, transfer_date = p_transfer_date,
      marked_paid_by = v_admin, marked_paid_at = now()
  where id = v.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_set_payment_due_date: any unpaid status; null clears it (KB9: set by hand)
-- ---------------------------------------------------------------------------
create function public.admin_set_payment_due_date(p_payment_id uuid, p_due_date date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v public.payments;
begin
  v := private.lock_payment(p_payment_id);
  perform private.require_unpaid(v);
  update public.payments set due_date = p_due_date where id = v.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_reverse_payment: full reversal row; optionally re-open the liability for re-approval
-- ---------------------------------------------------------------------------
create function public.admin_reverse_payment(p_payment_id uuid, p_reason text, p_reopen boolean)
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
begin
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
                          where assignment_id = v.assignment_id and kind = 'assignment' and status <> 'paid') then
    raise exception 'This assignment already has an open payment.' using errcode = 'ES409';
  end if;

  begin
    insert into public.payments (assignment_id, project_id, editor_id, kind, amount, currency, status,
      reverses_payment_id, reversal_reason, marked_paid_by, marked_paid_at, created_by)
    values (v.assignment_id, v.project_id, v.editor_id, 'reversal', -v.amount, v.currency, 'paid',
      v.id, v_reason, v_admin, now(), v_admin)
    returning id into v_id;
    if p_reopen then
      insert into public.payments (assignment_id, project_id, editor_id, kind, amount, currency, status, created_by)
      values (v.assignment_id, v.project_id, v.editor_id, 'assignment', v.amount, v.currency, 'pending_approval',
        v_admin);
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
-- admin_add_payment_note: append-only admin notes (never shown to editors)
-- ---------------------------------------------------------------------------
create function public.admin_add_payment_note(p_payment_id uuid, p_note text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v public.payments;
  v_note text;
  v_id uuid;
begin
  select * into v from public.payments where id = p_payment_id;
  if not found then
    raise exception 'Payment not found.' using errcode = 'ES422';
  end if;
  v_note := private.clean_text(p_note, 4000, 'note');
  if v_note is null then
    raise exception 'Please write a note.' using errcode = 'ES422';
  end if;
  insert into public.payment_notes (payment_id, author_id, note) values (v.id, v_admin, v_note)
  returning id into v_id;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'payment_note.added', 'payment', v.id::text,
    jsonb_build_object('payment_id', v.id, 'assignment_id', v.assignment_id, 'from', null, 'to', null));
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- editor_list_payments: own payments with only the project id and title (spec §6)
-- ---------------------------------------------------------------------------
create function public.editor_list_payments()
returns table (id uuid, project_id uuid, project_title text, kind public.payment_kind, amount numeric,
  currency char(3), status public.payment_status, on_hold_reason text, reversal_reason text,
  reverses_payment_id uuid, due_date date, transfer_date date, transaction_reference text,
  approved_at timestamptz, marked_paid_at timestamptz, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_editor();
begin
  return query
  select p.id, p.project_id, pr.title, p.kind, p.amount, p.currency, p.status, p.on_hold_reason,
    p.reversal_reason, p.reverses_payment_id, p.due_date, p.transfer_date, p.transaction_reference,
    p.approved_at, p.marked_paid_at, p.created_at
  from public.payments p
  join public.projects pr on pr.id = p.project_id
  where p.editor_id = v_uid
  order by p.created_at desc, p.id;
end;
$$;

revoke all on function
  public.admin_set_payment_status(uuid, text, text), public.admin_release_payment_hold(uuid),
  public.admin_mark_payment_paid(uuid, text, date), public.admin_set_payment_due_date(uuid, date),
  public.admin_reverse_payment(uuid, text, boolean), public.admin_add_payment_note(uuid, text),
  public.editor_list_payments()
from public, anon, authenticated;
grant execute on function
  public.admin_set_payment_status(uuid, text, text), public.admin_release_payment_hold(uuid),
  public.admin_mark_payment_paid(uuid, text, date), public.admin_set_payment_due_date(uuid, date),
  public.admin_reverse_payment(uuid, text, boolean), public.admin_add_payment_note(uuid, text),
  public.editor_list_payments()
to anon, authenticated;
