-- Phase 12E: payout details with the flag enabled INSIDE THIS TRANSACTION and FAKE data only.
-- Mark-paid gate in both modes (attestation while off, verified details while on, attestation
-- retired), save and version history, masking, reveal always audited with a reason, verification
-- reset on change, admin notification, editor isolation, and no bank value in activity_logs or
-- notifications. Roles: admin, editor A, editor B, pending applicant, suspended editor, anon.
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

create function pg_temp.as_anon()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('role', 'anon', true);
end;
$$;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('ea000000-0000-0000-0000-00000000000a', 'p12e-f-admin@test.local', '{}', '{}'),
  ('ea000000-0000-0000-0000-000000000001', 'p12e-f-editor-a@test.local', '{}', '{}'),
  ('ea000000-0000-0000-0000-000000000002', 'p12e-f-editor-b@test.local', '{}', '{}'),
  ('ea000000-0000-0000-0000-000000000003', 'p12e-f-applicant@test.local', '{}', '{}'),
  ('ea000000-0000-0000-0000-000000000004', 'p12e-f-suspended@test.local', '{}', '{}');
select private.grant_admin_by_email('p12e-f-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('ea000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000002');
update public.editor_profiles set access_status = 'suspended' where user_id = 'ea000000-0000-0000-0000-000000000004';

-- An approved payment for p_editor on a new project. Returns the payment id.
create function pg_temp.payment(p_title text, p_editor uuid)
returns uuid language plpgsql as $$
declare
  v_project uuid;
  v_id uuid;
  v_pay uuid;
begin
  perform pg_temp.as_user('ea000000-0000-0000-0000-00000000000a', 'aal2');
  v_project := public.admin_create_project(jsonb_build_object('title', p_title, 'brief_type', 'fully_instructed',
    'deadline', '2099-12-31', 'brief', jsonb_build_object('instructions', 'Cut it'),
    'deliverables', jsonb_build_array(jsonb_build_object('name', 'Main'))));
  perform public.admin_set_project_status(v_project, 'open');
  perform public.admin_save_terms_draft(v_project, '{"editor_milestone_shares": [100]}');
  perform public.admin_agree_terms(v_project, 1);
  v_id := public.admin_make_offer(v_project, p_editor, 10000, 'LKR');
  perform pg_temp.as_user(p_editor);
  perform public.editor_respond_offer(v_id, 'accept');
  perform pg_temp.as_user('ea000000-0000-0000-0000-00000000000a', 'aal2');
  perform public.admin_confirm_assignment(v_id);
  select id into v_pay from public.payments where assignment_id = v_id;
  reset role;
  update public.payments set status = 'pending_approval', payable_reason = 'client_deposit_verified',
    payable_at = now() where id = v_pay;
  perform pg_temp.as_user('ea000000-0000-0000-0000-00000000000a', 'aal2');
  perform public.admin_set_payment_status(v_pay, 'approved');
  reset role;
  return v_pay;
end;
$$;

create temp table ids (kind text primary key, id uuid not null);
grant select on ids to authenticated, anon;
insert into ids select 'a1', pg_temp.payment('A1', 'ea000000-0000-0000-0000-000000000001');
insert into ids select 'a2', pg_temp.payment('A2', 'ea000000-0000-0000-0000-000000000001');
insert into ids select 'a3', pg_temp.payment('A3', 'ea000000-0000-0000-0000-000000000001');
insert into ids select 'b1', pg_temp.payment('B1', 'ea000000-0000-0000-0000-000000000002');
create function pg_temp.p(p_kind text) returns uuid language sql as $$ select id from ids where kind = p_kind $$;
grant execute on function pg_temp.p(text) to authenticated, anon;
create function pg_temp.today() returns date language sql as $$ select (now() at time zone 'Asia/Colombo')::date $$;
grant execute on function pg_temp.today() to authenticated;
create function pg_temp.view(p_editor uuid) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.as_user('ea000000-0000-0000-0000-00000000000a', 'aal2');
  v := public.admin_get_payout_details_masked(p_editor);
  reset role;
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- Mode 1: flag off. Mark-paid needs a current attestation (call 1)
-- ---------------------------------------------------------------------------
select pg_temp.as_user('ea000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_mark_payment_paid(pg_temp.p('a1'), 'TEST-REF-1', pg_temp.today()) $$, 'ES409',
  'Before marking this paid, record on the payout card that the editor''s payout account was verified outside the app.',
  'off, no attestation: mark-paid is refused and says how to fix it');
reset role;
select is((select status::text from public.payments where id = pg_temp.p('a1')), 'approved', 'the payment is unchanged');
select pg_temp.as_user('ea000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_attest_payout_outside_app('ea000000-0000-0000-0000-000000000001', 'TEST verified by phone');
select lives_ok($$ select public.admin_mark_payment_paid(pg_temp.p('a1'), 'TEST-REF-1', pg_temp.today()) $$,
  'off, with an attestation: mark-paid works');
select throws_ok($$ select public.admin_mark_payment_paid(pg_temp.p('b1'), 'TEST-REF-B', pg_temp.today()) $$, 'ES409',
  null, 'editor A''s attestation does not cover editor B');
reset role;
select ok((select count(*) = 1 from public.activity_logs where action = 'payment.paid'
  and entity_id = pg_temp.p('a1')::text), 'the existing payment audit still records the paid payment');

-- ---------------------------------------------------------------------------
-- Mode 2: flag on (this transaction only). The attestation is retired
-- ---------------------------------------------------------------------------
select pg_temp.as_user('ea000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_set_payout_enabled(true);
select throws_ok($$ select public.admin_mark_payment_paid(pg_temp.p('a2'), 'TEST-REF-2', pg_temp.today()) $$, 'ES409',
  'The editor has not added payout details yet. Ask them to add them on their Earnings page, then verify them by phone.',
  'on: the attestation no longer counts; payout details are required');
reset role;
select is(pg_temp.view('ea000000-0000-0000-0000-000000000001') ->> 'attestation_current', 'false',
  'the admin view shows the attestation as retired');

-- Who may save
select pg_temp.as_anon();
select throws_ok($$ select public.editor_save_payout_details('TEST ACCOUNT', 'TEST BANK', 'TEST BRANCH', 'TEST-0000-1234') $$,
  'ES401', null, 'anon cannot save');
select throws_ok($$ select public.editor_get_payout_details() $$, 'ES401', null, 'anon cannot read');
select pg_temp.as_user('ea000000-0000-0000-0000-000000000003');
select throws_ok($$ select public.editor_save_payout_details('TEST ACCOUNT', 'TEST BANK', 'TEST BRANCH', 'TEST-0000-1234') $$,
  'ES403', null, 'a pending applicant cannot save');
select throws_ok($$ select public.editor_get_payout_details() $$, 'ES403', null, 'a pending applicant cannot read');
select pg_temp.as_user('ea000000-0000-0000-0000-000000000004');
select throws_ok($$ select public.editor_save_payout_details('TEST ACCOUNT', 'TEST BANK', 'TEST BRANCH', 'TEST-0000-1234') $$,
  'ES403', null, 'a suspended editor cannot save');
select pg_temp.as_user('ea000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.editor_save_payout_details('TEST ACCOUNT', 'TEST BANK', 'TEST BRANCH', 'TEST-0000-1234') $$,
  'ES403', null, 'an admin cannot save payout details for anyone');

-- Validation
select pg_temp.as_user('ea000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_save_payout_details('TEST ACCOUNT', ' ', 'TEST BRANCH', 'TEST-0000-1234') $$,
  'ES422', null, 'every field is required');
select throws_ok($$ select public.editor_save_payout_details('TEST ACCOUNT', 'TEST BANK', 'TEST BRANCH', 'abc') $$,
  'ES422', null, 'a too-short account number is refused');
select throws_ok($$ select public.editor_save_payout_details('TEST ACCOUNT', 'TEST BANK', 'TEST BRANCH', 'AB-123') $$,
  'ES422', null, 'an account number needs at least 6 letters or digits');
select throws_ok($$ select public.editor_save_payout_details('TEST ACCOUNT', 'TEST BANK', 'TEST BRANCH', 'TEST;0000') $$,
  'ES422', null, 'an account number with other characters is refused');
select throws_ok($$ select public.editor_save_payout_details('TEST ACCOUNT', 'TEST BANK', 'TEST BRANCH', 'TEST-ACCOUNT') $$,
  'ES422', null, 'an account number needs at least one digit');

-- Save (fake values)
select lives_ok($$ select public.editor_save_payout_details(' TEST ACCOUNT ', 'TEST BANK', 'TEST BRANCH', 'TEST-0000-1234') $$,
  'an active editor saves their own payout details');
select is(public.editor_get_payout_details() - 'last_changed_at',
  '{"enabled": true, "saved": true, "account_holder": "TEST ACCOUNT", "bank": "TEST BANK", "branch": "TEST BRANCH",
    "account_number_masked": "****1234", "verification_status": "unverified", "verified_at": null}'::jsonb,
  'the editor sees their details with the account number masked to the last 4, unverified');
select pg_temp.as_user('ea000000-0000-0000-0000-000000000002');
select is(public.editor_get_payout_details(), '{"enabled": true, "saved": false}'::jsonb,
  'editor B cannot see editor A''s details');
reset role;
select ok((select version = 1 and verification_status = 'unverified' and account_holder = 'TEST ACCOUNT'
  from public.editor_payout_details where editor_id = 'ea000000-0000-0000-0000-000000000001'), 'version 1 is stored, unverified');
select is((select count(*)::int from public.editor_payout_detail_versions
  where editor_id = 'ea000000-0000-0000-0000-000000000001' and changed_by = editor_id), 1, 'a version row records who changed it');
select is((select details from public.activity_logs where action = 'payout_details.changed'),
  jsonb_build_object('editor_id', 'ea000000-0000-0000-0000-000000000001'::uuid, 'version', 1,
    'fields', '["account_holder", "bank", "branch", "account_number"]'::jsonb),
  'the audit row holds the editor id, version and field names only');
select ok((select count(*) = 1 from public.notifications where kind = 'payout_details_changed'
  and recipient_id = 'ea000000-0000-0000-0000-00000000000a' and entity_type = 'editor_profile'
  and entity_id = 'ea000000-0000-0000-0000-000000000001'), 'admins are notified of the change');

-- Admin masked view and reveal
select ok((select x ->> 'account_number_masked' = '****1234' and x ->> 'version' = '1'
    and x::text not like '%0000-1234%' and x ->> 'mark_paid_block' like '%not verified%'
  from pg_temp.view('ea000000-0000-0000-0000-000000000001') x),
  'the admin view is masked and explains why payments are blocked');
select pg_temp.as_user('ea000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.admin_reveal_payout_details('ea000000-0000-0000-0000-000000000001', 'TEST') $$,
  'ES403', null, 'an editor cannot reveal the full number, even their own');
select throws_ok($$ select public.admin_get_payout_details_masked('ea000000-0000-0000-0000-000000000001') $$,
  'ES403', null, 'nor read the admin view');
select pg_temp.as_user('ea000000-0000-0000-0000-00000000000a', 'aal1');
select throws_ok($$ select public.admin_reveal_payout_details('ea000000-0000-0000-0000-000000000001', 'TEST') $$,
  'ES403', null, 'an admin without MFA cannot reveal');
select pg_temp.as_user('ea000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_reveal_payout_details('ea000000-0000-0000-0000-000000000001', '   ') $$,
  'ES422', 'Please give a reason for revealing the full account number.', 'a reason is required');
reset role;
select is((select count(*)::int from public.activity_logs where action = 'payout_details.revealed'), 0,
  'a refused reveal writes nothing');
select pg_temp.as_user('ea000000-0000-0000-0000-00000000000a', 'aal2');
select is(public.admin_reveal_payout_details('ea000000-0000-0000-0000-000000000001', 'TEST check before transfer'),
  'TEST-0000-1234', 'an MFA admin with a reason sees the full number');
select public.admin_reveal_payout_details('ea000000-0000-0000-0000-000000000001', 'TEST second look');
select throws_ok($$ select public.admin_reveal_payout_details('ea000000-0000-0000-0000-000000000001', 'TEST 1234567') $$,
  'ES422', 'Do not type bank details here: give the reason in words.', 'a reason with a long digit run is refused');
select throws_ok($$ select public.admin_reveal_payout_details('ea000000-0000-0000-0000-000000000001', 'TEST 12-34 56') $$,
  'ES422', null, 'separators do not hide a digit run');
reset role;
select is((select count(*)::int from public.activity_logs where action = 'payout_details.revealed'
  and actor_id = 'ea000000-0000-0000-0000-00000000000a' and entity_id = 'ea000000-0000-0000-0000-000000000001'
  and details ->> 'admin_id' = 'ea000000-0000-0000-0000-00000000000a' and details ->> 'reason' like 'TEST%'), 2,
  'every reveal writes an audit row with admin, editor and reason');

-- Verification
select pg_temp.as_user('ea000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_mark_payment_paid(pg_temp.p('a2'), 'TEST-REF-2', pg_temp.today()) $$, 'ES409',
  'The editor''s payout details are not verified. Verify them by phone on the payout card first.',
  'on, unverified: mark-paid is refused');
select throws_ok($$ select public.admin_verify_payout_details('ea000000-0000-0000-0000-000000000001', 2, 'phone', 'TEST call') $$,
  'ES409', null, 'verifying a version other than the current one is refused');
select throws_ok($$ select public.admin_verify_payout_details('ea000000-0000-0000-0000-000000000001', 1, 'email', 'TEST call') $$,
  'ES422', null, 'an unknown method is refused');
select throws_ok($$ select public.admin_verify_payout_details('ea000000-0000-0000-0000-000000000001', 1, 'phone', ' ') $$,
  'ES422', null, 'a note is required');
select pg_temp.as_user('ea000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.admin_verify_payout_details('ea000000-0000-0000-0000-000000000001', 1, 'phone', 'TEST') $$,
  'ES403', null, 'an editor cannot verify their own details');
select pg_temp.as_user('ea000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok($$ select public.admin_verify_payout_details('ea000000-0000-0000-0000-000000000001', 1, 'phone', 'TEST called the editor') $$,
  'an MFA admin records a phone verification');
select throws_ok($$ select public.admin_verify_payout_details('ea000000-0000-0000-0000-000000000001', 1, 'phone', 'TEST') $$,
  'ES409', 'These payout details are already verified.', 'verifying twice is refused');
select lives_ok($$ select public.admin_mark_payment_paid(pg_temp.p('a2'), 'TEST-REF-2', pg_temp.today()) $$,
  'on, verified: mark-paid works');
reset role;
select ok((select verification_status = 'verified' and verified_by = 'ea000000-0000-0000-0000-00000000000a'
  and verified_method = 'phone' and verified_at is not null
  from public.editor_payout_details where editor_id = 'ea000000-0000-0000-0000-000000000001'), 'the verification is recorded');

-- Any change resets verification and notifies again; identical saves change nothing
select pg_temp.as_user('ea000000-0000-0000-0000-000000000001');
select is(public.editor_get_payout_details() ->> 'verification_status', 'verified', 'the editor sees "verified"');
select public.editor_save_payout_details('TEST ACCOUNT', 'TEST BANK', 'TEST BRANCH TWO', 'TEST-0000-1234');
reset role;
select ok((select version = 2 and verification_status = 'unverified' and verified_by is null and verified_at is null
    and verified_method is null and verification_note is null
  from public.editor_payout_details where editor_id = 'ea000000-0000-0000-0000-000000000001'),
  'a change makes version 2 and resets verification');
select is((select details -> 'fields' from public.activity_logs where action = 'payout_details.changed'
  and details ->> 'version' = '2'), '["branch"]'::jsonb, 'the audit row names only the changed field');
select is((select count(*)::int from public.notifications where kind = 'payout_details_changed'), 2,
  'admins are notified again');
select pg_temp.as_user('ea000000-0000-0000-0000-000000000001');
select public.editor_save_payout_details('TEST ACCOUNT', 'TEST BANK', 'TEST BRANCH TWO', 'TEST-0000-1234');
reset role;
select is((select count(*)::int from public.editor_payout_detail_versions
  where editor_id = 'ea000000-0000-0000-0000-000000000001'), 2, 'saving identical details adds no version');
select pg_temp.as_user('ea000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_mark_payment_paid(pg_temp.p('a3'), 'TEST-REF-3', pg_temp.today()) $$, 'ES409',
  null, 'after a change, mark-paid is refused until verified again');
reset role;

-- Editor B's own details stay separate
select pg_temp.as_user('ea000000-0000-0000-0000-000000000002');
select public.editor_save_payout_details('TEST ACCOUNT B', 'TEST BANK', 'TEST BRANCH', 'TEST-0000-9876');
select is(public.editor_get_payout_details() ->> 'account_number_masked', '****9876', 'editor B sees only their own');
reset role;

-- The details guard holds for the table owner too
select throws_ok($$ update public.editor_payout_details set account_number = 'TEST-0000-4321'
  where editor_id = 'ea000000-0000-0000-0000-000000000002' $$, 'ES409', null,
  'a content change without the next version is refused');
select throws_ok($$ update public.editor_payout_details set account_number = 'TEST-0000-4321', version = version + 1,
  verification_status = 'verified', verified_at = now(), verified_method = 'phone'
  where editor_id = 'ea000000-0000-0000-0000-000000000002' $$, 'ES409', null,
  'a content change cannot stay verified');
select throws_ok($$ update public.editor_payout_details set version = version - 1
  where editor_id = 'ea000000-0000-0000-0000-000000000002' $$, 'ES409', null, 'the version never moves back');
select is(private.mask_account_number('AB 1-2C'), '****', 'a short number is never shown in full');

-- History is append-only
select throws_ok($$ update public.editor_payout_detail_versions set bank = 'X' $$, 'ES409', null,
  'version history cannot be changed');
select throws_ok($$ delete from public.editor_payout_detail_versions $$, 'ES409', null, 'or deleted');

-- No bank value anywhere in the audit log or notifications
select is_empty($$ select id from public.activity_logs
  where details::text ~ '(0000-1234|0000-9876|TEST BANK|TEST BRANCH|TEST ACCOUNT)' $$,
  'no account number, bank, branch or holder appears in activity_logs');
select is_empty($$ select id from public.notifications
  where (title || ' ' || body) ~ '(0000-1234|0000-9876|TEST BANK|TEST BRANCH|TEST ACCOUNT)' $$,
  'nor in notifications');

-- Turning the flag off again locks writes
select pg_temp.as_user('ea000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_set_payout_enabled(false);
select pg_temp.as_user('ea000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_save_payout_details('TEST ACCOUNT', 'TEST BANK', 'TEST BRANCH', 'TEST-0000-5555') $$,
  'ES409', null, 'off again: saving is refused');
select pg_temp.as_user('ea000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_reveal_payout_details('ea000000-0000-0000-0000-000000000001', 'TEST reason') $$,
  'ES409', null, 'off again: revealing the full number is refused');
select is(public.admin_get_payout_details_masked('ea000000-0000-0000-0000-000000000001') ->> 'account_number_masked',
  '****1234', 'off again: the masked view still works (stored rows are not purged)');
select is(public.admin_get_payout_details_masked('ea000000-0000-0000-0000-000000000001') ->> 'attestation_current',
  'true', 'off again: the earlier attestation counts again');
reset role;
reset role;

select * from finish();
rollback;
