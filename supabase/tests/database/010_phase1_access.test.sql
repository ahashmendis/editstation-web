-- Phase 1 access model: five identities (anon, pending applicant, active editor A,
-- active editor B, admin) plus escalation attempts. Decisions A, L, R.
begin;

create extension if not exists pgtap with schema extensions;

select plan(42);

-- ---------------------------------------------------------------------------
-- Fixtures (as postgres)
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'admin@test.local', '{}', '{}'),
  ('00000000-0000-0000-0000-000000000001', 'editor-a@test.local', '{}', '{}'),
  ('00000000-0000-0000-0000-000000000002', 'editor-b@test.local', '{}', '{}'),
  ('00000000-0000-0000-0000-000000000003', 'applicant@test.local', '{}', '{}'),
  -- Escalation attempt: user-controlled sign-up metadata claiming privileges.
  ('00000000-0000-0000-0000-000000000004', 'sneaky@test.local',
   '{"role":"admin","access_status":"active","is_admin":true}', '{}');

select private.grant_admin_by_email('admin@test.local', 'test bootstrap');

-- Expected totals, computed as postgres, so tests also pass on a non-empty local DB.
create temp table expected_totals as
  select (select count(*)::int from public.profiles) as profiles,
         (select count(*)::int from public.editor_profiles) as editor_profiles;
grant select on expected_totals to authenticated;

update public.editor_profiles set access_status = 'active'
where user_id in ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002');

-- ---------------------------------------------------------------------------
-- Sign-up trigger, escalation via metadata, audit log
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from public.profiles where email like '%@test.local'),
  5, 'sign-up creates one profile per account');

