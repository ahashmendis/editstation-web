-- Phase 12E: payout details schema and the LOCKED state. No API grants or policies on the payout
-- tables, the flag defaults to false, every write refuses while it is off (functions and direct
-- inserts), append-only history, the interim attestation (call 1) and the admin-only flag setter.
-- FAKE data only.
begin;

create extension if not exists pgtap with schema extensions;

select plan(30);

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
  ('e9000000-0000-0000-0000-00000000000a', 'p12e-s-admin@test.local', '{}', '{}'),
  ('e9000000-0000-0000-0000-000000000001', 'p12e-s-editor-a@test.local', '{}', '{}'),
  ('e9000000-0000-0000-0000-000000000002', 'p12e-s-editor-b@test.local', '{}', '{}');
select private.grant_admin_by_email('p12e-s-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('e9000000-0000-0000-0000-000000000001', 'e9000000-0000-0000-0000-000000000002');

create temp table t (name text primary key);
insert into t values ('editor_payout_details'), ('editor_payout_detail_versions'), ('editor_payout_attestations');
grant select on t to authenticated, anon;

-- ---------------------------------------------------------------------------
-- Tables: RLS on, no API grants, no policies
-- ---------------------------------------------------------------------------
select is((select count(*)::int from pg_class c join t on c.relname = t.name
  where c.relnamespace = 'public'::regnamespace and c.relrowsecurity), 3, 'RLS is on for the three payout tables');
select is_empty($$ select t.name || ' ' || r.role || ' ' || p.priv from t
  cross join (values ('anon'), ('authenticated')) r(role)
  cross join (values ('select'), ('insert'), ('update'), ('delete'), ('truncate'), ('references'), ('trigger')) p(priv)
  where has_table_privilege(r.role, 'public.' || t.name, p.priv) $$,
  'anon and authenticated hold no privilege at all on the payout tables');
select is_empty($$ select polname from pg_policy where polrelid in
  ('public.editor_payout_details'::regclass, 'public.editor_payout_detail_versions'::regclass,
   'public.editor_payout_attestations'::regclass) $$, 'no policies: the tables are reachable only through functions');
select is_empty($$ select t.name from t where has_table_privilege('public', 'public.' || t.name, 'select') $$,
  'PUBLIC holds no privilege either');

-- ---------------------------------------------------------------------------
-- The flag: off by default; only an MFA admin changes it, audited
-- ---------------------------------------------------------------------------
select is((select value from public.app_settings where key = 'payout_details_enabled'), 'false'::jsonb,
  'payout_details_enabled defaults to false');
select is(private.payout_details_enabled(), false, 'the helper reads it as off');

-- ---------------------------------------------------------------------------
-- Locked: every write refuses and no row can be created
-- ---------------------------------------------------------------------------
select pg_temp.as_user('e9000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_save_payout_details('TEST ACCOUNT', 'TEST BANK', 'TEST BRANCH', 'TEST-0000-1234') $$,
  'ES409', 'Payout details are not enabled yet. They stay off until Lenscape confirms how bank details are protected.',
  'an active editor cannot save payout details while they are off (clear message)');
select is(public.editor_get_payout_details(), '{"enabled": false, "saved": false}'::jsonb,
  'the editor sees that payout details are not available yet');
select pg_temp.as_user('e9000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_verify_payout_details('e9000000-0000-0000-0000-000000000001', 1, 'phone', 'TEST call') $$,
  'ES409', null, 'an admin cannot verify while payout details are off');
select throws_ok($$ select public.admin_reveal_payout_details('e9000000-0000-0000-0000-000000000001', 'TEST reason') $$,
  'ES409', null, 'there is nothing to reveal');
reset role;
select throws_ok($$ insert into public.editor_payout_details (editor_id, account_holder, bank, branch, account_number, version)
  values ('e9000000-0000-0000-0000-000000000001', 'TEST ACCOUNT', 'TEST BANK', 'TEST BRANCH', 'TEST-0000-1234', 1) $$,
  'ES409', null, 'even the table owner cannot insert payout details while they are off');
select throws_ok($$ insert into public.editor_payout_detail_versions (editor_id, version, account_holder, bank, branch, account_number)
  values ('e9000000-0000-0000-0000-000000000001', 1, 'TEST ACCOUNT', 'TEST BANK', 'TEST BRANCH', 'TEST-0000-1234') $$,
  'ES409', null, 'nor a version row');
select is((select count(*)::int from public.editor_payout_details) + (select count(*)::int from public.editor_payout_detail_versions),
  0, 'no payout rows exist');

-- ---------------------------------------------------------------------------
-- Interim attestation (call 1): admin only, note required, no bank data, append-only
-- ---------------------------------------------------------------------------
select pg_temp.as_user('e9000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.admin_attest_payout_outside_app('e9000000-0000-0000-0000-000000000001', 'TEST') $$,
  'ES403', null, 'an editor cannot attest');
select pg_temp.as_user('e9000000-0000-0000-0000-00000000000a', 'aal1');
select throws_ok($$ select public.admin_attest_payout_outside_app('e9000000-0000-0000-0000-000000000001', 'TEST') $$,
  'ES403', null, 'an admin without MFA cannot attest');
select pg_temp.as_user('e9000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_attest_payout_outside_app('e9000000-0000-0000-0000-000000000001', '  ') $$,
  'ES422', null, 'a note is required');
select throws_ok($$ select public.admin_attest_payout_outside_app(gen_random_uuid(), 'TEST') $$,
  'ES422', 'Editor not found.', 'an unknown editor is refused');
select lives_ok($$ select public.admin_attest_payout_outside_app('e9000000-0000-0000-0000-000000000001',
  'TEST verified by phone call') $$, 'an MFA admin records the attestation');
select ok((select (x -> 'attestation' ->> 'attested_by') = 'p12e-s-admin@test.local' and (x ->> 'attestation_current')::boolean
  and x ->> 'mark_paid_block' is null
  from public.admin_get_payout_details_masked('e9000000-0000-0000-0000-000000000001') x),
  'the admin view shows who attested and that payments can be marked paid');
reset role;
select ok((select attested_by = 'e9000000-0000-0000-0000-00000000000a' and attested_at is not null
  from public.editor_payout_attestations where editor_id = 'e9000000-0000-0000-0000-000000000001'),
  'it records the admin and the date');
select ok((select details = jsonb_build_object('editor_id', 'e9000000-0000-0000-0000-000000000001'::uuid,
    'attestation_id', (select id from public.editor_payout_attestations limit 1), 'fields', '["note"]'::jsonb)
  from public.activity_logs where action = 'payout_attestation.recorded'),
  'the audit row holds ids and field names only (not the note)');
reset role;
select throws_ok($$ update public.editor_payout_attestations set note = 'changed' $$, 'ES409', null,
  'an attestation cannot be changed');
select throws_ok($$ delete from public.editor_payout_attestations $$, 'ES409', null, 'or deleted');

-- ---------------------------------------------------------------------------
-- The flag setter
-- ---------------------------------------------------------------------------
select pg_temp.as_user('e9000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.admin_set_payout_enabled(true) $$, 'ES403', null, 'an editor cannot turn payouts on');
select pg_temp.as_user('e9000000-0000-0000-0000-00000000000a', 'aal1');
select throws_ok($$ select public.admin_set_payout_enabled(true) $$, 'ES403', null, 'nor an admin without MFA');
reset role;
select is(private.payout_details_enabled(), false, 'still off');
select pg_temp.as_user('e9000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok($$ select public.admin_set_payout_enabled(true) $$, 'an MFA admin turns payout details on');
reset role;
select ok((select private.payout_details_enabled() and exists (select 1 from public.activity_logs
  where action = 'app_settings.changed' and entity_id = 'payout_details_enabled'
    and actor_id = 'e9000000-0000-0000-0000-00000000000a' and details ->> 'enabled' = 'true')),
  'the flag is on and the change is audited');
select pg_temp.as_user('e9000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_attest_payout_outside_app('e9000000-0000-0000-0000-000000000002', 'TEST') $$,
  'ES409', 'Payout details are live: verify the editor''s payout account in the app instead.',
  'attestations cannot be recorded once payout details are live');
select ok((select not (x ->> 'attestation_current')::boolean and x ->> 'mark_paid_block' is not null
  from public.admin_get_payout_details_masked('e9000000-0000-0000-0000-000000000001') x),
  'the earlier attestation is retired: a verified payout account is now required');
reset role;

select * from finish();
rollback;
