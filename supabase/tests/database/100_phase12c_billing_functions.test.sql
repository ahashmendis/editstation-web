-- Phase 12C: client milestone functions (create from agreed terms and client price, per-project
-- split, replacement before invoicing, invoice/due dates, record, verify, correction), the deposit
-- start gate (editor sees a status only), the unpaid-deposit auto-hold with explicit p_now (fires
-- once, releases to assigned, extension), the manual assigned -> on_hold refusal, race checks and
-- the business timezone setting.
begin;

create extension if not exists pgtap with schema extensions;

select plan(71);

create function pg_temp.as_user(p_uid uuid, p_aal text default 'aal1')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;
grant execute on function pg_temp.as_user(uuid, text) to authenticated;

create function pg_temp.state_as(p_uid uuid, p_aal text, p_sql text)
returns text language plpgsql as $$
declare
  v text;
begin
  begin
    perform pg_temp.as_user(p_uid, p_aal);
    execute p_sql;
    raise exception 'rollback' using errcode = 'EST00';
  exception when others then
    v := case when sqlstate = 'EST00' then 'ok' else sqlstate end;
  end;
  reset role;
  return v;
end;
$$;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('a0000000-0000-0000-0000-00000000000a', 'p12cf-admin@test.local', '{}', '{}'),
  ('a0000000-0000-0000-0000-000000000001', 'p12cf-editor-a@test.local', '{}', '{}'),
  ('a0000000-0000-0000-0000-000000000002', 'p12cf-editor-b@test.local', '{}', '{}');
