-- Phase 12B: asset access schema, checks, the append-only report guard and report RLS as admin,
-- editor A, editor B, applicant, suspended editor and anon.
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

create function pg_temp.as_anon()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('role', 'anon', true);
end;
$$;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('96000000-0000-0000-0000-00000000000a', 'p12bs-admin@test.local', '{}', '{}'),
  ('96000000-0000-0000-0000-000000000001', 'p12bs-editor-a@test.local', '{}', '{}'),
  ('96000000-0000-0000-0000-000000000002', 'p12bs-editor-b@test.local', '{}', '{}'),
  ('96000000-0000-0000-0000-000000000003', 'p12bs-applicant@test.local', '{}', '{}'),
  ('96000000-0000-0000-0000-000000000004', 'p12bs-suspended@test.local', '{}', '{}');
select private.grant_admin_by_email('p12bs-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('96000000-0000-0000-0000-000000000001', '96000000-0000-0000-0000-000000000002',
                  '96000000-0000-0000-0000-000000000004');

insert into public.projects (id, title, brief_type, status, first_opened_at) values
  ('96000000-0000-0000-0000-0000000000f1', 'Assets P1', 'fully_instructed', 'assigned', now()),
  ('96000000-0000-0000-0000-0000000000f2', 'Assets P2', 'fully_instructed', 'assigned', now());
insert into public.assignments (project_id, editor_id, status, proposed_amount, agreed_amount, agreed_currency,
  confirmed_at) values
  ('96000000-0000-0000-0000-0000000000f1', '96000000-0000-0000-0000-000000000001', 'confirmed', 1000, 1000, 'LKR', now()),
  ('96000000-0000-0000-0000-0000000000f2', '96000000-0000-0000-0000-000000000002', 'confirmed', 1000, 1000, 'LKR', now());
insert into public.project_assets (id, project_id, label, url, provider) values
  ('96000000-0000-0000-0000-0000000000a1', '96000000-0000-0000-0000-0000000000f1', 'X1', 'https://drive.example.com/x1', 'google_drive'),
  ('96000000-0000-0000-0000-0000000000a2', '96000000-0000-0000-0000-0000000000f2', 'X2', 'https://drive.example.com/x2', 'dropbox');
insert into public.asset_access_reports (id, project_id, asset_id, editor_id, note) values
  ('96000000-0000-0000-0000-0000000000b1','96000000-0000-0000-0000-0000000000f1',
   '96000000-0000-0000-0000-0000000000a1', '96000000-0000-0000-0000-000000000001', 'A cannot open X1'),
  ('96000000-0000-0000-0000-0000000000b2', '96000000-0000-0000-0000-0000000000f2',
   '96000000-0000-0000-0000-0000000000a2', '96000000-0000-0000-0000-000000000002', 'B cannot open X2'),
  ('96000000-0000-0000-0000-0000000000b3', '96000000-0000-0000-0000-0000000000f1',
   '96000000-0000-0000-0000-0000000000a1', '96000000-0000-0000-0000-000000000004', 'Report by soon suspended');
update public.editor_profiles set access_status = 'suspended' where user_id = '96000000-0000-0000-0000-000000000004';
insert into public.asset_access_grants (id, project_id, editor_id, shared_with_email, provider) values
  ('96000000-0000-0000-0000-0000000000c1', '96000000-0000-0000-0000-0000000000f1',
   '96000000-0000-0000-0000-000000000001', 'a@x.example.com', 'google_drive');

-- ---------------------------------------------------------------------------
-- Structure and checks
-- ---------------------------------------------------------------------------
select has_table('public', 'asset_access_reports', 'asset_access_reports exists');
select ok((select relrowsecurity from pg_class where oid = 'public.asset_access_reports'::regclass), 'RLS is on');
select is_empty($$ select privilege_type from information_schema.role_table_grants
  where table_schema = 'public' and table_name = 'asset_access_reports'
    and grantee in ('anon', 'authenticated') and privilege_type <> 'SELECT' $$,
  'no write grants on reports for anon or authenticated');
select ok(not has_table_privilege('anon', 'public.asset_access_reports', 'select'), 'anon has no select grant on reports');
select is((select count(*)::int from information_schema.columns where table_schema = 'public'
  and table_name = 'project_assets'
  and column_name in ('description', 'access_instructions', 'access_status', 'verified_by', 'verified_at',
                      'editor_confirmed_at')), 6, 'project_assets has the new columns');
select is((select count(*)::int from information_schema.columns where table_schema = 'public'
  and table_name = 'asset_access_grants'
  and column_name in ('access_type', 'removal_requested_at', 'removal_requested_by', 'removal_confirmed_at',
                      'removal_confirmed_by')), 5, 'asset_access_grants has the new columns');
select is((select access_status::text from public.project_assets where id = '96000000-0000-0000-0000-0000000000a1'),
  'awaiting_access', 'a new asset awaits access');
