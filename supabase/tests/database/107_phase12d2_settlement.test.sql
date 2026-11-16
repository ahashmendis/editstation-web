-- Phase 12D part 2: cancellation settlement. Missing schedule (plain cancel keeps the Phase 9 hold),
-- the settle-instead rule, the maths with fractional percentages and rounding (shortfall row,
-- overpayment reversal spread, refunds spread across receipts with the last taking the remainder),
-- the admin's adjusted figure with a reason, the unverified-client-payment refusal, cancelled
-- finality, the refund verified like any transfer, and the editor's safe view.
begin;

create extension if not exists pgtap with schema extensions;

select plan(45);

create function pg_temp.as_user(p_uid uuid, p_aal text default 'aal1')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;
grant execute on function pg_temp.as_user(uuid, text) to authenticated;
create function pg_temp.admin() returns void language sql as $$
  select pg_temp.as_user('d6000000-0000-0000-0000-00000000000a', 'aal2') $$;
create function pg_temp.ed_a() returns void language sql as $$
  select pg_temp.as_user('d6000000-0000-0000-0000-000000000001') $$;
grant execute on function pg_temp.admin(), pg_temp.ed_a() to authenticated;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('d6000000-0000-0000-0000-00000000000a', 'p12d2s-admin@test.local', '{}', '{}'),
  ('d6000000-0000-0000-0000-000000000001', 'p12d2s-editor-a@test.local', '{}', '{}');
