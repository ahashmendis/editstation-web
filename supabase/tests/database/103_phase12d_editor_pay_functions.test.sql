-- Phase 12D part 1: editor milestones from the terms shares and rounding (call 9), the payable rules
-- in both orders (deposit then confirm, confirm then deposit), due dates in the business timezone,
-- approval moving only the later milestones, late-balance protection with explicit p_now and
-- idempotence, partial-dispute splits (invariant, refusals, release), the refund-aware deposit
-- flag and the editor list (fixed labels, never reasons or client money).
begin;

create extension if not exists pgtap with schema extensions;

select plan(64);

create function pg_temp.as_user(p_uid uuid, p_aal text default 'aal1')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;
grant execute on function pg_temp.as_user(uuid, text) to authenticated;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('d3000000-0000-0000-0000-00000000000a', 'p12d-admin@test.local', '{}', '{}'),
  ('d3000000-0000-0000-0000-000000000001', 'p12d-editor-a@test.local', '{}', '{}'),
  ('d3000000-0000-0000-0000-000000000002', 'p12d-editor-b@test.local', '{}', '{}'),
  ('d3000000-0000-0000-0000-000000000003', 'p12d-applicant@test.local', '{}', '{}');
select private.grant_admin_by_email('p12d-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('d3000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000002');

create temp table ids (kind text primary key, id uuid not null);
grant select, insert on ids to authenticated;
create function pg_temp.a(p_kind text) returns uuid language sql as $$ select id from ids where kind = p_kind $$;
grant execute on function pg_temp.a(text) to authenticated;
create function pg_temp.project(p_kind text) returns uuid language sql as $$
  select project_id from public.assignments where id = (select id from ids where kind = p_kind) $$;
grant execute on function pg_temp.project(text) to authenticated;
-- The milestone row (not a split child) of an assignment.
create function pg_temp.m(p_kind text, p_seq int) returns public.payments language sql as $$
  select * from public.payments where assignment_id = (select id from ids where kind = p_kind)
    and kind = 'assignment' and milestone_seq = p_seq and split_from_payment_id is null
  order by created_at desc limit 1 $$;
grant execute on function pg_temp.m(text, int) to authenticated;
create function pg_temp.cm(p_kind text, p_client_kind text) returns uuid language sql as $$
  select id from public.client_milestones where project_id = pg_temp.project(p_kind)
    and kind = p_client_kind::public.client_milestone_kind and voided_at is null order by seq limit 1 $$;
grant execute on function pg_temp.cm(text, text) to authenticated;

-- A project with agreed terms (p_terms), a 20000 LKR client price split by p_client, the deposit
-- invoiced; an editor confirmed for p_amount. p_deposit_first verifies the deposit before the
-- confirmation; p_start also confirms the brief and starts work (needs the deposit).
create function pg_temp.flow(p_title text, p_editor uuid, p_amount numeric, p_terms jsonb, p_client int[],
  p_deposit_first boolean, p_start boolean default false)
returns uuid language plpgsql as $$
declare
  v_project uuid;
  v_id uuid;
  v_dep uuid;
begin
  perform pg_temp.as_user('d3000000-0000-0000-0000-00000000000a', 'aal2');
  v_project := public.admin_create_project(jsonb_build_object('title', p_title, 'brief_type', 'fully_instructed',
    'deadline', '2099-12-31', 'brief', jsonb_build_object('instructions', 'Cut it'),
    'deliverables', jsonb_build_array(jsonb_build_object('name', 'Main'))));
  perform public.admin_set_project_status(v_project, 'open');
  perform public.admin_save_terms_draft(v_project, p_terms);
  perform public.admin_agree_terms(v_project, 1);
  perform public.admin_update_project(v_project, '{"client_price": 20000}');
  perform public.admin_create_client_milestones(v_project, p_client);
  select id into v_dep from public.client_milestones where project_id = v_project and kind = 'deposit' and voided_at is null;
  perform public.admin_issue_client_invoice(v_dep);
  if p_deposit_first then
    perform public.admin_record_client_payment(v_dep, 'TEST-DEP');
    perform public.admin_verify_client_payment(v_dep);
  end if;
  v_id := public.admin_make_offer(v_project, p_editor, p_amount, 'LKR');
  perform pg_temp.as_user(p_editor);
  perform public.editor_respond_offer(v_id, 'accept');
  perform pg_temp.as_user('d3000000-0000-0000-0000-00000000000a', 'aal2');
  perform public.admin_confirm_assignment(v_id);
  if p_start then
    perform pg_temp.as_user(p_editor);
    perform public.editor_confirm_brief(v_id, 1, '2099-12-31', p_amount, 'LKR');
    perform public.editor_start_work(v_id);
  end if;
  reset role;
  return v_id;
end;
$$;

-- Submit as the editor and approve as the admin.
create function pg_temp.approve(p_kind text, p_editor uuid) returns void language plpgsql as $$
declare
  v_sub uuid;
begin
  perform pg_temp.as_user(p_editor);
  v_sub := public.editor_submit_work(pg_temp.a(p_kind), 'https://drive.example/' || p_kind);
  perform pg_temp.as_user('d3000000-0000-0000-0000-00000000000a', 'aal2');
  perform public.admin_review_submission(v_sub, 'approved');
  reset role;
end;
$$;

-- ---------------------------------------------------------------------------
-- Milestone creation and rounding (call 9); confirm, then deposit
-- ---------------------------------------------------------------------------
insert into ids select 'r', pg_temp.flow('Rounding', 'd3000000-0000-0000-0000-000000000001', 100.01,
  '{"editor_milestone_shares": [33, 33, 34], "editor_pay_days": 5}', '{50,50}', false);
select is((select string_agg(milestone_seq || ':' || amount || ':' || status, ',' order by milestone_seq)
  from public.payments where assignment_id = pg_temp.a('r')), '1:33.00:not_due,2:33.00:not_due,3:34.01:not_due',
  'confirmation creates one not_due row per terms share; the last takes the rounding remainder');
select is((select sum(amount) from public.payments where assignment_id = pg_temp.a('r')), 100.01::numeric,
  'the milestones add up to the agreed amount');
select is((select string_agg(waiting_on_client::text, ',' order by milestone_seq) from public.payments
  where assignment_id = pg_temp.a('r')), 'true,false,false',
  'only milestone 1 waits for the client (deposit unverified); later ones wait for approval, not the client');
select ok((select bool_and(payable_reason is null and payable_at is null and due_date is null)
  from public.payments where assignment_id = pg_temp.a('r')), 'nothing is payable yet');

select pg_temp.as_user('d3000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_set_payment_status((pg_temp.m('r', 1)).id, 'pending_approval') $$, 'ES409',
  null, 'an admin cannot make a not_due milestone payable by hand');
select public.admin_record_client_payment(pg_temp.cm('r', 'deposit'), 'TEST-DEP');
reset role;
select is((pg_temp.m('r', 1)).status::text, 'not_due', 'a recorded but unverified deposit changes nothing');
select pg_temp.as_user('d3000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_verify_client_payment(pg_temp.cm('r', 'deposit'));
reset role;
select ok((select status = 'pending_approval' and payable_reason = 'client_deposit_verified' and payable_at is not null
    and due_date = private.business_date(payable_at) + 5 and not waiting_on_client from pg_temp.m('r', 1)),
  'verifying the deposit makes milestone 1 payable, due editor_pay_days after (business timezone)');
select is((select string_agg(status::text, ',' order by milestone_seq) from public.payments
  where assignment_id = pg_temp.a('r') and milestone_seq > 1), 'not_due,not_due', 'later milestones stay not_due');

-- ---------------------------------------------------------------------------
-- Deposit, then confirm; default 50/50 and default 7 pay days
-- ---------------------------------------------------------------------------
insert into ids select 'p', pg_temp.flow('Approval', 'd3000000-0000-0000-0000-000000000001', 10000,
  '{}', '{50,50}', true, true);
select is((select string_agg(milestone_seq || ':' || amount || ':' || status, ',' order by milestone_seq)
  from public.payments where assignment_id = pg_temp.a('p')), '1:5000.00:pending_approval,2:5000.00:not_due',
  'default 50/50; with the deposit already verified, confirmation makes milestone 1 payable');
select ok((select payable_reason = 'client_deposit_verified' and due_date = private.business_date(payable_at) + 7
  from pg_temp.m('p', 1)), 'default editor_pay_days is 7');

-- ---------------------------------------------------------------------------
-- Approval moves only the later milestone, and only once the client balance is verified
-- ---------------------------------------------------------------------------
select pg_temp.approve('p', 'd3000000-0000-0000-0000-000000000001');
select ok((select status = 'not_due' and waiting_on_client and payable_reason is null from pg_temp.m('p', 2)),
  'approved with the balance unverified: milestone 2 waits for the client');
select pg_temp.as_user('d3000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_issue_client_invoice(pg_temp.cm('p', 'balance'));
select public.admin_record_client_payment(pg_temp.cm('p', 'balance'), 'TEST-BAL');
select public.admin_verify_client_payment(pg_temp.cm('p', 'balance'));
reset role;
select ok((select status = 'pending_approval' and payable_reason = 'client_balance_verified' and not waiting_on_client
  from pg_temp.m('p', 2)), 'verifying the balance makes milestone 2 payable');
select is((select count(*)::int from public.activity_logs where action = 'payment.pending_approval'
  and details ->> 'assignment_id' = pg_temp.a('p')::text), 2, 'each milestone audited once as payable');

-- Balance verified before approval (100% upfront): approval makes milestone 2 payable at once.
insert into ids select 'u', pg_temp.flow('Upfront', 'd3000000-0000-0000-0000-000000000001', 10000,
  '{}', '{100}', true, true);
select is((pg_temp.m('u', 2)).status::text, 'not_due', 'before approval milestone 2 is not due');
select ok((select not waiting_on_client from pg_temp.m('u', 2)), 'and not waiting for the client');
select pg_temp.approve('u', 'd3000000-0000-0000-0000-000000000001');
select ok((select status = 'pending_approval' and payable_reason = 'client_balance_verified' from pg_temp.m('u', 2)),
  'approval with all client money in makes milestone 2 payable');

-- ---------------------------------------------------------------------------
-- Due dates in the business timezone (explicit p_now; the client trigger is bypassed for setup)
-- ---------------------------------------------------------------------------
insert into ids select 'tz1', pg_temp.flow('TZ Colombo', 'd3000000-0000-0000-0000-000000000001', 10000, '{}', '{100}', false);
insert into ids select 'tz2', pg_temp.flow('TZ UTC', 'd3000000-0000-0000-0000-000000000001', 10000, '{}', '{100}', false);
set local session_replication_role = replica;
update public.client_milestones set verification_status = 'verified', received_at = now(), transfer_reference = 'T',
  verified_at = now()
where project_id in (pg_temp.project('tz1'), pg_temp.project('tz2')) and kind = 'deposit';
set local session_replication_role = origin;
select is(private.sync_editor_milestones(pg_temp.project('tz1'), '2026-11-15 20:00:00+00'), 1,
  'the sync makes one milestone payable');
select is((pg_temp.m('tz1', 1)).due_date, '2026-11-23'::date,
  'Asia/Colombo: 20:00 UTC is already the 16th, so due on the 23rd');
update public.app_settings set value = to_jsonb('UTC'::text) where key = 'business_timezone';
select private.sync_editor_milestones(pg_temp.project('tz2'), '2026-11-15 20:00:00+00');
select is((pg_temp.m('tz2', 1)).due_date, '2026-11-22'::date, 'UTC: still the 15th, so due on the 22nd');
select is((pg_temp.m('tz2', 1)).payable_at, '2026-11-15 20:00:00+00'::timestamptz, 'payable_at is p_now');
update public.app_settings set value = to_jsonb('Asia/Colombo'::text) where key = 'business_timezone';
select is(private.sync_editor_milestones(pg_temp.project('tz2'), now()), 0, 'the sync is idempotent');

-- ---------------------------------------------------------------------------
-- Late-balance protection (KB9a-1) with explicit p_now
-- ---------------------------------------------------------------------------
insert into ids select 'l', pg_temp.flow('Late balance', 'd3000000-0000-0000-0000-000000000001', 10000,
  '{"late_balance_days": 14, "editor_pay_days": 3}', '{50,50}', true, true);
select pg_temp.approve('l', 'd3000000-0000-0000-0000-000000000001');
select private.apply_timed_rules(now() + interval '60 days');
select is((pg_temp.m('l', 2)).status::text, 'not_due', 'no protection while the balance invoice is not issued');
select pg_temp.as_user('d3000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_issue_client_invoice(pg_temp.cm('l', 'balance'));
reset role;
-- Balance due = business today + 7; protection from due + 14 days, i.e. day 22.
select private.apply_timed_rules(now() + interval '21 days');
select is((pg_temp.m('l', 2)).status::text, 'not_due', 'not yet on the last day of the waiting period');
select ok(private.apply_timed_rules(now() + interval '22 days') >= 1, 'the rule acts the day after');
select ok((select status = 'pending_approval' and payable_reason = 'late_balance_protection'
    and payable_at = now() + interval '22 days' and due_date = private.business_date(now()) + 22 + 3
  from pg_temp.m('l', 2)), 'milestone 2 is payable by late-balance protection, due editor_pay_days later');
select is((select count(*)::int from public.activity_logs where action = 'payment.late_balance_payable'
  and entity_id = (pg_temp.m('l', 2)).id::text), 1, 'one audit row');
select is((select array_agg(k order by k) from public.activity_logs, jsonb_object_keys(details) k
  where action = 'payment.late_balance_payable' and entity_id = (pg_temp.m('l', 2)).id::text),
  array['assignment_id', 'payment_id', 'project_id', 'reason'], 'the audit row holds ids and the enum reason only');
select is((select count(*)::int from public.notifications where kind = 'late_balance_payable'
  and entity_id = (pg_temp.m('l', 2)).id and recipient_id = 'd3000000-0000-0000-0000-00000000000a'), 1,
  'the admin is notified once');
select private.apply_timed_rules(now() + interval '40 days');
select is((select count(*)::int from public.activity_logs where action = 'payment.late_balance_payable'
  and entity_id = (pg_temp.m('l', 2)).id::text), 1, 'a second run does nothing again (idempotent)');
select is((select count(*)::int from public.notifications where kind = 'late_balance_payable'
  and entity_id = (pg_temp.m('l', 2)).id), 1, 'and notifies no one again');

-- Unapproved project: no protection.
insert into ids select 'nl', pg_temp.flow('Not approved', 'd3000000-0000-0000-0000-000000000001', 10000,
  '{}', '{50,50}', true, true);
select pg_temp.as_user('d3000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_issue_client_invoice(pg_temp.cm('nl', 'balance'));
reset role;
select private.apply_timed_rules(now() + interval '90 days');
select is((pg_temp.m('nl', 2)).status::text, 'not_due', 'no protection before the project is approved');

-- Any hold on the assignment (not only a dispute part) pauses protection (conservative).
insert into ids select 'h', pg_temp.flow('Held', 'd3000000-0000-0000-0000-000000000001', 10000,
  '{}', '{50,50}', true, true);
select pg_temp.approve('h', 'd3000000-0000-0000-0000-000000000001');
select pg_temp.as_user('d3000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_issue_client_invoice(pg_temp.cm('h', 'balance'));
select public.admin_set_payment_status((pg_temp.m('h', 1)).id, 'on_hold', 'Bank check');
reset role;
select private.apply_timed_rules(now() + interval '60 days');
select is((pg_temp.m('h', 2)).status::text, 'not_due', 'a held milestone 1 pauses protection for milestone 2');
select pg_temp.as_user('d3000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_release_payment_hold((pg_temp.m('h', 1)).id);
reset role;
select private.apply_timed_rules(now() + interval '60 days');
select is((pg_temp.m('h', 2)).payable_reason::text, 'late_balance_protection', 'after release protection applies');

-- ---------------------------------------------------------------------------
-- Partial dispute split (KB9a-4) and protection skipped while the dispute is open
-- ---------------------------------------------------------------------------
insert into ids select 'd', pg_temp.flow('Dispute', 'd3000000-0000-0000-0000-000000000001', 10000,
  '{}', '{50,50}', true, true);
select pg_temp.approve('d', 'd3000000-0000-0000-0000-000000000001');
select pg_temp.as_user('d3000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_issue_client_invoice(pg_temp.cm('d', 'balance'));
select throws_ok($$ select public.admin_split_payment_for_dispute((pg_temp.m('d', 2)).id, 5000, 'Too much') $$,
  'ES422', null, 'the disputed part must be less than the payment');
select throws_ok($$ select public.admin_split_payment_for_dispute((pg_temp.m('d', 2)).id, 0, 'Zero') $$,
  'ES422', null, 'the disputed part must be more than 0');
select throws_ok($$ select public.admin_split_payment_for_dispute((pg_temp.m('d', 2)).id, 10.005, 'Cents') $$,
  'ES422', null, 'the disputed part is in whole cents');
select throws_ok($$ select public.admin_split_payment_for_dispute((pg_temp.m('d', 2)).id, 100, '   ') $$,
  'ES422', null, 'a reason is required');
insert into ids select 'dc', public.admin_split_payment_for_dispute((pg_temp.m('d', 2)).id, 1500.50,
  'Client disputes the colour grade ZQX');
reset role;
select ok((select amount = 3499.50 and amount_before_split = 5000 and status = 'not_due' from pg_temp.m('d', 2)),
  'the undisputed row keeps the rest and its status');
select ok((select amount = 1500.50 and status = 'on_hold' and held_from_status = 'not_due'
    and split_from_payment_id = (pg_temp.m('d', 2)).id and milestone_seq = 2
    and on_hold_reason = 'Client disputes the colour grade ZQX'
  from public.payments where id = pg_temp.a('dc')), 'the disputed child is on hold with the reason');
select is((select sum(amount) from public.payments where assignment_id = pg_temp.a('d') and milestone_seq = 2),
  5000::numeric, 'the parts add up to the original');
select ok((select details ? 'child_payment_id' and details::text not like '%ZQX%' and details::text not like '%1500%'
  from public.activity_logs where action = 'payment.dispute_split' and entity_id = (pg_temp.m('d', 2)).id::text),
  'the split audit row holds ids and field names only');
select pg_temp.as_user('d3000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_split_payment_for_dispute((pg_temp.m('d', 2)).id, 100, 'Again') $$,
  'ES409', null, 'a milestone is split once');
select throws_ok($$ select public.admin_split_payment_for_dispute(pg_temp.a('dc'), 100, 'Child') $$,
  'ES409', null, 'the held child cannot be split');
reset role;
select private.apply_timed_rules(now() + interval '60 days');
select is((pg_temp.m('d', 2)).status::text, 'not_due', 'late-balance protection skips an assignment with an open dispute');

-- Direct writes cannot break the invariant (table owner, constraint checked per statement).
select throws_ok($$ update public.payments set amount = 1 where id = (pg_temp.m('d', 2)).id $$,
  'ES409', null, 'the amount cannot be changed directly');
select set_config('es.payment_split', (pg_temp.m('d', 1)).id::text, true);
select throws_ok($$ update public.payments set amount = 1000, amount_before_split = 5000 where id = (pg_temp.m('d', 1)).id $$,
  'ES409', 'The parts of a split payment must add up to the original.', 'a split without its child is refused');
select set_config('es.payment_split', '', true);

-- Release returns the child to its prior state; then protection applies to both parts.
select pg_temp.as_user('d3000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_release_payment_hold(pg_temp.a('dc'));
reset role;
select ok((select status = 'not_due' and held_from_status is null and on_hold_reason is null and waiting_on_client
  from public.payments where id = pg_temp.a('dc')), 'release returns the child to not_due (waiting for the client)');
select private.apply_timed_rules(now() + interval '60 days');
select is((select string_agg(status::text || ':' || payable_reason::text, ',' order by amount)
  from public.payments where assignment_id = pg_temp.a('d') and milestone_seq = 2),
  'pending_approval:late_balance_protection,pending_approval:late_balance_protection',
  'with the dispute resolved both parts become payable');

-- A payable milestone splits with its approval facts; release returns to that status.
select pg_temp.as_user('d3000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_set_payment_status((pg_temp.m('d', 1)).id, 'approved');
insert into ids select 'dc1', public.admin_split_payment_for_dispute((pg_temp.m('d', 1)).id, 1000, 'Partial');
select public.admin_release_payment_hold(pg_temp.a('dc1'));
reset role;
select ok((select status = 'approved' and approved_at is not null and payable_reason = 'client_deposit_verified'
  from public.payments where id = pg_temp.a('dc1')), 'an approved milestone''s child returns to approved');
select pg_temp.as_user('d3000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_mark_payment_paid((pg_temp.m('d', 1)).id, 'REF-1', (now() at time zone 'Asia/Colombo')::date);
select throws_ok($$ select public.admin_split_payment_for_dispute((pg_temp.m('d', 1)).id, 10, 'Paid') $$,
  'ES409', null, 'a paid row cannot be split');
select public.admin_reverse_payment((pg_temp.m('d', 1)).id, 'Reversal reason RVZ', false);
reset role;
select ok(pg_get_functiondef('public.admin_reverse_payment(uuid, text, boolean)'::regprocedure)
  ~ 'public\.projects where id = v_project_id for update.*public\.assignments where id = v_assignment_id for update.*lock_payment',
  'admin_reverse_payment locks project, then assignment, then payment');

-- ---------------------------------------------------------------------------
-- The deposit flag nets refund rows (§4.2 note)
-- ---------------------------------------------------------------------------
select ok(private.client_deposit_verified(pg_temp.project('p')), 'a verified deposit counts');
insert into public.client_milestones (project_id, terms_id, seq, kind, amount, currency, reverses_id)
select m.project_id, m.terms_id, 50, 'refund', -4000, m.currency, m.id
from public.client_milestones m where m.id = pg_temp.cm('p', 'deposit');
select ok(private.client_deposit_verified(pg_temp.project('p')), 'a partial refund leaves it counted');
insert into public.client_milestones (project_id, terms_id, seq, kind, amount, currency, reverses_id)
select m.project_id, m.terms_id, 51, 'refund', -6000, m.currency, m.id
from public.client_milestones m where m.id = pg_temp.cm('p', 'deposit');
select ok(not private.client_deposit_verified(pg_temp.project('p')), 'a deposit refunded to 0 no longer counts');
select ok(not private.client_balance_verified(pg_temp.project('p')), 'nor does the client balance');

-- ---------------------------------------------------------------------------
-- editor_list_payments: fixed labels, no reasons, no client money
-- ---------------------------------------------------------------------------
insert into ids select 'w', pg_temp.flow('Waiting', 'd3000000-0000-0000-0000-000000000001', 10000, '{}', '{50,50}', false);
select pg_temp.as_user('d3000000-0000-0000-0000-00000000000a', 'aal2');
insert into ids select 'nlc', public.admin_split_payment_for_dispute((pg_temp.m('nl', 1)).id, 100, 'Hold QQ');
select pg_temp.as_user('d3000000-0000-0000-0000-000000000001');
create temp table a_list as select * from public.editor_list_payments();
reset role;
select is((select hold_label::text from a_list where id = (pg_temp.m('r', 2)).id), null,
  'waiting for approval has no label');
select is((select hold_label::text from a_list where id = (pg_temp.m('w', 1)).id), 'waiting_for_client_payment',
  'waiting for the client deposit shows the fixed label');
select is((select hold_label::text from a_list where id = pg_temp.a('nlc')), 'under_review',
  'a held dispute part shows Under review, not the reason');
select ok((select count(*) = 3 and bool_and(milestone_seq between 1 and 3) from a_list
  where project_id = pg_temp.project('r')), 'the editor sees each milestone');
select ok(not exists (select 1 from a_list a
                      where (to_jsonb(a) - 'waiting_on_client' - 'hold_label')::text ~ '(ZQX|colour grade|Partial|Hold QQ|RVZ|Bank check|late_balance|client_)'),
  'no hold reason, payable reason or client fact reaches the editor');
select ok(not exists (select 1 from a_list where amount = 20000), 'no client price appears');
select ok(exists (select 1 from a_list where kind = 'reversal' and status = 'paid'), 'the editor sees the reversal row');
select ok(not exists (select 1 from information_schema.routines r
  join information_schema.parameters x on x.specific_name = r.specific_name
  where r.routine_schema = 'public' and r.routine_name = 'editor_list_payments' and x.parameter_name like '%reason%'),
  'the editor list has no reason column at all');
select pg_temp.as_user('d3000000-0000-0000-0000-000000000002');
select is((select count(*)::int from public.editor_list_payments()), 0, 'editor B lists none of editor A''s payments');
reset role;

select * from finish();
rollback;
