-- Phase 12C (3/4): client billing functions. Spec §4.2, §5, calls 4 and 9; decisions KB9, KB9b.
-- Lock order: the projects row first (as everywhere), then client_milestones rows.
-- Audit rows hold ids and field names only (never amounts, references, dates or reasons).
-- Errors: ES401/ES403 from the helpers, ES409 state, ES422 input.

-- ---------------------------------------------------------------------------
-- Helpers (private, no API grants)
-- ---------------------------------------------------------------------------

-- Locks the milestone's project (then the milestone) and returns the milestone. Archived projects
-- are refused; cancelled ones are allowed when p_allow_cancelled (money still moves after a
-- cancellation, e.g. a refund).
create function private.lock_client_milestone(p_milestone_id uuid, p_allow_cancelled boolean)
returns public.client_milestones
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_project_id uuid;
  v_project public.projects;
  v public.client_milestones;
begin
  select project_id into v_project_id from public.client_milestones where id = p_milestone_id;
  if v_project_id is null then
    raise exception 'Client milestone not found.' using errcode = 'ES422';
  end if;
  select * into v_project from public.projects where id = v_project_id for update;
  if v_project.archived_at is not null then
    raise exception 'This project is archived. Restore it first.' using errcode = 'ES409';
  end if;
  if v_project.status = 'cancelled' and not p_allow_cancelled then
    raise exception 'This project is cancelled.' using errcode = 'ES409';
  end if;
  select * into v from public.client_milestones where id = p_milestone_id for update;
  if v.voided_at is not null then
    raise exception 'This milestone was replaced. Refresh to see the current milestones.' using errcode = 'ES409';
  end if;
  return v;
end;
$$;

-- Work has begun or is past the start (any status from in_progress on).
create function private.project_past_start(p_project_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.project_work_started(p_project_id)
    or exists (select 1 from public.projects p where p.id = p_project_id
               and p.status in ('in_progress', 'in_review', 'revision_requested', 'approved', 'completed'));
$$;

-- ---------------------------------------------------------------------------
-- admin_create_client_milestones: computes the client milestones once from the agreed terms and
-- the client price (KB9b-1). p_shares is the per-project split in percent (default 50/50; e.g.
-- {100} for 100% upfront): the first row is the deposit, the rest are balance rows, and the last
-- row takes the rounding remainder (call 9). Only before work starts; uninvoiced, unpaid rows
-- from an earlier call are kept as voided and replaced. Returns the number of rows created.
-- ---------------------------------------------------------------------------
create function public.admin_create_client_milestones(p_project_id uuid, p_shares int[] default null)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_shares int[] := coalesce(p_shares, '{50,50}');
  v_terms public.project_terms;
  v_price numeric(12, 2);
  v_currency char(3);
  v_amount numeric(12, 2);
  v_sum numeric(12, 2) := 0;
  v_voided uuid[];
  v_ids uuid[] := '{}';
  v_id uuid;
  v_seq int;
  i int;
begin
  if cardinality(v_shares) is null or cardinality(v_shares) not between 1 and 10
     or array_position(v_shares, null) is not null
     or (select bool_or(s < 1 or s > 100) or sum(s) <> 100 from unnest(v_shares) s) then
    raise exception 'Client milestones must be 1 to 10 whole percentages adding up to 100.' using errcode = 'ES422';
  end if;

  perform private.lock_writable_project(p_project_id);

  if private.project_past_start(p_project_id) then
    raise exception 'Client milestones cannot change after work has begun.' using errcode = 'ES409';
  end if;
  select * into v_terms from public.project_terms where project_id = p_project_id and status = 'agreed';
  if v_terms.id is null then
    raise exception 'Agree the project terms before creating client milestones.' using errcode = 'ES409';
  end if;
  select client_price, client_price_currency into v_price, v_currency
  from public.project_internal where project_id = p_project_id;
  if v_price is null or v_price <= 0 then
    raise exception 'Set the client price before creating client milestones.' using errcode = 'ES409';
  end if;

  perform 1 from public.client_milestones where project_id = p_project_id and voided_at is null for update;
  if exists (select 1 from public.client_milestones where project_id = p_project_id and voided_at is null
             and (invoice_issued_at is not null or verification_status <> 'expected' or kind not in ('deposit', 'balance'))) then
    raise exception 'An invoice was issued or a payment recorded, so the client milestones cannot be replaced.'
      using errcode = 'ES409';
  end if;

  with v as (
    update public.client_milestones set voided_at = now(), voided_by = v_admin
    where project_id = p_project_id and voided_at is null
    returning id)
  select coalesce(array_agg(id), '{}') into v_voided from v;

  v_seq := coalesce((select max(seq) from public.client_milestones where project_id = p_project_id), 0);
  begin
    for i in 1 .. cardinality(v_shares) loop
      v_amount := case when i = cardinality(v_shares) then v_price - v_sum
                       else round(v_price * v_shares[i] / 100, 2) end;
      v_sum := v_sum + v_amount;
      insert into public.client_milestones (project_id, terms_id, seq, kind, share_percent, amount, currency, created_by)
      values (p_project_id, v_terms.id, v_seq + i,
              case when i = 1 then 'deposit' else 'balance' end::public.client_milestone_kind,
              v_shares[i], v_amount, v_currency, v_admin)
      returning id into v_id;
      v_ids := v_ids || v_id;
    end loop;
  exception
    when check_violation then
      raise exception 'The client price is too small to split into these milestones.' using errcode = 'ES422';
  end;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'client_milestones.created', 'project', p_project_id::text,
    jsonb_build_object('project_id', p_project_id, 'terms_id', v_terms.id, 'milestone_ids', to_jsonb(v_ids),
      'voided_ids', to_jsonb(v_voided),
      'fields', case when v_shares = '{50,50}' then '[]'::jsonb else '["shares"]'::jsonb end));
  return cardinality(v_ids);
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_issue_client_invoice: records that the deposit or balance invoice was sent; the due date
-- is the business-timezone date plus the agreed deposit_days / balance_days (defaults 14 / 7).
-- ---------------------------------------------------------------------------
create function public.admin_issue_client_invoice(p_milestone_id uuid)
returns date
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v public.client_milestones;
  v_days int;
  v_due date;
