-- Phase 12D part 2: extra pay offers (offer, decline, new offer, withdraw, accept), the revision gate
-- (acknowledge, start and submit blocked until the offer is accepted), the accepted offer's own
-- payment row (agreed amount untouched), extra-round client charges with an admin due date
-- (call 5), scope quotes gating a scope change (quote accepted AND extra pay accepted), editor
-- isolation (editor B, table reads) and the guards.
begin;

create extension if not exists pgtap with schema extensions;

select plan(63);

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
  select pg_temp.as_user('d5000000-0000-0000-0000-00000000000a', 'aal2') $$;
create function pg_temp.ed_a() returns void language sql as $$
  select pg_temp.as_user('d5000000-0000-0000-0000-000000000001') $$;
create function pg_temp.ed_b() returns void language sql as $$
  select pg_temp.as_user('d5000000-0000-0000-0000-000000000002') $$;
grant execute on function pg_temp.admin(), pg_temp.ed_a(), pg_temp.ed_b() to authenticated;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('d5000000-0000-0000-0000-00000000000a', 'p12d2-admin@test.local', '{}', '{}'),
  ('d5000000-0000-0000-0000-000000000001', 'p12d2-editor-a@test.local', '{}', '{}'),
  ('d5000000-0000-0000-0000-000000000002', 'p12d2-editor-b@test.local', '{}', '{}');