select private.grant_admin_by_email('p12cf-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('a0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002');

create temp table ids (kind text primary key, id uuid not null);
-- Today in the business timezone, computed once by the owner (API roles cannot call private helpers).
create temp table biz_today as select private.business_date(now()) as d;
grant select on biz_today to authenticated;
create function pg_temp.today() returns date language sql as $q$ select d from biz_today $q$;
grant execute on function pg_temp.today() to authenticated;
grant select, insert on ids to authenticated;
create function pg_temp.a(p_kind text) returns uuid language sql as $$ select id from ids where kind = p_kind $$;
grant execute on function pg_temp.a(text) to authenticated;
create function pg_temp.project(p_kind text) returns uuid language sql as $$
  select project_id from public.assignments where id = (select id from ids where kind = p_kind) $$;
grant execute on function pg_temp.project(text) to authenticated;
create function pg_temp.ms(p_kind text, p_ms public.client_milestone_kind) returns public.client_milestones
language sql as $$
  select * from public.client_milestones where project_id = pg_temp.project(p_kind) and kind = p_ms and voided_at is null
  order by seq limit 1 $$;
grant execute on function pg_temp.ms(text, public.client_milestone_kind) to authenticated;
create function pg_temp.pstatus(p_kind text) returns text language sql as $$
  select status::text || '/' || coalesce(status_before_hold::text, '-') from public.projects where id = pg_temp.project(p_kind) $$;

-- Confirmed assignment with the brief confirmed; optional client price and agreed terms.
create function pg_temp.flow(p_title text, p_editor uuid, p_price numeric)
returns uuid language plpgsql as $$
declare
  v_project uuid;
  v_id uuid;
begin
  perform pg_temp.as_user('a0000000-0000-0000-0000-00000000000a', 'aal2');
  v_project := public.admin_create_project(jsonb_build_object('title', p_title, 'brief_type', 'fully_instructed',
    'deadline', '2099-12-31', 'client_price', p_price, 'brief', jsonb_build_object('instructions', 'Cut it'),
    'deliverables', jsonb_build_array(jsonb_build_object('name', 'Main'))));
  perform public.admin_set_project_status(v_project, 'open');
  perform public.admin_agree_terms(v_project, 1);
  v_id := public.admin_make_offer(v_project, p_editor, 10000, 'LKR');
  perform pg_temp.as_user(p_editor);
  perform public.editor_respond_offer(v_id, 'accept');
  perform pg_temp.as_user('a0000000-0000-0000-0000-00000000000a', 'aal2');
  perform public.admin_confirm_assignment(v_id);
  perform pg_temp.as_user(p_editor);
  perform public.editor_confirm_brief(v_id, 1, '2099-12-31', 10000, 'LKR');
  reset role;
  return v_id;
end;
$$;

insert into ids select 'p', pg_temp.flow('Billing P', 'a0000000-0000-0000-0000-000000000001', 10000.01);
insert into ids select 'r', pg_temp.flow('Billing R', 'a0000000-0000-0000-0000-000000000002', 8000);
insert into ids select 't', pg_temp.flow('Billing T', 'a0000000-0000-0000-0000-000000000002', 8000);
insert into ids select 'n', pg_temp.flow('Billing N', 'a0000000-0000-0000-0000-000000000001', null);
select pg_temp.as_user('a0000000-0000-0000-0000-00000000000a', 'aal2');
insert into ids select 'q', public.admin_create_project('{"title": "No terms", "brief_type": "creative_led",
  "client_price": 500}');
insert into ids select 's', public.admin_create_project('{"title": "Open only", "brief_type": "creative_led",
  "client_price": 500}');
select public.admin_agree_terms(pg_temp.a('s'), 1);
reset role;
update public.projects set status = 'open', first_opened_at = now() where id = pg_temp.a('s');
insert into public.assignments (project_id, editor_id, status, proposed_amount, agreed_amount, agreed_currency,
  confirmed_at) values (pg_temp.a('s'), 'a0000000-0000-0000-0000-000000000001', 'confirmed', 100, 100, 'LKR', now());

-- ---------------------------------------------------------------------------
-- admin_create_client_milestones
-- ---------------------------------------------------------------------------
select is(pg_temp.state_as('a0000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_create_client_milestones(pg_temp.a('q')) $$), 'ES409', 'no milestones without agreed terms');
select is(pg_temp.state_as('a0000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_create_client_milestones(pg_temp.project('n')) $$), 'ES409',
  'no milestones without a client price (no invented amounts)');
select is(pg_temp.state_as('a0000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_create_client_milestones(pg_temp.project('p'), '{60,30}') $$), 'ES422',
  'shares must add up to 100');
select is(pg_temp.state_as('a0000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_create_client_milestones(pg_temp.project('p'), '{0,100}') $$), 'ES422', 'a zero share is refused');

select pg_temp.as_user('a0000000-0000-0000-0000-00000000000a', 'aal2');
select is(public.admin_create_client_milestones(pg_temp.project('p'), '{30,70}'), 2, 'a 30/70 split creates two rows');
select is(public.admin_create_client_milestones(pg_temp.project('p')), 2,
  'before invoicing the admin replaces them with the default 50/50');
reset role;
select ok((pg_temp.ms('p', 'deposit')).amount = 5000.01 and (pg_temp.ms('p', 'balance')).amount = 5000.00
  and (pg_temp.ms('p', 'deposit')).share_percent = 50 and (pg_temp.ms('p', 'deposit')).seq = 3
  and (pg_temp.ms('p', 'balance')).currency = 'LKR',
  '50/50 of 10000.01: the deposit is rounded and the last milestone takes the remainder');
select is((select count(*)::int from public.client_milestones where project_id = pg_temp.project('p') and voided_at is not null),
  2, 'the replaced rows are kept as voided');
select ok((select bool_and(details - 'project_id' - 'terms_id' - 'milestone_ids' - 'voided_ids' - 'fields' = '{}'::jsonb)
  from public.activity_logs where action = 'client_milestones.created' and entity_id = pg_temp.project('p')::text)
  and (select count(*) = 2 from public.activity_logs where action = 'client_milestones.created'
       and entity_id = pg_temp.project('p')::text),
  'each creation is audited with ids and field names only');
select pg_temp.as_user('a0000000-0000-0000-0000-00000000000a', 'aal2');
select is(public.admin_create_client_milestones(pg_temp.project('r'), '{100}'), 1, '100% upfront is one deposit row');
select public.admin_create_client_milestones(pg_temp.project('t'));
select public.admin_create_client_milestones(pg_temp.a('s'));
reset role;
select ok((pg_temp.ms('r', 'deposit')).amount = 8000 and (pg_temp.ms('r', 'deposit')).share_percent = 100
  and (pg_temp.ms('r', 'balance')).id is null, 'the upfront deposit is the whole client price');
select ok((select details -> 'fields' = '["shares"]' from public.activity_logs where action = 'client_milestones.created'
  and entity_id = pg_temp.project('r')::text), 'a non-default split is recorded in the audit');

-- ---------------------------------------------------------------------------
-- admin_issue_client_invoice
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a0000000-0000-0000-0000-00000000000a', 'aal2');
select is(public.admin_issue_client_invoice((pg_temp.ms('p', 'deposit')).id), pg_temp.today() + 14,
  'the deposit is due deposit_days (14) after the invoice, in business calendar days');
select is(public.admin_issue_client_invoice((pg_temp.ms('p', 'balance')).id), pg_temp.today() + 7,
  'the balance is due balance_days (7) after its invoice');
select throws_ok($$ select public.admin_issue_client_invoice((pg_temp.ms('p', 'deposit')).id) $$, 'ES409', null,
  'an invoice is issued once');
select throws_ok($$ select public.admin_create_client_milestones(pg_temp.project('p')) $$, 'ES409', null,
  'after an invoice the milestones cannot be replaced');
select public.admin_issue_client_invoice((pg_temp.ms('r', 'deposit')).id);
select public.admin_issue_client_invoice((pg_temp.ms('t', 'deposit')).id);
select public.admin_issue_client_invoice((select id from public.client_milestones where project_id = pg_temp.a('s') and kind = 'deposit'));
reset role;

-- ---------------------------------------------------------------------------
-- The deposit gate: the editor sees a status only
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a0000000-0000-0000-0000-000000000001');
select ok((select not client_deposit_verified and not ready and brief_confirmed
  from public.get_assignment_gate(pg_temp.a('p'))), 'editor A sees the deposit is not verified, so not ready');
select throws_ok($$ select public.editor_start_work(pg_temp.a('p')) $$, 'ES409',
  'Waiting for the client deposit. Work can start once it is confirmed.',
  'the editor cannot start before the deposit is verified, and sees only a status');
reset role;
select is(pg_temp.state_as('a0000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_start_work(pg_temp.a('p')) $$), 'ES409', 'nor can the admin start it');
select throws_ok(format($$ update public.assignments set status = 'in_progress', started_at = now() where id = %L $$,
  pg_temp.a('p')), 'ES409', null, 'the guard trigger refuses a direct start without a verified deposit');
select ok(not exists (select 1 from unnest((select proargnames from pg_proc
  where oid = 'public.get_assignment_gate(uuid)'::regprocedure)) n where n ~ 'price|milestone|balance|transfer|due|client_amount')
  and not exists (select 1 from pg_proc f join pg_namespace s on s.oid = f.pronamespace
    where s.nspname = 'public' and f.prosrc ~ 'client_milestones' and f.prosrc !~ 'private\.require_admin\(\)'),
  'editors cannot infer client money: the gate returns a yes/no flag, and every public function reading milestones is admin-only');

-- ---------------------------------------------------------------------------
-- Record and verify
-- ---------------------------------------------------------------------------
select is(pg_temp.state_as('a0000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_record_client_payment((pg_temp.ms('p', 'deposit')).id, '   ') $$), 'ES422',
  'a transfer reference is required');
select is(pg_temp.state_as('a0000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_record_client_payment((pg_temp.ms('p', 'deposit')).id, 'BANK-1', pg_temp.today() + 1) $$),
  'ES422', 'a transfer date in the future is refused');
select is(pg_temp.state_as('a0000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_verify_client_payment((pg_temp.ms('p', 'deposit')).id) $$), 'ES409',
  'a payment is verified only after it is recorded');
select pg_temp.as_user('a0000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok($$ select public.admin_record_client_payment((pg_temp.ms('p', 'deposit')).id, 'BANK-0') $$,
  'the admin records the transfer');
select lives_ok($$ select public.admin_record_client_payment((pg_temp.ms('p', 'deposit')).id, 'BANK-1',
  pg_temp.today() - 2) $$, 'and may correct it while unverified');
reset role;
select ok((pg_temp.ms('p', 'deposit')).verification_status = 'received_unverified'
  and (pg_temp.ms('p', 'deposit')).transfer_reference = 'BANK-1'
  and private.business_date((pg_temp.ms('p', 'deposit')).received_at) = pg_temp.today() - 2,
  'the row is received, unverified, with the reference and business-calendar date');
select pg_temp.as_user('a0000000-0000-0000-0000-000000000001');
select ok((select not client_deposit_verified and not ready from public.get_assignment_gate(pg_temp.a('p'))),
  'a recorded but unverified deposit does not open the gate');
reset role;
select pg_temp.as_user('a0000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok($$ select public.admin_verify_client_payment((pg_temp.ms('p', 'deposit')).id) $$, 'the admin verifies it');
select throws_ok($$ select public.admin_verify_client_payment((pg_temp.ms('p', 'deposit')).id) $$, 'ES409', null,
  'a second admin verifying the same transfer is refused');
select throws_ok($$ select public.admin_record_client_payment((pg_temp.ms('p', 'deposit')).id, 'X') $$, 'ES409', null,
  'a verified payment cannot be re-recorded');
reset role;
select ok((pg_temp.ms('p', 'deposit')).verified_by = 'a0000000-0000-0000-0000-00000000000a'
  and (pg_temp.ms('p', 'deposit')).verified_at is not null, 'the verifier and time are recorded');
select ok((select bool_and(details::text !~ 'BANK') from public.activity_logs
  where action like 'client_milestone.%' and entity_id = pg_temp.project('p')::text)
  and exists (select 1 from public.activity_logs where action = 'client_milestone.verified'
              and details ->> 'milestone_id' = (pg_temp.ms('p', 'deposit')).id::text),
  'record and verify are audited without references');

select pg_temp.as_user('a0000000-0000-0000-0000-000000000001');
select ok((select client_deposit_verified and ready from public.get_assignment_gate(pg_temp.a('p'))),
  'with the deposit verified the gate is ready');
select lives_ok($$ select public.editor_start_work(pg_temp.a('p')) $$, 'editor A starts work');
reset role;

-- ---------------------------------------------------------------------------
-- Correction (audited) of a verified payment
-- ---------------------------------------------------------------------------
select is(pg_temp.state_as('a0000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_correct_client_payment((pg_temp.ms('p', 'deposit')).id, 'Wrong account') $$), 'ES409',
  'a deposit verification cannot be corrected once work has begun');
select pg_temp.as_user('a0000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_record_client_payment((pg_temp.ms('p', 'balance')).id, 'BANK-2');
select public.admin_verify_client_payment((pg_temp.ms('p', 'balance')).id);
select throws_ok($$ select public.admin_correct_client_payment((pg_temp.ms('p', 'balance')).id, '  ') $$, 'ES422', null,
  'a correction needs a reason');
select lives_ok($$ select public.admin_correct_client_payment((pg_temp.ms('p', 'balance')).id, 'Bounced transfer') $$,
  'a mistaken balance verification is corrected');
reset role;
select ok((pg_temp.ms('p', 'balance')).verification_status = 'received_unverified'
  and (pg_temp.ms('p', 'balance')).verified_at is null
  and (pg_temp.ms('p', 'balance')).correction_reason = 'Bounced transfer'
  and exists (select 1 from public.activity_logs where action = 'client_milestone.verification_corrected'
              and details::text !~ 'Bounced'),
  'the correction is stored and audited without the reason text');

-- ---------------------------------------------------------------------------
-- Timed rules: unpaid-deposit auto-hold (explicit p_now; R and T are assigned, deposits due in 14
-- days; S is open with no confirmed editor; P is in progress with a verified deposit)
-- ---------------------------------------------------------------------------
select is(private.apply_timed_rules(now()), 0, 'nothing is overdue today');
select is(private.apply_timed_rules(now() + interval '14 days'), 0, 'on the due date itself nothing happens');
select is(private.apply_timed_rules(now() + interval '15 days'), 2,
  'the day after the due date R and T are put on hold (S has no confirmed editor)');
select is(pg_temp.pstatus('r'), 'on_hold/assigned', 'R is on hold and remembers it was assigned');
select is(pg_temp.pstatus('p'), 'in_progress/-', 'P (deposit verified) is untouched');
select is((select status::text from public.projects where id = pg_temp.a('s')), 'open',
  'an open project is never auto-held, even with a confirmed editor seeded');
select is(private.apply_timed_rules(now() + interval '16 days'), 0, 'a second run does nothing (never twice)');
select is((select count(*)::int from public.activity_logs where action = 'project.auto_held'
  and entity_id = pg_temp.project('r')::text and details ->> 'reason' = 'deposit_unpaid'
  and details ->> 'milestone_id' = (pg_temp.ms('r', 'deposit')).id::text), 1,
  'the hold is audited once with the deposit-unpaid reason and ids only');
select is((select count(*)::int from public.notifications where kind = 'project_auto_held'
  and recipient_id = 'a0000000-0000-0000-0000-00000000000a' and entity_id = pg_temp.project('r')), 1,
  'the admin is notified once');
select is((select count(*)::int from public.notifications where kind = 'project_auto_held'
  and recipient_id <> 'a0000000-0000-0000-0000-00000000000a'), 0, 'editors are never notified about the client deposit');
select pg_temp.as_user('a0000000-0000-0000-0000-000000000002');
select ok((select not project_active and not client_deposit_verified from public.get_assignment_gate(pg_temp.a('r'))),
  'editor B sees only that the project is on hold and the deposit unverified');
reset role;

-- Release returns to assigned; the rule does not act again for the same due date.
select pg_temp.as_user('a0000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok($$ select public.admin_set_project_status(pg_temp.project('r'), 'assigned') $$,
  'the admin releases the hold');
select throws_ok($$ select public.admin_set_project_status(pg_temp.project('r'), 'assigned') $$, 'ES409', null,
  'a second admin releasing the same hold is refused');
select throws_ok($$ select public.admin_set_project_status(pg_temp.project('r'), 'on_hold') $$, 'ES409',
  'An assigned project goes on hold only automatically, when the client deposit is overdue.',
  'an admin cannot put an assigned project on hold by hand');
reset role;
select is(pg_temp.pstatus('r'), 'assigned/-', 'R is assigned again');
select ok((pg_temp.ms('r', 'deposit')).auto_held_at is null
  and (pg_temp.ms('r', 'deposit')).auto_held_for_due = (pg_temp.ms('r', 'deposit')).due_date,
  'a manual release ends the deposit hold but remembers the due date it acted on');
select is(private.apply_timed_rules(now() + interval '20 days'), 0, 'the released project is not held again');
-- A later hold that is not the deposit hold (seeded by the owner) is not released by an extension.
update public.projects set status = 'on_hold', status_before_hold = 'assigned' where id = pg_temp.project('r');
select pg_temp.as_user('a0000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_extend_deposit_due((pg_temp.ms('r', 'deposit')).id, pg_temp.today() + 40, 'Asked again');
reset role;
select ok(pg_temp.pstatus('r') = 'on_hold/assigned'
  and (select details ->> 'hold_released' = 'false' from public.activity_logs
       where action = 'client_milestone.due_extended' and entity_id = pg_temp.project('r')::text),
  'an extension releases only the deposit-unpaid hold');
update public.projects set status = 'assigned', status_before_hold = null where id = pg_temp.project('r');

-- Extension releases an auto-hold and the rule can act again after the new date.
select is(pg_temp.state_as('a0000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_extend_deposit_due((pg_temp.ms('t', 'deposit')).id, pg_temp.today() + 30, ' ') $$),
  'ES422', 'an extension needs a reason');
select is(pg_temp.state_as('a0000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_extend_deposit_due((pg_temp.ms('t', 'deposit')).id, pg_temp.today() + 10, 'Asked') $$),
  'ES422', 'an extension must move the due date later');
select is(pg_temp.state_as('a0000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_extend_deposit_due((pg_temp.ms('p', 'deposit')).id, pg_temp.today() + 30, 'Asked') $$),
  'ES409', 'a verified deposit cannot be extended');
select pg_temp.as_user('a0000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok($$ select public.admin_extend_deposit_due((pg_temp.ms('t', 'deposit')).id, pg_temp.today() + 30,
  'Client asked for more time') $$, 'the admin extends the deposit due date');
reset role;
select ok(pg_temp.pstatus('t') = 'assigned/-' and (pg_temp.ms('t', 'deposit')).auto_held_at is null
  and (pg_temp.ms('t', 'deposit')).due_date = pg_temp.today() + 30
  and (select details ->> 'hold_released' = 'true' from public.activity_logs where action = 'client_milestone.due_extended'
       and entity_id = pg_temp.project('t')::text),
  'the extension releases the hold back to assigned and is audited');
select is(private.apply_timed_rules(now() + interval '30 days'), 0, 'not overdue before the new date has passed');
select is(private.apply_timed_rules(now() + interval '31 days'), 1, 'overdue again after the new date');
select pg_temp.as_user('a0000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok($$ select public.admin_set_project_status(pg_temp.project('t'), 'cancelled') $$,
  'an auto-held project can be cancelled');
reset role;
select is((select status::text from public.assignments where id = pg_temp.a('t')), 'withdrawn',
  'cancelling withdraws the confirmed editor');

-- admin_run_timed_rules: admin only, audited when it acts
select pg_temp.as_user('a0000000-0000-0000-0000-00000000000a', 'aal2');
select is(public.admin_run_timed_rules(), 0, 'the admin backstop runs the rules for now');
reset role;
select is((select count(*)::int from public.activity_logs where action = 'timed_rules.run'), 0,
  'a run with nothing to do writes no audit row');

-- Lock order: the project row before the milestone.
select ok(position('from public.projects where id = r.project_id for update' in
  pg_get_functiondef('private.apply_timed_rules(timestamptz)'::regprocedure))
  < position('from public.client_milestones where id = r.id for update' in
  pg_get_functiondef('private.apply_timed_rules(timestamptz)'::regprocedure)), 'the rule locks the project first');

-- ---------------------------------------------------------------------------
-- Business timezone setting (call 4)
-- ---------------------------------------------------------------------------
select is(pg_temp.state_as('a0000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_set_business_timezone('Mars/Olympus') $$), 'ES422', 'an unknown timezone is refused');
select pg_temp.as_user('a0000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_set_business_timezone('UTC');
reset role;
select ok(private.business_timezone() = 'UTC' and exists (select 1 from public.activity_logs
  where action = 'app_settings.changed' and details -> 'fields' = '["business_timezone"]'),
  'the admin changes the business timezone (audited)');

select * from finish();
rollback;
