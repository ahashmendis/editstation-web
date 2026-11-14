-- Phase 5: assets schema. project_assets, project_references.early_access, asset_access_grants.
-- Admin-only reads (editor policies arrive in Phase 6), no direct writes for anyone.
begin;

create extension if not exists pgtap with schema extensions;

select plan(26);

create function pg_temp.as_user(p_uid uuid, p_aal text default 'aal1')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create function pg_temp.as_anon()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('role', 'anon', true);
end;
$$;

create function pg_temp.visible_counts()
returns int[] language sql as $$
  select array[
    (select count(*)::int from public.project_assets),
    (select count(*)::int from public.asset_access_grants)];
$$;
grant execute on function pg_temp.visible_counts() to authenticated;

-- ---------------------------------------------------------------------------
-- Fixtures (as postgres)
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('50000000-0000-0000-0000-00000000000a', 'p5s-admin@test.local', '{}', '{}'),
  ('50000000-0000-0000-0000-000000000001', 'p5s-editor-a@test.local', '{}', '{}'),
  ('50000000-0000-0000-0000-000000000002', 'p5s-editor-b@test.local', '{}', '{}'),
  ('50000000-0000-0000-0000-000000000003', 'p5s-applicant@test.local', '{}', '{}'),
  ('50000000-0000-0000-0000-000000000004', 'p5s-suspended@test.local', '{}', '{}');