select is((select access_type::text from public.asset_access_grants where id = '96000000-0000-0000-0000-0000000000c1'),
  'editor_account', 'a share defaults to the editor''s own account');
select throws_ok($$ update public.project_assets set access_status = 'verified'
  where id = '96000000-0000-0000-0000-0000000000a1' $$, '23514', null, 'verified needs verified_at');
select throws_ok($$ update public.asset_access_grants set removal_confirmed_at = now()
  where id = '96000000-0000-0000-0000-0000000000c1' $$, '23514', null, 'removal confirmed needs removal requested');
select lives_ok($$ update public.asset_access_grants set removal_requested_at = now(), removal_confirmed_at = now()
  where id = '96000000-0000-0000-0000-0000000000c1' $$, 'requested then confirmed is allowed');
select is_empty($$ select column_name from information_schema.columns
  where table_schema = 'public' and table_name in ('project_assets', 'asset_access_reports')
    and column_name ~ '(client|email|phone|company|contact|price)' $$,
  'editor-readable asset tables hold no client identity or price columns');

-- ---------------------------------------------------------------------------
-- Append-only guard (as postgres, so only the trigger can refuse)
-- ---------------------------------------------------------------------------
select throws_ok($$ delete from public.asset_access_reports where id = '96000000-0000-0000-0000-0000000000b2' $$,
  'ES409', null, 'a report cannot be deleted');
select throws_ok($$ update public.asset_access_reports set note = 'edited' where id = '96000000-0000-0000-0000-0000000000b2' $$,
  'ES409', null, 'a report note cannot be changed');
select throws_ok($$ update public.asset_access_reports set editor_id = '96000000-0000-0000-0000-000000000001'
  where id = '96000000-0000-0000-0000-0000000000b2' $$, 'ES409', null, 'a report editor cannot be changed');
select lives_ok($$ update public.asset_access_reports set resolved_at = now(), resolved_by = '96000000-0000-0000-0000-00000000000a'
  where id = '96000000-0000-0000-0000-0000000000b3' $$, 'a report can be resolved once');
select throws_ok($$ update public.asset_access_reports set resolved_at = now() + interval '1 day'
  where id = '96000000-0000-0000-0000-0000000000b3' $$, 'ES409', null, 'a resolution cannot be changed');
select throws_ok($$ update public.asset_access_reports set resolved_at = null, resolved_by = null
  where id = '96000000-0000-0000-0000-0000000000b3' $$, 'ES409', null, 'a resolution cannot be undone');

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
select pg_temp.as_user('96000000-0000-0000-0000-00000000000a', 'aal2');
select is((select count(*)::int from public.asset_access_reports), 3, 'admin (aal2) reads every report');
select throws_ok($$ insert into public.asset_access_reports (project_id, editor_id, note)
  values ('96000000-0000-0000-0000-0000000000f1', '96000000-0000-0000-0000-000000000001', 'x') $$,
  '42501', null, 'admin cannot insert a report directly');
reset role;

select pg_temp.as_user('96000000-0000-0000-0000-00000000000a', 'aal1');
select is((select count(*)::int from public.asset_access_reports), 0, 'admin without MFA reads no reports');
reset role;

select pg_temp.as_user('96000000-0000-0000-0000-000000000001');
select results_eq($$ select note from public.asset_access_reports $$, array['A cannot open X1'],
  'editor A reads only their own report');
select throws_ok($$ insert into public.asset_access_reports (project_id, editor_id, note)
  values ('96000000-0000-0000-0000-0000000000f1', '96000000-0000-0000-0000-000000000001', 'x') $$,
  '42501', null, 'editor A cannot insert a report directly');
select throws_ok($$ update public.project_assets set access_status = 'inaccessible' $$,
  '42501', null, 'editor A cannot change an asset status directly');
select is((select count(*)::int from public.asset_access_grants), 0, 'editor A reads no folder shares');
reset role;

select pg_temp.as_user('96000000-0000-0000-0000-000000000002');
select results_eq($$ select note from public.asset_access_reports $$, array['B cannot open X2'],
  'editor B reads only their own report (no cross-editor read)');
reset role;

select pg_temp.as_user('96000000-0000-0000-0000-000000000003');
select is((select count(*)::int from public.asset_access_reports), 0, 'an applicant reads no reports');
reset role;

select pg_temp.as_user('96000000-0000-0000-0000-000000000004');
select is((select count(*)::int from public.asset_access_reports), 0, 'a suspended editor reads not even their own report');
reset role;

select pg_temp.as_anon();
select throws_ok($$ select count(*) from public.asset_access_reports $$, '42501', null, 'anon cannot read reports');
reset role;

select is((select count(*)::int from public.asset_access_reports), 3, 'nothing was written by the API roles');

select * from finish();
rollback;