begin
  v := private.lock_client_milestone(p_milestone_id, false);
  if v.kind not in ('deposit', 'balance') then
    raise exception 'Only a deposit or balance invoice can be issued here.' using errcode = 'ES409';
  end if;
  if v.invoice_issued_at is not null then
    raise exception 'This invoice was already issued.' using errcode = 'ES409';
  end if;
  select case when v.kind = 'deposit' then t.deposit_days else t.balance_days end into v_days
  from public.project_terms t
  where t.project_id = v.project_id and t.status = 'agreed';
  if v_days is null then
    select case when v.kind = 'deposit' then t.deposit_days else t.balance_days end into v_days
    from public.project_terms t where t.id = v.terms_id;
  end if;
  v_due := private.business_date(now()) + coalesce(v_days, case when v.kind = 'deposit' then 14 else 7 end);

  update public.client_milestones set invoice_issued_at = now(), due_date = v_due where id = v.id;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'client_milestone.invoice_issued', 'project', v.project_id::text,
    jsonb_build_object('project_id', v.project_id, 'milestone_id', v.id, 'kind', v.kind));
  return v_due;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_record_client_payment: the transfer arrived (or, for a refund, was sent). Records the
-- transfer reference and date; stays unverified until an admin verifies it. May be re-recorded
-- (to fix a typo) while unverified.
-- ---------------------------------------------------------------------------
create function public.admin_record_client_payment(
  p_milestone_id uuid, p_transfer_reference text, p_received_on date default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v public.client_milestones;
  v_ref text := private.clean_text(p_transfer_reference, 120, 'transfer reference');
  v_today date := private.business_date(now());
  v_fields text[] := '{}';
begin
  if v_ref is null then
    raise exception 'Please enter the transfer reference.' using errcode = 'ES422';
  end if;
  if p_received_on is not null and p_received_on > v_today then
    raise exception 'The transfer date cannot be in the future.' using errcode = 'ES422';
  end if;
  v := private.lock_client_milestone(p_milestone_id, true);
  if v.verification_status = 'verified' then
    raise exception 'This payment is already verified and cannot be changed.' using errcode = 'ES409';
  end if;
  if v.verification_status = 'received_unverified' then
    v_fields := array['transfer_reference', 'received_at'];
  end if;

  update public.client_milestones set
    verification_status = 'received_unverified',
    transfer_reference = v_ref,
    received_at = case when p_received_on is null or p_received_on = v_today then now()
                       else p_received_on::timestamp at time zone private.business_timezone() end
  where id = v.id;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'client_milestone.payment_recorded', 'project', v.project_id::text,
    jsonb_build_object('project_id', v.project_id, 'milestone_id', v.id, 'kind', v.kind,
      'fields', to_jsonb(v_fields)));
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_verify_client_payment: an admin checked the bank and confirms the transfer. Final, except
-- through admin_correct_client_payment.
-- ---------------------------------------------------------------------------
create function public.admin_verify_client_payment(p_milestone_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v public.client_milestones;
begin
  v := private.lock_client_milestone(p_milestone_id, true);
  if v.verification_status = 'verified' then
    raise exception 'This payment is already verified.' using errcode = 'ES409';
  end if;
  if v.verification_status <> 'received_unverified' then
    raise exception 'Record the transfer before verifying it.' using errcode = 'ES409';
  end if;
  update public.client_milestones set verification_status = 'verified', verified_by = v_admin, verified_at = now()
  where id = v.id;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'client_milestone.verified', 'project', v.project_id::text,
    jsonb_build_object('project_id', v.project_id, 'milestone_id', v.id, 'kind', v.kind));
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_correct_client_payment: the audited correction of a mistaken verification (back to
-- received, unverified), with a reason. Refused for a deposit once work has begun (the start gate
-- relied on it) and for a payment that a refund already reverses.
-- ---------------------------------------------------------------------------
create function public.admin_correct_client_payment(p_milestone_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v public.client_milestones;
  v_reason text := private.clean_text(p_reason, 2000, 'reason for the correction');
begin
  if v_reason is null then
    raise exception 'Please give a reason for the correction.' using errcode = 'ES422';
  end if;
  v := private.lock_client_milestone(p_milestone_id, true);
  if v.verification_status <> 'verified' then
    raise exception 'Only a verified payment can be corrected.' using errcode = 'ES409';
  end if;
  if v.kind = 'deposit' and (private.project_past_start(v.project_id)
     or exists (select 1 from public.assignments a where a.project_id = v.project_id and a.status = 'in_progress')) then
    raise exception 'Work has begun on this deposit, so its verification cannot be corrected.' using errcode = 'ES409';
  end if;
  if exists (select 1 from public.client_milestones r where r.reverses_id = v.id) then
    raise exception 'A refund already reverses this payment, so it cannot be corrected.' using errcode = 'ES409';
  end if;

  perform set_config('es.client_milestone_correction', v.id::text, true);
  update public.client_milestones set verification_status = 'received_unverified', verified_by = null,
    verified_at = null, correction_reason = v_reason
  where id = v.id;
  perform set_config('es.client_milestone_correction', '', true);

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'client_milestone.verification_corrected', 'project', v.project_id::text,
    jsonb_build_object('project_id', v.project_id, 'milestone_id', v.id, 'kind', v.kind,
      'fields', '["verification_status", "correction_reason"]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_extend_deposit_due: a later due date for an unverified, invoiced deposit, with a reason.
-- If the project is on the unpaid-deposit hold (auto_held_at set, on hold from assigned), the hold
-- is released back to assigned; the rule may act again after the new date.
-- ---------------------------------------------------------------------------
create function public.admin_extend_deposit_due(p_milestone_id uuid, p_due_date date, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v public.client_milestones;
  v_project public.projects;
  v_reason text := private.clean_text(p_reason, 2000, 'reason for the extension');
  v_released boolean := false;
begin
  if p_due_date is null then
    raise exception 'Please choose the new due date.' using errcode = 'ES422';
  end if;
  if v_reason is null then
    raise exception 'Please give a reason for the extension.' using errcode = 'ES422';
  end if;
  v := private.lock_client_milestone(p_milestone_id, false);
  select * into v_project from public.projects where id = v.project_id;  -- locked above
  if v.kind <> 'deposit' then
    raise exception 'Only the deposit due date can be extended here.' using errcode = 'ES409';
  end if;
  if v.verification_status = 'verified' then
    raise exception 'This deposit is already verified.' using errcode = 'ES409';
  end if;
  if v.invoice_issued_at is null then
    raise exception 'Issue the deposit invoice first.' using errcode = 'ES409';
  end if;
  if p_due_date <= v.due_date or p_due_date < private.business_date(now()) then
    raise exception 'The new due date must be later than the current one and not in the past.' using errcode = 'ES422';
  end if;

  update public.client_milestones set due_date = p_due_date, due_change_reason = v_reason, auto_held_at = null
  where id = v.id;

  if v.auto_held_at is not null and v_project.status = 'on_hold' and v_project.status_before_hold = 'assigned' then
    update public.projects set status = v_project.status_before_hold, status_before_hold = null
    where id = v.project_id;
    v_released := true;
  end if;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'client_milestone.due_extended', 'project', v.project_id::text,
    jsonb_build_object('project_id', v.project_id, 'milestone_id', v.id, 'hold_released', v_released,
      'fields', '["due_date", "due_change_reason"]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_set_business_timezone (call 4): an IANA timezone name known to the database.
-- ---------------------------------------------------------------------------
create function public.admin_set_business_timezone(p_timezone text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_tz text := private.clean_text(p_timezone, 100, 'timezone');
begin
  if v_tz is null or not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = v_tz) then
    raise exception 'Please choose a valid timezone (for example Asia/Colombo).' using errcode = 'ES422';
  end if;
  insert into public.app_settings (key, value, updated_by) values ('business_timezone', to_jsonb(v_tz), v_admin)
  on conflict (key) do update set value = excluded.value, updated_by = excluded.updated_by;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'app_settings.changed', 'app_settings', 'business_timezone',
    jsonb_build_object('fields', '["business_timezone"]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges
-- ---------------------------------------------------------------------------
revoke all on function private.lock_client_milestone(uuid, boolean), private.project_past_start(uuid)
from public, anon, authenticated;

grant execute on function
  public.admin_create_client_milestones(uuid, int[]), public.admin_issue_client_invoice(uuid),
  public.admin_record_client_payment(uuid, text, date), public.admin_verify_client_payment(uuid),
  public.admin_correct_client_payment(uuid, text), public.admin_extend_deposit_due(uuid, date, text),
  public.admin_set_business_timezone(text)
to anon, authenticated;
revoke execute on function
  public.admin_create_client_milestones(uuid, int[]), public.admin_issue_client_invoice(uuid),
  public.admin_record_client_payment(uuid, text, date), public.admin_verify_client_payment(uuid),
  public.admin_correct_client_payment(uuid, text), public.admin_extend_deposit_due(uuid, date, text),
  public.admin_set_business_timezone(text)
from public;