select is(
  (select count(*)::int from public.editor_profiles
   where access_status = 'none'
     and user_id in ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000004')),
  2, 'new accounts start with no editor access');

select ok(
  not exists (select 1 from public.admin_users where user_id = '00000000-0000-0000-0000-000000000004'),
  'sign-up metadata cannot create an admin');

select is(
  (select access_status::text from public.editor_profiles where user_id = '00000000-0000-0000-0000-000000000004'),
  'none', 'sign-up metadata cannot grant editor access');

select ok(
  exists (select 1 from public.activity_logs
          where action = 'admin.granted' and entity_id = '00000000-0000-0000-0000-00000000000a'),
  'admin grant is audited');

select is(
  (select count(*)::int from public.activity_logs
   where action = 'editor.access_changed'
     and entity_id in ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002')),
  2, 'editor access changes are audited');

select throws_ok(
  $$ update public.activity_logs set action = 'tampered' $$,
  '42501', null, 'activity_logs cannot be updated, even by postgres');

select throws_ok(
  $$ delete from public.activity_logs $$,
  '42501', null, 'activity_logs cannot be deleted, even by postgres');

-- ---------------------------------------------------------------------------
-- Anonymous
-- ---------------------------------------------------------------------------
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select throws_ok($$ select 1 from public.profiles $$, '42501', null, 'anon cannot read profiles');
select throws_ok($$ select 1 from public.admin_users $$, '42501', null, 'anon cannot read admin_users');
select throws_ok($$ select 1 from public.editor_profiles $$, '42501', null, 'anon cannot read editor_profiles');
select throws_ok($$ select 1 from public.activity_logs $$, '42501', null, 'anon cannot read activity_logs');
select throws_ok($$ select private.is_admin() $$, '42501', null, 'anon cannot call private helpers');

reset role;

-- ---------------------------------------------------------------------------
-- Pending applicant (no editor access)
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated","aal":"aal1"}', true);

select is((select count(*)::int from public.profiles), 1, 'applicant sees only their own profile');
select is((select access_status::text from public.editor_profiles), 'none', 'applicant sees own access status: none');
select is((select count(*)::int from public.admin_users), 0, 'applicant sees no admin rows');
select is((select count(*)::int from public.activity_logs), 0, 'applicant sees no activity logs');
select ok(not private.is_active_editor(), 'applicant is not an active editor');
select ok(not private.is_admin(), 'applicant is not an admin');

select lives_ok(
  $$ update public.profiles set full_name = 'Applicant Name' where id = '00000000-0000-0000-0000-000000000003' $$,
  'applicant can update their own name');

select throws_ok(
  $$ update public.profiles set email = 'x@test.local' where id = '00000000-0000-0000-0000-000000000003' $$,
  '42501', null, 'applicant cannot change profile email directly');

select throws_ok(
  $$ update public.editor_profiles set access_status = 'active' $$,
  '42501', null, 'applicant cannot activate themselves');

select throws_ok(
  $$ insert into public.admin_users (user_id) values ('00000000-0000-0000-0000-000000000003') $$,
  '42501', null, 'applicant cannot insert an admin row');

-- Checked via privilege, not by calling: in this Supabase image, a function
-- "permission denied" raised for a hinted role (anon/authenticated) crashes
-- Postgres (supautils hint bug). See docs/SECURITY_AND_PRIVACY.md.
select ok(
  not has_function_privilege('authenticated', 'private.grant_admin_by_email(text, text)', 'execute'),
  'applicant cannot call the admin bootstrap function');

select lives_ok(
  $$ update public.profiles set full_name = 'Hijacked' where id = '00000000-0000-0000-0000-000000000001' $$,
  'updating another user''s profile is silently filtered by RLS');

select throws_ok(
  $$ delete from public.profiles where id = '00000000-0000-0000-0000-000000000003' $$,
  '42501', null, 'applicant cannot delete profiles');

reset role;

-- ---------------------------------------------------------------------------
-- Active editor A
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal1"}', true);

select ok(private.is_active_editor(), 'editor A is an active editor');
select is((select count(*)::int from public.profiles), 1, 'editor A cannot see editor B or anyone else');
select is((select count(*)::int from public.editor_profiles), 1, 'editor A sees only their own editor profile');
select throws_ok(
  $$ update public.editor_profiles set access_status = 'suspended'
     where user_id = '00000000-0000-0000-0000-000000000002' $$,
  '42501', null, 'editor A cannot change anyone''s access status');

reset role;

-- ---------------------------------------------------------------------------
-- Admin without MFA (aal1): not an admin for authorisation
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated","aal":"aal1"}', true);

select ok(not private.is_admin(), 'admin without MFA is not authorised as admin');
select ok(private.is_admin_account(), 'admin without MFA is recognised as an admin account (routing only)');
select is((select count(*)::int from public.profiles), 1, 'admin without MFA sees only their own profile');
select is((select count(*)::int from public.activity_logs), 0, 'admin without MFA sees no activity logs');

reset role;

-- ---------------------------------------------------------------------------
-- Admin with MFA (aal2)
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated","aal":"aal2"}', true);

select ok(private.is_admin(), 'admin with MFA is authorised as admin');
select is((select count(*)::int from public.profiles), (select profiles from expected_totals),
  'admin with MFA sees all profiles');
select is((select count(*)::int from public.editor_profiles), (select editor_profiles from expected_totals),
  'admin with MFA sees all editor profiles');
select ok((select count(*) from public.activity_logs) > 0, 'admin with MFA can read activity logs');
select throws_ok(
  $$ update public.editor_profiles set access_status = 'active'
     where user_id = '00000000-0000-0000-0000-000000000003' $$,
  '42501', null, 'even admins cannot change access status directly (only via audited functions)');

reset role;

-- ---------------------------------------------------------------------------
-- Suspension and revocation take effect immediately
-- ---------------------------------------------------------------------------
update public.editor_profiles set access_status = 'suspended'
where user_id = '00000000-0000-0000-0000-000000000002';

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal1"}', true);
select ok(not private.is_active_editor(), 'suspended editor B loses editor access immediately');
reset role;

select is(
  (select full_name from public.profiles where id = '00000000-0000-0000-0000-000000000001'),
  null, 'applicant''s attempt to edit editor A''s profile changed nothing');

update public.admin_users set revoked_at = now()
where user_id = '00000000-0000-0000-0000-00000000000a';

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated","aal":"aal2"}', true);
select ok(not private.is_admin(), 'a revoked admin loses admin access immediately, even with MFA');
reset role;

select * from finish();

rollback;