select private.grant_admin_by_email('p12d2-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('d5000000-0000-0000-0000-000000000001', 'd5000000-0000-0000-0000-000000000002');

create temp table ids (kind text primary key, id uuid not null);
grant select, insert on ids to authenticated;
create function pg_temp.a(p_kind text) returns uuid language sql as $$ select id from ids where kind = p_kind $$;
grant execute on function pg_temp.a(text) to authenticated;

-- A started project: agreed terms (0 included rounds, extra round charge 1500 LKR), client price
-- 20000 with the deposit verified, editor A confirmed for 10000 LKR and working.
create function pg_temp.flow(p_title text) returns uuid language plpgsql as $$
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
  perform public.admin_save_terms_draft(v_project,
    '{"included_rounds": 0, "extra_round_charge": 1500, "charge_currency": "LKR"}');
  perform public.admin_agree_terms(v_project, 1);
  perform public.admin_update_project(v_project, '{"client_price": 20000}');
  perform public.admin_create_client_milestones(v_project, null);
  select id into v_dep from public.client_milestones where project_id = v_project and kind = 'deposit';
  perform public.admin_issue_client_invoice(v_dep);
  perform public.admin_record_client_payment(v_dep, 'TEST-DEP');
  perform public.admin_verify_client_payment(v_dep);
  v_id := public.admin_make_offer(v_project, 'd5000000-0000-0000-0000-000000000001', 10000, 'LKR');
  perform pg_temp.ed_a();
  perform public.editor_respond_offer(v_id, 'accept');
  perform pg_temp.admin();
  perform public.admin_confirm_assignment(v_id);
  perform pg_temp.ed_a();
  perform public.editor_confirm_brief(v_id, 1, '2099-12-31', 10000, 'LKR');
  perform public.editor_start_work(v_id);
  reset role;
  return v_id;
end;
$$;

-- Editor A submits; the admin reviews with an outcome; the new request id is stored as p_kind.
create function pg_temp.cycle(p_kind text, p_outcome text, p_type text) returns void language plpgsql as $$
declare
  v_sub uuid;
begin
  perform pg_temp.ed_a();
  v_sub := public.editor_submit_work(pg_temp.a('x'), 'https://drive.example/' || p_kind);
  perform pg_temp.admin();
  insert into ids values (p_kind, public.admin_review_submission(v_sub, p_outcome, 'Feedback', p_type, 'Reason'));
  reset role;
end;
$$;

insert into ids select 'x', pg_temp.flow('Extras');
insert into ids select 'xp', project_id from public.assignments where id = pg_temp.a('x');
select pg_temp.cycle('r1', 'revision_requested', 'client_revision');
select is((select (round_number, beyond_allowance, adjustment_required)::text from public.revision_requests
  where id = pg_temp.a('r1')), '(1,t,f)', 'with 0 included rounds, round 1 is chargeable; extra pay not yet required');

-- ---------------------------------------------------------------------------
-- Marking the round as needing extra pay; the gate
-- ---------------------------------------------------------------------------
select pg_temp.admin();
select throws_ok($$ select public.admin_offer_adjustment(pg_temp.a('x'), 'extra_round', 2500, pg_temp.a('r1')) $$,
  'ES409', 'Mark this client revision as needing extra pay first.', 'an extra round offer needs the mark');
select throws_ok($$ select public.admin_set_revision_adjustment_required(pg_temp.a('r1'), null) $$, 'ES422', null,
  'the mark needs a yes or no');
select lives_ok($$ select public.admin_set_revision_adjustment_required(pg_temp.a('r1'), true) $$,
  'the admin marks the chargeable round as needing extra pay');
reset role;
select ok((select adjustment_required from public.revision_requests where id = pg_temp.a('r1')), 'the mark is stored');
select ok(exists (select 1 from public.activity_logs where action = 'revision_request.adjustment_required'
  and entity_id = pg_temp.a('r1')::text and details ? 'to' and not details ? 'reason'), 'the mark is audited (no reason)');

select pg_temp.ed_a();
select is(public.editor_revision_gate(pg_temp.a('r1')), 'needs_extra_pay', 'the editor sees the extra pay wait');
select throws_ok($$ select public.editor_acknowledge_revision(pg_temp.a('r1')) $$, 'ES409',
  'This change needs extra pay agreed first. Accept the extra pay offer before you begin.',
  'the editor cannot acknowledge before accepting extra pay');
select throws_ok($$ select public.editor_acknowledge_revision(pg_temp.a('r1'), true) $$, 'ES409', null,
  'nor start it');
select throws_ok($$ select public.editor_submit_work(pg_temp.a('x'), 'https://drive.example/early') $$, 'ES409', null,
  'nor resubmit');
select pg_temp.ed_b();
select throws_ok($$ select public.editor_revision_gate(pg_temp.a('r1')) $$, 'ES422', 'Change request not found.',
  'editor B cannot read the gate of editor A''s request');

-- ---------------------------------------------------------------------------
-- Offer, decline, new offer, withdraw, accept
-- ---------------------------------------------------------------------------
select pg_temp.admin();
select throws_ok($$ select public.admin_offer_adjustment(pg_temp.a('x'), 'extra_round', 0, pg_temp.a('r1')) $$,
  'ES422', null, 'the amount must be above 0');
select throws_ok($$ select public.admin_offer_adjustment(pg_temp.a('x'), 'extra_round', 25.555, pg_temp.a('r1')) $$,
  'ES422', null, 'the amount is in whole cents');
select throws_ok($$ select public.admin_offer_adjustment(pg_temp.a('x'), 'extra_round', 25, null) $$,
  'ES422', null, 'an extra round offer names its request');
select throws_ok($$ select public.admin_offer_adjustment(pg_temp.a('x'), 'cancellation', 25) $$,
  'ES409', 'Extra cancellation pay can be offered only after the cancellation is settled.',
  'a cancellation offer needs a settled cancellation');
insert into ids select 'adj1', public.admin_offer_adjustment(pg_temp.a('x'), 'extra_round', 2500, pg_temp.a('r1'),
  null, 'Second pass on the grade');
select throws_ok($$ select public.admin_offer_adjustment(pg_temp.a('x'), 'extra_round', 2600, pg_temp.a('r1')) $$,
  'ES409', 'There is already an open or accepted extra pay offer for this.', 'one live offer per round');
reset role;
select is((select (kind, amount, currency, status, offered_by is not null)::text from public.compensation_adjustments
  where id = pg_temp.a('adj1')), '(extra_round,2500.00,LKR,offered,t)',
  'the offer holds editor pay in the agreed currency');
select is((select count(*)::int from public.notifications where kind = 'adjustment_offered'
  and recipient_id = 'd5000000-0000-0000-0000-000000000001' and entity_id = pg_temp.a('xp')), 1,
  'editor A is notified of the offer (links to the project)');

select pg_temp.ed_b();
select is((select count(*)::int from public.editor_list_adjustments()), 0, 'editor B lists none of editor A''s offers');
select throws_ok($$ select public.editor_respond_adjustment(pg_temp.a('adj1'), 'accept') $$, 'ES422',
  'Extra pay offer not found.', 'editor B cannot answer it');
select pg_temp.ed_a();
select is((select count(*)::int from public.compensation_adjustments), 0, 'editors read no offer rows directly');
select is((select (amount, currency, status, revision_request_id = pg_temp.a('r1'), note)::text
  from public.editor_list_adjustments(pg_temp.a('xp'))), '(2500.00,LKR,offered,t,"Second pass on the grade")',
  'editor A lists the offer for the project');
select throws_ok($$ select public.editor_respond_adjustment(pg_temp.a('adj1'), 'maybe') $$, 'ES422', null,
  'accept or decline only');
select lives_ok($$ select public.editor_respond_adjustment(pg_temp.a('adj1'), 'decline') $$, 'editor A declines');
select throws_ok($$ select public.editor_respond_adjustment(pg_temp.a('adj1'), 'accept') $$, 'ES409',
  'This offer is no longer open.', 'a declined offer cannot be answered again');
select throws_ok($$ select public.editor_acknowledge_revision(pg_temp.a('r1')) $$, 'ES409', null,
  'still blocked after a decline');
reset role;
select is((select (status, answered_by)::text from public.compensation_adjustments where id = pg_temp.a('adj1')),
  '(declined,d5000000-0000-0000-0000-000000000001)', 'the decline is recorded');
select is((select count(*)::int from public.payments where adjustment_id = pg_temp.a('adj1')), 0,
  'a decline creates no payment');
select is((select count(*)::int from public.notifications where kind = 'adjustment_answered'
  and recipient_id = 'd5000000-0000-0000-0000-00000000000a'), 1, 'the admins are told of the answer');

select pg_temp.admin();
insert into ids select 'adj2', public.admin_offer_adjustment(pg_temp.a('x'), 'extra_round', 3000, pg_temp.a('r1'));
select lives_ok($$ select public.admin_withdraw_adjustment(pg_temp.a('adj2')) $$, 'the admin withdraws a new offer');
select throws_ok($$ select public.admin_withdraw_adjustment(pg_temp.a('adj2')) $$, 'ES409',
  'Only an unanswered offer can be withdrawn.', 'a withdrawn offer cannot be withdrawn again');
insert into ids select 'adj3', public.admin_offer_adjustment(pg_temp.a('x'), 'extra_round', 3000, pg_temp.a('r1'));
select pg_temp.ed_a();
select throws_ok($$ select public.editor_respond_adjustment(pg_temp.a('adj2'), 'accept') $$, 'ES409', null,
  'a withdrawn offer cannot be accepted');
select lives_ok($$ select public.editor_respond_adjustment(pg_temp.a('adj3'), 'accept') $$, 'editor A accepts');
reset role;
select ok((select milestone_seq is null and amount = 3000 and currency = 'LKR' and status = 'pending_approval'
    and payable_reason = 'adjustment_accepted' and due_date = private.business_date(payable_at) + 7
    from public.payments where adjustment_id = pg_temp.a('adj3')),
  'accepting creates its own payable row, due editor pay days later');
select is((select (sum(amount), max(a.agreed_amount))::text from public.payments p
  join public.assignments a on a.id = p.assignment_id
  where p.assignment_id = pg_temp.a('x') and p.milestone_seq is not null), '(10000.00,10000.00)',
  'the agreed amount and the milestones are untouched');
select pg_temp.admin();
select throws_ok($$ select public.admin_withdraw_adjustment(pg_temp.a('adj3')) $$, 'ES409', null,
  'an accepted offer cannot be withdrawn');
select pg_temp.ed_a();
select is(public.editor_revision_gate(pg_temp.a('r1')), 'ok', 'the gate opens once extra pay is accepted');
select lives_ok($$ select public.editor_acknowledge_revision(pg_temp.a('r1')) $$, 'editor A can now acknowledge');
select pg_temp.admin();
select throws_ok($$ select public.admin_classify_revision(pg_temp.a('r1'), 'scope_change', 'Bigger than thought') $$,
  'ES409', 'This change request has already begun, so it cannot become a scope change. Raise a new change request instead.',
  'a begun request cannot be reclassified as a scope change (it would skip the gate)');
select pg_temp.ed_a();
select is((select line_kind from public.editor_list_payments() where amount = 3000), 'extra_round',
  'the earnings list labels the row as extra round pay');
select pg_temp.admin();
select throws_ok($$ select public.admin_set_revision_adjustment_required(pg_temp.a('r1'), true) $$, 'ES409', null,
  'the mark cannot be set after the editor has begun');

-- ---------------------------------------------------------------------------
-- Extra round client charge (call 5: admin due date, no default)
-- ---------------------------------------------------------------------------
select throws_ok($$ select public.admin_charge_extra_round(pg_temp.a('r1'), null) $$, 'ES422',
  'Please enter the client due date.', 'no default due date');
select throws_ok($$ select public.admin_charge_extra_round(pg_temp.a('r1'), '2000-01-01') $$, 'ES422', null,
  'a past due date is refused');
insert into ids select 'cm1', public.admin_charge_extra_round(pg_temp.a('r1'), '2099-01-01');
select throws_ok($$ select public.admin_charge_extra_round(pg_temp.a('r1'), '2099-01-01') $$, 'ES409',
  'This round was already charged.', 'once per round');
reset role;
select is((select (kind, amount, currency, revision_request_id = pg_temp.a('r1'), due_date, invoice_issued_at is not null)::text
  from public.client_milestones where id = pg_temp.a('cm1')), '(extra_work,1500.00,LKR,t,2099-01-01,t)',
  'the charge comes from the terms, invoiced with the admin''s due date');

-- Guards (as the table owner).
select throws_ok($$ insert into public.payments (assignment_id, project_id, editor_id, kind, milestone_seq,
    adjustment_id, amount, currency, payable_reason, payable_at)
  select assignment_id, project_id, editor_id, 'assignment', null, id, 1, currency, 'adjustment_accepted', now()
  from public.compensation_adjustments where id = pg_temp.a('adj3') $$, 'ES409',
  'An extra pay payment must match its accepted offer.', 'extra pay rows never exceed the accepted offer');
select throws_ok($$ update public.compensation_adjustments set amount = 1 where id = pg_temp.a('adj3') $$, 'ES409', null,
  'an answered offer is immutable');
select throws_ok($$ delete from public.compensation_adjustments where id = pg_temp.a('adj1') $$, 'ES409', null,
  'offers are never deleted');

-- ---------------------------------------------------------------------------
-- Scope change: quote accepted AND extra pay accepted
-- ---------------------------------------------------------------------------
select pg_temp.cycle('r2', 'scope_change_required', null);
select pg_temp.ed_a();
select is(public.editor_revision_gate(pg_temp.a('r2')), 'waiting_for_scope_approval',
  'a scope change first waits for the client''s accepted quote');
select pg_temp.admin();
select throws_ok($$ select public.admin_create_scope_quote(pg_temp.a('r1'), 'x', 100, 'LKR') $$, 'ES409',
  'A scope quote is for a scope-change request.', 'quotes are for scope changes only');
select throws_ok($$ select public.admin_create_scope_quote(pg_temp.a('r2'), 'x', 100, 'LK') $$, 'ES422', null,
  'a three-letter currency is required');
insert into ids select 'q1', public.admin_create_scope_quote(pg_temp.a('r2'), 'Add a second ending', 5000, 'lkr');
select throws_ok($$ select public.admin_create_scope_quote(pg_temp.a('r2'), 'Again', 100, 'LKR') $$, 'ES409',
  'This scope change already has a quote.', 'one live quote per scope change');
select throws_ok($$ select public.admin_record_scope_quote_answer(pg_temp.a('q1'), true, '2099-02-01') $$, 'ES409',
  null, 'the client answer is recorded only after the quote is sent');
select throws_ok($$ select public.admin_offer_adjustment(pg_temp.a('x'), 'scope_change', 2000, null, pg_temp.a('q1')) $$,
  'ES409', 'Record the client''s acceptance of the scope quote before offering extra pay.',
  'a scope offer needs the accepted quote (an accepted offer never outlives a declined quote)');
select public.admin_send_scope_quote(pg_temp.a('q1'));
select throws_ok($$ select public.admin_offer_adjustment(pg_temp.a('x'), 'scope_change', 2000, null, pg_temp.a('q1')) $$,
  'ES409', null, 'nor while the quote is only sent');
select throws_ok($$ select public.admin_record_scope_quote_answer(pg_temp.a('q1'), true) $$, 'ES422',
  'Please enter the client due date.', 'acceptance needs the admin''s due date');
insert into ids select 'cm2', public.admin_record_scope_quote_answer(pg_temp.a('q1'), true, '2099-02-01');
reset role;
select is((select (q.status, q.currency, m.kind, m.amount, m.due_date)::text from public.scope_change_quotes q
  join public.client_milestones m on m.scope_quote_id = q.id where q.id = pg_temp.a('q1')),
  '(accepted,LKR,extra_work,5000.00,2099-02-01)', 'acceptance creates the extra_work client milestone');
select throws_ok($$ update public.scope_change_quotes set amount = 1 where id = pg_temp.a('q1') $$, 'ES409', null,
  'a quote''s amount is fixed');
select pg_temp.ed_a();
select is(public.editor_revision_gate(pg_temp.a('r2')), 'needs_extra_pay',
  'with the quote accepted, the scope change waits for the editor''s extra pay');
select throws_ok($$ select public.editor_acknowledge_revision(pg_temp.a('r2')) $$, 'ES409',
  'This change needs extra pay agreed first. Accept the extra pay offer before you begin.',
  'the editor cannot begin yet');
select is((select count(*)::int from public.scope_change_quotes) + (select count(*)::int from public.client_milestones),
  0, 'editors read no quotes and no client milestones');
select pg_temp.admin();
insert into ids select 'adj4', public.admin_offer_adjustment(pg_temp.a('x'), 'scope_change', 2000, null, pg_temp.a('q1'));
select pg_temp.ed_a();
select public.editor_respond_adjustment(pg_temp.a('adj4'), 'accept');
select is((select line_kind from public.editor_list_payments() where amount = 2000), 'scope_change',
  'the scope change pay row is labelled');
select lives_ok($$ select public.editor_acknowledge_revision(pg_temp.a('r2')) $$,
  'the scope change begins once both are accepted');
reset role;

select * from finish();
rollback;