select private.grant_admin_by_email('p12d2s-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active' where user_id = 'd6000000-0000-0000-0000-000000000001';
-- Phase 12E: payout details stay locked, so mark-paid needs the interim attestation (call 1).
insert into public.editor_payout_attestations (editor_id, note) values ('d6000000-0000-0000-0000-000000000001', 'TEST attested outside the app');

create temp table ids (kind text primary key, id uuid not null);
grant select, insert on ids to authenticated;
create function pg_temp.a(p_kind text) returns uuid language sql as $$ select id from ids where kind = p_kind $$;
grant execute on function pg_temp.a(text) to authenticated;
create function pg_temp.project(p_kind text) returns uuid language sql as $$
  select project_id from public.assignments where id = (select id from ids where kind = p_kind) $$;
grant execute on function pg_temp.project(text) to authenticated;
create function pg_temp.cm(p_kind text, p_client_kind text) returns uuid language sql as $$
  select id from public.client_milestones where project_id = pg_temp.project(p_kind)
    and kind = p_client_kind::public.client_milestone_kind and voided_at is null order by seq limit 1 $$;
grant execute on function pg_temp.cm(text, text) to authenticated;

-- Agreed terms p_terms, client price 20000 LKR (50/50), deposit verified, editor A confirmed for
-- p_amount LKR; p_start also starts work.
create function pg_temp.flow(p_title text, p_amount numeric, p_terms jsonb, p_start boolean) returns uuid
language plpgsql as $$
declare
  v_project uuid;
  v_id uuid;
  v_dep uuid;
begin
  perform pg_temp.admin();
  v_project := public.admin_create_project(jsonb_build_object('title', p_title, 'brief_type', 'fully_instructed',
    'deadline', '2099-12-31', 'brief', jsonb_build_object('instructions', 'Cut it'),
    'deliverables', jsonb_build_array(jsonb_build_object('name', 'Main'))));
  perform public.admin_set_project_status(v_project, 'open');
  perform public.admin_save_terms_draft(v_project, p_terms);
  perform public.admin_agree_terms(v_project, 1);
  perform public.admin_update_project(v_project, '{"client_price": 20000}');
  perform public.admin_create_client_milestones(v_project, null);
  select id into v_dep from public.client_milestones where project_id = v_project and kind = 'deposit';
  perform public.admin_issue_client_invoice(v_dep);
  perform public.admin_record_client_payment(v_dep, 'TEST-DEP');
  perform public.admin_verify_client_payment(v_dep);
  v_id := public.admin_make_offer(v_project, 'd6000000-0000-0000-0000-000000000001', p_amount, 'LKR');
  perform pg_temp.ed_a();
  perform public.editor_respond_offer(v_id, 'accept');
  perform pg_temp.admin();
  perform public.admin_confirm_assignment(v_id);
  if p_start then
    perform pg_temp.ed_a();
    perform public.editor_confirm_brief(v_id, 1, '2099-12-31', p_amount, 'LKR');
    perform public.editor_start_work(v_id);
  end if;
  reset role;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- No schedule (e.g. backfilled terms): refused cleanly; the plain cancel keeps the Phase 9 hold
-- ---------------------------------------------------------------------------
insert into ids select 'n', pg_temp.flow('No schedule', 1000, '{}', false);
select pg_temp.admin();
select throws_ok($$ select public.admin_preview_cancellation_settlement(pg_temp.project('n')) $$, 'ES409', null,
  'the preview refuses a missing schedule');
select throws_ok($$ select public.admin_settle_cancellation(pg_temp.project('n')) $$, 'ES409',
  'The agreed terms have no cancellation schedule for this stage, so it cannot be settled here. Cancel the project from its status instead; unpaid editor payments then go on hold for you to resolve.',
  'settling refuses a missing schedule');
select lives_ok($$ select public.admin_set_project_status(pg_temp.project('n'), 'cancelled') $$,
  'without a schedule the plain cancel still works');
reset role;
select is((select string_agg(status::text, ',' order by milestone_seq) from public.payments
  where assignment_id = pg_temp.a('n')), 'on_hold,on_hold', 'and unpaid rows go on hold as before (Phase 9)');

-- ---------------------------------------------------------------------------
-- Stage assigned: fractional percentages, rounding, shortfall and a single refund row
-- ---------------------------------------------------------------------------
insert into ids select 's', pg_temp.flow('Assigned stage', 100.01,
  '{"editor_milestone_shares": [33, 33, 34], "stages": [{"stage": "assigned", "editor_earned_percent": 12.5, "client_charge_percent": 7.33}]}',
  false);
select pg_temp.admin();
select throws_ok($$ select public.admin_set_project_status(pg_temp.project('s'), 'cancelled') $$, 'ES409',
  'This project has a confirmed editor and an agreed cancellation schedule. Use Settle cancellation instead.',
  'with a confirmed editor and a schedule, the plain cancel is refused');
select is((select (f ->> 'stage') || ' ' || (f ->> 'computed_editor_earned') || ' ' || (f ->> 'editor_settlement_amount')
    || ' ' || (f ->> 'client_charge') || ' ' || (f ->> 'client_refund') || ' ' || (f ->> 'unpaid_count')
  from public.admin_preview_cancellation_settlement(pg_temp.project('s')) f),
  'assigned 12.50 12.50 1466.00 8534.00 3',
  'preview: 100.01 x 12.5% = 12.50; client charge 20000 x 7.33% = 1466.00; refund 10000 - 1466 = 8534.00');
select throws_ok($$ select public.admin_settle_cancellation(pg_temp.project('s'), 13) $$, 'ES422',
  'Please give the reason for changing the editor''s earned amount.', 'an adjusted figure needs a reason');
insert into ids select 'set_s', public.admin_settle_cancellation(pg_temp.project('s'));
reset role;
select is((select (p.status, a.status)::text from public.projects p join public.assignments a on a.project_id = p.id
  where a.id = pg_temp.a('s')), '(cancelled,withdrawn)', 'the settlement cancels the project and closes the assignment');
select is((select string_agg(status::text, ',' order by milestone_seq) from public.payments
  where assignment_id = pg_temp.a('s') and milestone_seq is not null), 'cancelled,cancelled,cancelled',
  'every unpaid milestone (payable or not) is cancelled');
select ok((select amount = 12.50 and status = 'pending_approval' and payable_reason = 'cancellation_settlement'
    and settlement_id = pg_temp.a('set_s') and milestone_seq is null and due_date = private.business_date(payable_at) + 7
  from public.payments where assignment_id = pg_temp.a('s') and settlement_id is not null),
  'one settlement row pays the shortfall, due editor pay days later');
select is((select (stage, editor_earned_percent, client_charge_percent, computed_editor_earned, editor_earned,
    editor_paid_before, editor_settlement_amount, editor_overpayment, cancelled_payment_count, client_base,
    client_received, client_charge, client_refund, client_owes)::text
  from public.cancellation_settlements where id = pg_temp.a('set_s')),
  '(assigned,12.50,7.33,12.50,12.50,0.00,12.50,0.00,3,20000.00,10000.00,1466.00,8534.00,0.00)',
  'the settlement records every figure');
select is((select (kind, amount, reverses_id = pg_temp.cm('s', 'deposit'), verification_status, settlement_id = pg_temp.a('set_s'))::text
  from public.client_milestones where project_id = pg_temp.project('s') and kind = 'refund'),
  '(refund,-8534.00,t,expected,t)', 'a negative refund row reverses the deposit, waiting to be sent and verified');
select ok(exists (select 1 from public.activity_logs where action = 'project.cancellation_settled'
  and entity_id = pg_temp.project('s')::text and details ? 'settlement_id' and not details ? 'editor_earned'),
  'the settlement is audited with ids only');
select ok((select bool_and(action = 'payment.cancelled') from public.activity_logs
  where action like 'payment.%' and details ->> 'to' = 'cancelled'), 'each cancellation is audited as payment.cancelled');

-- The refund is verified like any transfer; the deposit flag nets it.
select pg_temp.admin();
select public.admin_record_client_payment((select id from public.client_milestones
  where project_id = pg_temp.project('s') and kind = 'refund'), 'TEST-REFUND');
select lives_ok($$ select public.admin_verify_client_payment((select id from public.client_milestones
  where project_id = pg_temp.project('s') and kind = 'refund')) $$, 'the admin verifies the refund transfer');
reset role;
select ok(private.client_deposit_verified(pg_temp.project('s')), 'the deposit still counts (10000 - 8534 > 0)');

-- Cancelled is final.
select pg_temp.admin();
select throws_ok($$ select public.admin_settle_cancellation(pg_temp.project('s')) $$, 'ES409',
  'This cancellation was already settled.', 'a project is settled once');
select throws_ok($$ select public.admin_set_payment_status((select id from public.payments
  where assignment_id = pg_temp.a('s') and milestone_seq = 1), 'approved') $$, 'ES409', null,
  'a cancelled row cannot be approved');
select throws_ok($$ select public.admin_mark_payment_paid((select id from public.payments
  where assignment_id = pg_temp.a('s') and milestone_seq = 1), 'REF', current_date) $$, 'ES409', null,
  'nor marked paid');
select throws_ok($$ select public.admin_release_payment_hold((select id from public.payments
  where assignment_id = pg_temp.a('s') and milestone_seq = 1)) $$, 'ES409', null, 'nor released');
select throws_ok($$ select public.admin_split_payment_for_dispute((select id from public.payments
  where assignment_id = pg_temp.a('s') and milestone_seq = 1), 1, 'x') $$, 'ES409', null, 'nor split');
reset role;
select throws_ok($$ update public.payments set status = 'not_due' where assignment_id = pg_temp.a('s')
  and milestone_seq = 1 $$, 'ES409', 'This payment was cancelled by the cancellation settlement and cannot be changed.',
  'the table owner cannot revive a cancelled row');
select throws_ok($$ update public.payments set status = 'cancelled' where assignment_id = pg_temp.a('n')
  and milestone_seq = 1 $$, 'ES409', 'Only a cancellation settlement can cancel a payment.',
  'only a settlement cancels a row');
select throws_ok($$ insert into public.payments (assignment_id, project_id, editor_id, milestone_seq, amount, currency,
    status) select id, project_id, editor_id, 9, 1, 'LKR', 'cancelled' from public.assignments where id = pg_temp.a('n') $$,
  'ES409', null, 'a row cannot start cancelled');
select throws_ok($$ update public.cancellation_settlements set editor_earned = 0 where id = pg_temp.a('set_s') $$,
  'ES409', null, 'the settlement record is append-only');

-- The editor's view: labels and editor pay only.
select pg_temp.ed_a();
select is((select string_agg(line_kind || ':' || status::text || ':' || amount::text, ',' order by milestone_seq nulls last)
  from public.editor_list_payments() where project_id = pg_temp.project('s')),
  'milestone:cancelled:33.00,milestone:cancelled:33.00,milestone:cancelled:34.01,cancellation_settlement:pending_approval:12.50',
  'editor A sees the cancelled milestones and the settlement row');
select is((select count(*)::int from public.cancellation_settlements) + (select count(*)::int from public.client_milestones),
  0, 'editors read no settlement record and no client money');
reset role;

-- ---------------------------------------------------------------------------
-- Stage in_progress: unverified client payment refused; adjusted figure with a reason;
-- overpayment reversal; refunds spread across receipts
-- ---------------------------------------------------------------------------
insert into ids select 'o', pg_temp.flow('In progress stage', 10000,
  '{"stages": [{"stage": "assigned", "editor_earned_percent": 0, "client_charge_percent": 0}, {"stage": "in_progress", "editor_earned_percent": 20, "client_charge_percent": 30}]}',
  true);
select pg_temp.admin();
select public.admin_set_payment_status((select id from public.payments where assignment_id = pg_temp.a('o')
  and milestone_seq = 1), 'approved');
select public.admin_mark_payment_paid((select id from public.payments where assignment_id = pg_temp.a('o')
  and milestone_seq = 1), 'TEST-PAY', current_date);
select public.admin_record_client_payment(pg_temp.cm('o', 'balance'), 'TEST-BAL');
select throws_ok($$ select public.admin_settle_cancellation(pg_temp.project('o')) $$, 'ES409',
  'Verify or correct the recorded client payments before settling.', 'an unverified client payment blocks settling');
select public.admin_verify_client_payment(pg_temp.cm('o', 'balance'));
select throws_ok($$ select public.admin_settle_cancellation(pg_temp.project('o'), 10000.01, 'Too much') $$, 'ES422',
  null, 'the adjusted figure cannot exceed the agreed pay plus accepted extra pay');
select throws_ok($$ select public.admin_settle_cancellation(pg_temp.project('o'), 1.005, 'Cents') $$, 'ES422', null,
  'the adjusted figure is in whole cents');
insert into ids select 'set_o', public.admin_settle_cancellation(pg_temp.project('o'), 2500.50, 'Two scenes were finished');
reset role;
select is((select (computed_editor_earned, editor_earned, adjustment_reason, editor_paid_before, editor_settlement_amount,
    editor_overpayment, client_received, client_charge, client_refund)::text
  from public.cancellation_settlements where id = pg_temp.a('set_o')),
  '(2000.00,2500.50,"Two scenes were finished",5000.00,0.00,2499.50,20000.00,6000.00,14000.00)',
  'computed 20% = 2000, adjusted to 2500.50 with the reason; paid 5000, so 2499.50 overpaid');
select is((select string_agg(kind || ':' || amount || ':' || status, ',' order by kind, status::text)
  from public.payments where assignment_id = pg_temp.a('o')),
  'assignment:5000.00:cancelled,assignment:5000.00:paid,reversal:-2499.50:paid',
  'the unpaid milestone is cancelled and part of the paid one is reversed (no settlement row)');
select ok((select reverses_payment_id = (select id from public.payments where assignment_id = pg_temp.a('o')
    and milestone_seq = 1 and kind = 'assignment') and settlement_id = pg_temp.a('set_o') and milestone_seq = 1
  from public.payments where assignment_id = pg_temp.a('o') and kind = 'reversal'),
  'the reconciliation reversal names the paid row and the settlement');
select is((select string_agg(m.kind || ':' || r.amount, ',' order by r.seq) from public.client_milestones r
  join public.client_milestones m on m.id = r.reverses_id
  where r.project_id = pg_temp.project('o') and r.kind = 'refund'), 'balance:-10000.00,deposit:-4000.00',
  'the 14000 refund reverses the balance first, the deposit takes the remainder');
select is((select sum(amount) from public.payments where assignment_id = pg_temp.a('o') and status = 'paid'),
  2500.50::numeric, 'net paid now equals the settled earned amount');
select ok(exists (select 1 from public.activity_logs where action = 'project.cancellation_settled'
  and entity_id = pg_temp.project('o')::text
  and details -> 'fields' = '["editor_earned", "adjustment_reason"]'::jsonb), 'the adjustment is audited by field name');
select throws_ok($$ insert into public.payments (assignment_id, project_id, editor_id, kind, milestone_seq,
    settlement_id, amount, currency, payable_reason, payable_at)
  select id, project_id, editor_id, 'assignment', null, pg_temp.a('set_o'), 1, 'LKR', 'cancellation_settlement', now()
  from public.assignments where id = pg_temp.a('o') $$, 'ES409', 'A settlement payment must match the settlement.',
  'no settlement row beyond the shortfall');
select pg_temp.ed_a();
select is((select line_kind || ':' || amount from public.editor_list_payments() where kind = 'reversal'
  and project_id = pg_temp.project('o')), 'cancellation_reconciliation:-2499.50',
  'the editor sees the reconciliation with a fixed label');
reset role;

-- ---------------------------------------------------------------------------
-- Accepted extra pay counts as earned in full; paid extra pay is not reversed, unpaid extra pay
-- stays payable; only milestones are cancelled or reconciled
-- ---------------------------------------------------------------------------
create function pg_temp.extra_round(p_kind text, p_amount numeric) returns void language plpgsql as $$
declare
  v_sub uuid;
  v_rev uuid;
  v_adj uuid;
begin
  perform pg_temp.ed_a();
  v_sub := public.editor_submit_work(pg_temp.a('e'), 'https://drive.example/' || p_kind);
  perform pg_temp.admin();
  v_rev := public.admin_review_submission(v_sub, 'revision_requested', 'Feedback', 'client_revision', 'Reason');
  perform public.admin_set_revision_adjustment_required(v_rev, true);
  v_adj := public.admin_offer_adjustment(pg_temp.a('e'), 'extra_round', p_amount, v_rev);
  perform pg_temp.ed_a();
  perform public.editor_respond_adjustment(v_adj, 'accept');
  reset role;
  insert into ids values (p_kind, v_adj);
end;
$$;
insert into ids select 'e', pg_temp.flow('Extra pay stage', 10000,
  '{"stages": [{"stage": "revision_requested", "editor_earned_percent": 40, "client_charge_percent": 50}]}', true);
select pg_temp.extra_round('ea1', 1000);
select pg_temp.admin();
select public.admin_set_payment_status((select id from public.payments where adjustment_id = pg_temp.a('ea1')), 'approved');
select public.admin_mark_payment_paid((select id from public.payments where adjustment_id = pg_temp.a('ea1')),
  'TEST-EXTRA', current_date);
reset role;
select pg_temp.extra_round('ea2', 500);
select pg_temp.admin();
select is((select (f ->> 'computed_editor_earned') || ' ' || (f ->> 'editor_extra_pay') || ' '
    || (f ->> 'editor_settlement_amount') || ' ' || (f ->> 'unpaid_count')
  from public.admin_preview_cancellation_settlement(pg_temp.project('e')) f), '5500.00 1500.00 4000.00 2',
  'preview: 40% of 10000 plus 1500 accepted extra pay; the shortfall counts milestones only');
select throws_ok($$ select public.admin_settle_cancellation(pg_temp.project('e'), 1499.99, 'Too low') $$, 'ES422', null,
  'the earned figure cannot go below the accepted extra pay');
insert into ids select 'set_e', public.admin_settle_cancellation(pg_temp.project('e'));
reset role;
select is((select (computed_editor_earned, editor_earned, editor_extra_pay, editor_paid_before,
    editor_settlement_amount, editor_overpayment, cancelled_payment_count)::text
  from public.cancellation_settlements where id = pg_temp.a('set_e')), '(5500.00,5500.00,1500.00,0.00,4000.00,0.00,2)',
  'the settlement records the extra pay as earned');
select is((select string_agg(coalesce(milestone_seq::text, 'x') || ':' || amount || ':' || status, ','
    order by milestone_seq nulls last, amount)
  from public.payments where assignment_id = pg_temp.a('e') and kind = 'assignment'),
  '1:5000.00:cancelled,2:5000.00:cancelled,x:500.00:pending_approval,x:1000.00:paid,x:4000.00:pending_approval',
  'milestones are cancelled; paid extra pay stays paid, unpaid extra pay stays payable; one settlement row');
select is((select count(*)::int from public.payments where assignment_id = pg_temp.a('e') and kind = 'reversal'), 0,
  'paid extra pay is never reversed as an overpayment');

-- Status checks: a draft/open project or one with nothing confirmed cannot be settled.
select pg_temp.admin();
insert into ids select 'open', public.admin_create_project(jsonb_build_object('title', 'Open', 'brief_type',
  'fully_instructed', 'deadline', '2099-12-31', 'brief', jsonb_build_object('instructions', 'x'),
  'deliverables', jsonb_build_array(jsonb_build_object('name', 'Main'))));
select throws_ok($$ select public.admin_settle_cancellation(pg_temp.a('open')) $$, 'ES409',
  'Only an assigned or started project is settled here.', 'a draft project is not settled');
select lives_ok($$ select public.admin_set_project_status(pg_temp.a('open'), 'cancelled') $$,
  'and is cancelled as before');
reset role;

select * from finish();
rollback;