select private.grant_admin_by_email('p5s-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('50000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000002');
update public.editor_profiles set access_status = 'suspended'
where user_id = '50000000-0000-0000-0000-000000000004';

insert into public.projects (id, title, brief_type, status, first_opened_at) values
  ('50000000-0000-0000-0000-0000000000f1', 'Assets project', 'fully_instructed', 'open', now()),
  ('50000000-0000-0000-0000-0000000000f2', 'Disposable', 'creative_led', 'draft', null);
insert into public.project_assets (project_id, label, url, provider, kind) values
  ('50000000-0000-0000-0000-0000000000f1', 'Raw footage', 'https://drive.example.com/f/1', 'google_drive', 'footage');
insert into public.asset_access_grants (id, project_id, editor_id, shared_with_email, provider) values
  ('50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-0000000000f1',
   '50000000-0000-0000-0000-000000000001', 'editor-a@drive.example.com', 'google_drive');

-- ---------------------------------------------------------------------------
-- Structure
-- ---------------------------------------------------------------------------
select has_column('public', 'project_references', 'early_access', 'project_references has early_access');
select col_default_is('public', 'project_references', 'early_access', 'false',
  'project_references.early_access defaults to false');
select has_type('public', 'asset_provider', 'asset_provider enum exists');
select enum_has_labels('public', 'asset_provider', array['google_drive', 'dropbox', 'other'],
  'asset_provider has exactly google_drive, dropbox, other');

-- ---------------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------------
select pg_temp.as_anon();
select throws_ok($$ select 1 from public.project_assets $$, '42501', null, 'anon cannot read project_assets');
select throws_ok($$ select 1 from public.asset_access_grants $$, '42501', null, 'anon cannot read asset_access_grants');
reset role;

select pg_temp.as_user('50000000-0000-0000-0000-000000000001');
select is(pg_temp.visible_counts(), array[0,0], 'editor A sees no assets or grants (even their own grant)');
reset role;
select pg_temp.as_user('50000000-0000-0000-0000-000000000002');
select is(pg_temp.visible_counts(), array[0,0], 'editor B sees no assets or grants');
reset role;
select pg_temp.as_user('50000000-0000-0000-0000-000000000004');
select is(pg_temp.visible_counts(), array[0,0], 'a suspended editor sees no assets or grants');
reset role;
select pg_temp.as_user('50000000-0000-0000-0000-000000000003');
select is(pg_temp.visible_counts(), array[0,0], 'a pending applicant sees no assets or grants');
reset role;
select pg_temp.as_user('50000000-0000-0000-0000-00000000000a', 'aal1');
select is(pg_temp.visible_counts(), array[0,0], 'admin without MFA sees no assets or grants');
reset role;

-- ---------------------------------------------------------------------------
-- Admin with MFA: reads everything, writes nothing directly
-- ---------------------------------------------------------------------------
select pg_temp.as_user('50000000-0000-0000-0000-00000000000a', 'aal2');
select is(pg_temp.visible_counts(), array[1,1], 'admin with MFA sees the seeded asset and grant');
select throws_ok($$ insert into public.project_assets (project_id, label, url)
  values ('50000000-0000-0000-0000-0000000000f1', 'X', 'https://x.example.com') $$,
  '42501', null, 'admin cannot insert assets directly');
select throws_ok($$ update public.project_assets set label = 'X' $$, '42501', null, 'admin cannot update assets directly');
select throws_ok($$ delete from public.project_assets $$, '42501', null, 'admin cannot delete assets directly');
select throws_ok($$ insert into public.asset_access_grants (project_id, editor_id, shared_with_email, provider)
  values ('50000000-0000-0000-0000-0000000000f1', '50000000-0000-0000-0000-000000000002', 'b@x.com', 'other') $$,
  '42501', null, 'admin cannot insert grants directly');
select throws_ok($$ update public.asset_access_grants set revoked_at = now() $$, '42501', null,
  'admin cannot update grants directly');
select throws_ok($$ delete from public.asset_access_grants $$, '42501', null, 'admin cannot delete grants directly');
reset role;

-- ---------------------------------------------------------------------------
-- Constraints (as postgres)
-- ---------------------------------------------------------------------------
select throws_ok($$ insert into public.project_assets (project_id, label, url)
  values ('50000000-0000-0000-0000-0000000000f1', 'X', 'http://x.example.com') $$,
  '23514', null, 'an asset link must be https');
select throws_ok($$ insert into public.project_assets (project_id, label, url)
  values ('50000000-0000-0000-0000-0000000000f1', repeat('a', 201), 'https://x.example.com') $$,
  '23514', null, 'an asset label is at most 200 characters');
select throws_ok($$ insert into public.project_assets (project_id, label, url, kind)
  values ('50000000-0000-0000-0000-0000000000f1', 'X', 'https://x.example.com', repeat('k', 41)) $$,
  '23514', null, 'an asset kind is at most 40 characters');
select throws_ok($$ insert into public.asset_access_grants (project_id, editor_id, shared_with_email, provider)
  values ('50000000-0000-0000-0000-0000000000f1', '50000000-0000-0000-0000-000000000002', ' A@B.com', 'other') $$,
  '23514', null, 'a share email must be stored normalised');
select throws_ok($$ insert into public.asset_access_grants (project_id, editor_id, shared_with_email, provider)
  values ('50000000-0000-0000-0000-0000000000f1', '50000000-0000-0000-0000-000000000001',
          'editor-a@drive.example.com', 'dropbox') $$,
  '23505', null, 'one live grant per project, editor and email');
update public.asset_access_grants set revoked_at = now() where id = '50000000-0000-0000-0000-0000000000a1';
select lives_ok($$ insert into public.asset_access_grants (project_id, editor_id, shared_with_email, provider)
  values ('50000000-0000-0000-0000-0000000000f1', '50000000-0000-0000-0000-000000000001',
          'editor-a@drive.example.com', 'google_drive') $$,
  'a new grant for the same account is allowed once the earlier one is revoked');
select throws_ok($$ insert into public.asset_access_grants (project_id, editor_id, shared_with_email, provider, revoke_reason)
  values ('50000000-0000-0000-0000-0000000000f1', '50000000-0000-0000-0000-000000000002', 'b@x.com', 'other', 'Done') $$,
  '23514', null, 'a revoke reason needs revoked_at');

insert into public.project_assets (project_id, label, url)
values ('50000000-0000-0000-0000-0000000000f2', 'Gone soon', 'https://x.example.com/gone');
delete from public.projects where id = '50000000-0000-0000-0000-0000000000f2';
select is((select count(*)::int from public.project_assets where project_id = '50000000-0000-0000-0000-0000000000f2'),
  0, 'deleting a project deletes its assets');

select * from finish();

rollback;
