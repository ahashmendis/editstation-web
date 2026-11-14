-- Phase 5: asset sync, early-access setters, folder-share log and the revoke checklist.
-- Review Focus 1 (asset list input) and 2 (share email normalisation).
begin;

create extension if not exists pgtap with schema extensions;

select plan(66);

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

-- ---------------------------------------------------------------------------
-- Fixtures (as postgres)
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('51000000-0000-0000-0000-00000000000a', 'p5f-admin@test.local', '{}', '{}'),
  ('51000000-0000-0000-0000-000000000001', 'p5f-editor-a@test.local', '{}', '{}'),
  ('51000000-0000-0000-0000-000000000002', 'p5f-editor-b@test.local', '{}', '{}'),
  ('51000000-0000-0000-0000-000000000003', 'p5f-applicant@test.local', '{}', '{}'),
  ('51000000-0000-0000-0000-000000000004', 'p5f-suspended@test.local', '{}', '{}');
select private.grant_admin_by_email('p5f-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('51000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000002');
update public.editor_profiles set access_status = 'suspended'
where user_id = '51000000-0000-0000-0000-000000000004';

insert into public.projects (id, title, brief_type, status, first_opened_at, archived_at) values
  ('51000000-0000-0000-0000-0000000000f1', 'Main', 'fully_instructed', 'open', now(), null),
  ('51000000-0000-0000-0000-0000000000f2', 'Other', 'fully_instructed', 'open', now(), null),
  ('51000000-0000-0000-0000-0000000000f3', 'Cancelled', 'fully_instructed', 'cancelled', now(), null),
  ('51000000-0000-0000-0000-0000000000f4', 'Archived', 'fully_instructed', 'open', now(), now()),
  ('51000000-0000-0000-0000-0000000000c1', 'Checklist open', 'fully_instructed', 'open', now(), null),
  ('51000000-0000-0000-0000-0000000000c2', 'Checklist cancelled', 'fully_instructed', 'cancelled', now(), null),
  ('51000000-0000-0000-0000-0000000000c3', 'Checklist archived', 'fully_instructed', 'open', now(), now()),
  ('51000000-0000-0000-0000-0000000000c4', 'Checklist completed', 'fully_instructed', 'completed', now(), null);
insert into public.brief_versions (project_id, version, instructions)
values ('51000000-0000-0000-0000-0000000000f1', 1, 'Do it');
insert into public.project_deliverables (project_id, name) values ('51000000-0000-0000-0000-0000000000f1', 'Main');
insert into public.project_references (id, project_id, url)
values ('51000000-0000-0000-0000-0000000000b1', '51000000-0000-0000-0000-0000000000f1', 'https://ref.example.com/1');
insert into public.project_assets (id, project_id, label, url) values
  ('51000000-0000-0000-0000-0000000000e4', '51000000-0000-0000-0000-0000000000f4', 'Archived asset',
   'https://drive.example.com/arch');

-- Checklist grants (explicit times fix the order).
insert into public.asset_access_grants (id, project_id, editor_id, shared_with_email, provider, shared_at,
  revoked_at) values
  ('51000000-0000-0000-0000-0000000000d1', '51000000-0000-0000-0000-0000000000c1',
   '51000000-0000-0000-0000-000000000001', 'a@drive.example.com', 'google_drive', '2026-01-01', null),
  ('51000000-0000-0000-0000-0000000000d2', '51000000-0000-0000-0000-0000000000c1',
   '51000000-0000-0000-0000-000000000004', 's@drive.example.com', 'google_drive', '2026-01-02', null),
  ('51000000-0000-0000-0000-0000000000d3', '51000000-0000-0000-0000-0000000000c2',
   '51000000-0000-0000-0000-000000000001', 'a@drive.example.com', 'dropbox', '2026-01-03', null),
  ('51000000-0000-0000-0000-0000000000d4', '51000000-0000-0000-0000-0000000000c3',
   '51000000-0000-0000-0000-000000000001', 'a@drive.example.com', 'other', '2026-01-04', null),
  ('51000000-0000-0000-0000-0000000000d5', '51000000-0000-0000-0000-0000000000c1',
   '51000000-0000-0000-0000-000000000002', 'b@drive.example.com', 'google_drive', '2026-01-05', now()),
  ('51000000-0000-0000-0000-0000000000d6', '51000000-0000-0000-0000-0000000000c4',
   '51000000-0000-0000-0000-000000000001', 'a@drive.example.com', 'google_drive', '2026-01-06', null);

create temp table ids (kind text primary key, id uuid not null);
grant select, insert, update on ids to authenticated;

create function pg_temp.asset_id(p_label text)
returns uuid language sql as $$ select id from public.project_assets where label = p_label $$;
grant execute on function pg_temp.asset_id(text) to authenticated;

create function pg_temp.audits(p_action text)
returns int language sql as $$
  select count(*)::int from public.activity_logs where action = p_action $$;
grant execute on function pg_temp.audits(text) to authenticated;

-- ---------------------------------------------------------------------------
-- admin_save_assets
-- ---------------------------------------------------------------------------
select pg_temp.as_user('51000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok($$ select public.admin_save_assets('51000000-0000-0000-0000-0000000000f1', '[
  {"label": "Footage A", "url": "https://drive.example.com/a", "provider": "google_drive", "kind": "footage"},
  {"label": "Music", "url": "https://dropbox.example.com/m", "provider": "dropbox", "notes": "Licensed"},
  {"label": "Logo", "url": "https://x.example.com/logo"}]') $$, 'admin saves three assets');
select is((select array_agg(label order by sort_order) from public.project_assets
  where project_id = '51000000-0000-0000-0000-0000000000f1'), array['Footage A', 'Music', 'Logo'],
  'three assets are stored in the given order');
select ok((select bool_and(not early_access) from public.project_assets
  where project_id = '51000000-0000-0000-0000-0000000000f1'), 'new assets are not early access');
select is((select provider from public.project_assets where label = 'Logo'), 'other'::public.asset_provider,
  'a missing provider defaults to other');
select is(pg_temp.audits('project.assets_changed'), 1, 'adding assets writes one audit row');

select lives_ok($$ select public.admin_save_assets('51000000-0000-0000-0000-0000000000f1', jsonb_build_array(
  jsonb_build_object('id', pg_temp.asset_id('Footage A'), 'label', 'Footage A (v2)',
    'url', 'https://drive.example.com/a', 'provider', 'google_drive', 'kind', 'footage'),
  jsonb_build_object('id', pg_temp.asset_id('Music'), 'label', 'Music', 'url', 'https://dropbox.example.com/m',
    'provider', 'dropbox', 'notes', 'Licensed'),
  jsonb_build_object('label', 'Script', 'url', 'https://x.example.com/script', 'kind', 'script'))) $$,
  'admin edits, drops and adds assets in one save');
select is((select array_agg(label order by sort_order) from public.project_assets
  where project_id = '51000000-0000-0000-0000-0000000000f1'), array['Footage A (v2)', 'Music', 'Script'],
  'the edited, kept and new assets remain; the dropped one is gone');
select is(pg_temp.audits('project.assets_changed'), 2, 'the edit writes one more audit row');

select lives_ok($$ select public.admin_save_assets('51000000-0000-0000-0000-0000000000f1', jsonb_build_array(
  jsonb_build_object('id', pg_temp.asset_id('Footage A (v2)'), 'label', 'Footage A (v2)',
    'url', 'https://drive.example.com/a', 'provider', 'google_drive', 'kind', 'footage'),
  jsonb_build_object('id', pg_temp.asset_id('Music'), 'label', 'Music', 'url', 'https://dropbox.example.com/m',
    'provider', 'dropbox', 'notes', 'Licensed'),
  jsonb_build_object('id', pg_temp.asset_id('Script'), 'label', 'Script', 'url', 'https://x.example.com/script',
    'kind', 'script'))) $$, 'admin saves identical content');
select lives_ok($$ select public.admin_save_assets('51000000-0000-0000-0000-0000000000f1', jsonb_build_array(
  jsonb_build_object('id', pg_temp.asset_id('Script'), 'label', 'Script', 'url', 'https://x.example.com/script',
    'kind', 'script'),
  jsonb_build_object('id', pg_temp.asset_id('Footage A (v2)'), 'label', 'Footage A (v2)',
    'url', 'https://drive.example.com/a', 'provider', 'google_drive', 'kind', 'footage'),
  jsonb_build_object('id', pg_temp.asset_id('Music'), 'label', 'Music', 'url', 'https://dropbox.example.com/m',
    'provider', 'dropbox', 'notes', 'Licensed'))) $$, 'admin reorders assets only');
select is((select array_agg(label order by sort_order) from public.project_assets
  where project_id = '51000000-0000-0000-0000-0000000000f1'), array['Script', 'Footage A (v2)', 'Music'],
  'the reorder is stored');
select is(pg_temp.audits('project.assets_changed'), 2, 'identical content and a reorder write no audit row');
select ok((select current_brief_version = 1 from public.projects where id = '51000000-0000-0000-0000-0000000000f1')
  and (select count(*) = 1 from public.brief_versions where project_id = '51000000-0000-0000-0000-0000000000f1'),
  'asset changes on an opened project never create a brief version');

-- Unknown keys ignored, then null and [] clear the list (on the other project).
select lives_ok($$ select public.admin_save_assets('51000000-0000-0000-0000-0000000000f2',
  '[{"label": "Q1", "url": "https://x.example.com/q1", "colour": "red"}]') $$, 'unknown item keys are ignored');

-- Review Focus 1.
select throws_ok($$ select public.admin_save_assets('51000000-0000-0000-0000-0000000000f1', '{}') $$,
  'ES422', null, 'an object instead of a list is refused');
select throws_ok($$ select public.admin_save_assets('51000000-0000-0000-0000-0000000000f1', '"x"') $$,
  'ES422', null, 'a string instead of a list is refused');
select throws_ok($$ select public.admin_save_assets('51000000-0000-0000-0000-0000000000f1', '[1]') $$,
  'ES422', null, 'a non-object item is refused');
select throws_ok($$ select public.admin_save_assets('51000000-0000-0000-0000-0000000000f1',
  (select jsonb_agg(jsonb_build_object('label', 'A' || g, 'url', 'https://x.example.com/' || g))
   from generate_series(1, 101) g)) $$, 'ES422', null, 'more than 100 assets are refused');
select throws_ok($$ select public.admin_save_assets('51000000-0000-0000-0000-0000000000f1',
  '[{"label": "X", "url": "http://x.example.com"}]') $$, 'ES422', null, 'an http link is refused');
select throws_ok($$ select public.admin_save_assets('51000000-0000-0000-0000-0000000000f1',
  jsonb_build_array(jsonb_build_object('id', pg_temp.asset_id('Q1'), 'label', 'Q1', 'url', 'https://x.example.com/q1'))) $$,
  'ES422', null, 'an asset of another project is refused');
select throws_ok($$ select public.admin_save_assets('51000000-0000-0000-0000-0000000000f1', jsonb_build_array(
  jsonb_build_object('id', pg_temp.asset_id('Music'), 'label', 'Music', 'url', 'https://dropbox.example.com/m'),
  jsonb_build_object('id', pg_temp.asset_id('Music'), 'label', 'Music 2', 'url', 'https://dropbox.example.com/m'))) $$,
  'ES422', null, 'a duplicated asset id is refused');
select throws_ok($$ select public.admin_save_assets('51000000-0000-0000-0000-0000000000f1',
  '[{"url": "https://x.example.com"}]') $$, 'ES422', null, 'an asset without a label is refused');
select is((select count(*)::int from public.project_assets where project_id = '51000000-0000-0000-0000-0000000000f1'),
  3, 'refused saves change nothing');

select lives_ok($$ select public.admin_save_assets('51000000-0000-0000-0000-0000000000f2', null) $$,
  'null clears the asset list');
select is((select count(*)::int from public.project_assets where project_id = '51000000-0000-0000-0000-0000000000f2'),
  0, 'the list is empty after null');
select public.admin_save_assets('51000000-0000-0000-0000-0000000000f2', '[{"label": "Q2", "url": "https://x.example.com/q2"}]');
select lives_ok($$ select public.admin_save_assets('51000000-0000-0000-0000-0000000000f2', '[]') $$,
  'an empty list clears the asset list');
select is((select count(*)::int from public.project_assets where project_id = '51000000-0000-0000-0000-0000000000f2'),
  0, 'the list is empty after []');

select throws_ok($$ select public.admin_save_assets('51000000-0000-0000-0000-0000000000f3', '[]') $$,
  'ES409', null, 'assets of a cancelled project cannot be saved');
select throws_ok($$ select public.admin_save_assets('51000000-0000-0000-0000-0000000000f4', '[]') $$,
  'ES409', null, 'assets of an archived project cannot be saved');
select throws_ok($$ select public.admin_save_assets('51000000-0000-0000-0000-0000000000ff', '[]') $$,
  'ES422', null, 'an unknown project is refused');

-- ---------------------------------------------------------------------------
-- Early access
-- ---------------------------------------------------------------------------
select lives_ok($$ select public.admin_set_asset_early_access(pg_temp.asset_id('Music'), true) $$,
  'admin marks an asset as early access');
select ok((select early_access from public.project_assets where label = 'Music'), 'the asset is early access');
select is((select details from public.activity_logs where action = 'project.early_access_changed'),
  jsonb_build_object('project_id', '51000000-0000-0000-0000-0000000000f1'::uuid, 'asset_id', pg_temp.asset_id('Music'),
    'early_access', true), 'one audit row with ids and the new value');
select public.admin_set_asset_early_access(pg_temp.asset_id('Music'), true);
select is(pg_temp.audits('project.early_access_changed'), 1, 'setting an unchanged value writes no audit row');
select throws_ok($$ select public.admin_set_asset_early_access('51000000-0000-0000-0000-0000000000ff', true) $$,
  'ES422', null, 'an unknown asset is refused');
select throws_ok($$ select public.admin_set_asset_early_access(pg_temp.asset_id('Music'), null) $$,
  'ES422', null, 'a missing value is refused');
select throws_ok($$ select public.admin_set_asset_early_access('51000000-0000-0000-0000-0000000000e4', true) $$,
  'ES409', null, 'an asset of an archived project cannot be changed');

select lives_ok($$ select public.admin_set_reference_early_access('51000000-0000-0000-0000-0000000000b1', true) $$,
  'admin marks a reference as early access');
select is(pg_temp.audits('project.early_access_changed'), 2, 'the reference change is audited');
select throws_ok($$ select public.admin_set_reference_early_access('51000000-0000-0000-0000-0000000000ff', true) $$,
  'ES422', null, 'an unknown reference is refused');
select lives_ok($$ select public.admin_save_brief('51000000-0000-0000-0000-0000000000f1',
  '{"references": [{"id": "51000000-0000-0000-0000-0000000000b1", "url": "https://ref.example.com/1"}]}') $$,
  'admin saves the brief with an unchanged reference list');
select ok((select early_access from public.project_references where id = '51000000-0000-0000-0000-0000000000b1')
  and (select count(*) = 1 from public.brief_versions where project_id = '51000000-0000-0000-0000-0000000000f1'),
  'the reference keeps early access and no brief version is created');

-- ---------------------------------------------------------------------------
-- Folder shares
-- ---------------------------------------------------------------------------
insert into ids select 'g1', public.admin_record_asset_grant('51000000-0000-0000-0000-0000000000f1',
  '51000000-0000-0000-0000-000000000001', '  Editor@Drive.COM ', 'google_drive', 'https://drive.example.com/folder');
select ok((select shared_with_email = 'editor@drive.com' and shared_by = '51000000-0000-0000-0000-00000000000a'
    and revoked_at is null
  from public.asset_access_grants where id = (select id from ids where kind = 'g1')),
  'a share is recorded with the normalised email and the admin');
select is((select details from public.activity_logs where action = 'asset_grant.recorded'),
  jsonb_build_object('grant_id', (select id from ids where kind = 'g1'),
    'project_id', '51000000-0000-0000-0000-0000000000f1'::uuid, 'editor_id', '51000000-0000-0000-0000-000000000001'::uuid),
  'the share audit row holds ids only');
select throws_ok($$ select public.admin_record_asset_grant('51000000-0000-0000-0000-0000000000f1',
  '51000000-0000-0000-0000-000000000001', 'editor@DRIVE.com', 'dropbox') $$,
  'ES409', 'This share is already recorded.', 'the same account cannot be recorded twice while live');
select lives_ok($$ select public.admin_revoke_asset_grant((select id from ids where kind = 'g1'), '  Finished  ') $$,
  'admin revokes a share');
select ok((select revoked_at is not null and revoked_by = '51000000-0000-0000-0000-00000000000a'
    and revoke_reason = 'Finished'
  from public.asset_access_grants where id = (select id from ids where kind = 'g1')),
  'the revoke is recorded with the admin and the trimmed reason');
insert into ids select 'g2', public.admin_record_asset_grant('51000000-0000-0000-0000-0000000000f1',
  '51000000-0000-0000-0000-000000000001', '  Editor@Drive.COM ', 'google_drive');
select is((select count(*)::int from public.asset_access_grants
  where project_id = '51000000-0000-0000-0000-0000000000f1' and revoked_at is null), 1,
  'the account can be recorded again after the revoke');
select throws_ok($$ select public.admin_record_asset_grant('51000000-0000-0000-0000-0000000000f1',
  '51000000-0000-0000-0000-000000000003', 'app@x.com', 'other') $$, 'ES422', 'Choose an active editor.',
  'a share for an applicant is refused');
select throws_ok($$ select public.admin_record_asset_grant('51000000-0000-0000-0000-0000000000f1',
  '51000000-0000-0000-0000-000000000004', 's@x.com', 'other') $$, 'ES422', 'Choose an active editor.',
  'a share for a suspended editor is refused');
select throws_ok($$ select public.admin_record_asset_grant('51000000-0000-0000-0000-0000000000f1',
  '51000000-0000-0000-0000-000000000002', 'not-an-email', 'other') $$, 'ES422', null, 'a bad email is refused');
select throws_ok($$ select public.admin_record_asset_grant('51000000-0000-0000-0000-0000000000f1',
  '51000000-0000-0000-0000-000000000002', 'b@x.com', 'other', 'http://x.example.com') $$, 'ES422', null,
  'an http folder link is refused');
select throws_ok($$ select public.admin_record_asset_grant('51000000-0000-0000-0000-0000000000f1',
  '51000000-0000-0000-0000-000000000002', 'b@x.com', null) $$, 'ES422', null, 'a missing provider is refused');
select throws_ok($$ select public.admin_record_asset_grant('51000000-0000-0000-0000-0000000000f3',
  '51000000-0000-0000-0000-000000000002', 'b@x.com', 'other') $$, 'ES409', null,
  'a share on a cancelled project is refused');
select throws_ok($$ select public.admin_record_asset_grant('51000000-0000-0000-0000-0000000000f4',
  '51000000-0000-0000-0000-000000000002', 'b@x.com', 'other') $$, 'ES409', null,
  'a share on an archived project is refused');

select public.admin_revoke_asset_grant((select id from ids where kind = 'g2'));
select throws_ok($$ select public.admin_revoke_asset_grant((select id from ids where kind = 'g2')) $$,
  'ES409', null, 'revoking twice is refused');
select throws_ok($$ select public.admin_revoke_asset_grant('51000000-0000-0000-0000-0000000000ff') $$,
  'ES422', null, 'revoking an unknown share is refused');
insert into ids select 'g3', public.admin_record_asset_grant('51000000-0000-0000-0000-0000000000f2',
  '51000000-0000-0000-0000-000000000002', 'b@x.com', 'dropbox');
reset role;
update public.projects set archived_at = now() where id = '51000000-0000-0000-0000-0000000000f2';
select pg_temp.as_user('51000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok($$ select public.admin_revoke_asset_grant((select id from ids where kind = 'g3'), 'Archived') $$,
  'a share on an archived project can still be revoked');

-- ---------------------------------------------------------------------------
-- Revoke checklist (Phase 5 reasons; Phase 6 adds no_active_assignment, filtered out here)
-- ---------------------------------------------------------------------------
select results_eq($$ select grant_id, reason from public.admin_pending_revocations()
  where project_id in ('51000000-0000-0000-0000-0000000000c1', '51000000-0000-0000-0000-0000000000c2',
    '51000000-0000-0000-0000-0000000000c3', '51000000-0000-0000-0000-0000000000c4')
    and reason in ('editor_not_active', 'project_closed') $$,
  $$ values ('51000000-0000-0000-0000-0000000000d2'::uuid, 'editor_not_active'),
            ('51000000-0000-0000-0000-0000000000d3'::uuid, 'project_closed'),
            ('51000000-0000-0000-0000-0000000000d4'::uuid, 'project_closed'),
            ('51000000-0000-0000-0000-0000000000d6'::uuid, 'project_closed') $$,
  'the checklist lists suspended editors and closed projects, in share order');
select ok(not exists (select 1 from public.admin_pending_revocations()
  where grant_id in ('51000000-0000-0000-0000-0000000000d1', '51000000-0000-0000-0000-0000000000d5')
    and reason in ('editor_not_active', 'project_closed')),
  'an active editor on an open project and a revoked share are not listed for those reasons');
select is((select shared_with_email || ' ' || provider from public.admin_pending_revocations()
  where grant_id = '51000000-0000-0000-0000-0000000000d2'), 's@drive.example.com google_drive',
  'the checklist returns the shared email and provider');
reset role;

-- ---------------------------------------------------------------------------
-- Non-admin identities
-- ---------------------------------------------------------------------------
create function pg_temp.refused(p_code text)
returns int language plpgsql as $$
declare
  v int := 0;
  v_p uuid := '51000000-0000-0000-0000-0000000000f1';
begin
  begin perform public.admin_save_assets(v_p, '[]'); exception when sqlstate 'ES401' or sqlstate 'ES403' then if sqlstate = p_code then v := v + 1; end if; end;
  begin perform public.admin_set_reference_early_access('51000000-0000-0000-0000-0000000000b1', false); exception when sqlstate 'ES401' or sqlstate 'ES403' then if sqlstate = p_code then v := v + 1; end if; end;
  begin perform public.admin_set_asset_early_access('51000000-0000-0000-0000-0000000000e4', false); exception when sqlstate 'ES401' or sqlstate 'ES403' then if sqlstate = p_code then v := v + 1; end if; end;
  begin perform public.admin_record_asset_grant(v_p, '51000000-0000-0000-0000-000000000002', 'b@x.com', 'other'); exception when sqlstate 'ES401' or sqlstate 'ES403' then if sqlstate = p_code then v := v + 1; end if; end;
  begin perform public.admin_revoke_asset_grant('51000000-0000-0000-0000-0000000000d1'); exception when sqlstate 'ES401' or sqlstate 'ES403' then if sqlstate = p_code then v := v + 1; end if; end;
  begin perform public.admin_pending_revocations(); exception when sqlstate 'ES401' or sqlstate 'ES403' then if sqlstate = p_code then v := v + 1; end if; end;
  return v;
end;
$$;
grant execute on function pg_temp.refused(text) to anon, authenticated;

select pg_temp.as_anon();
select is(pg_temp.refused('ES401'), 6, 'anon is refused (ES401) by all six functions');
reset role;
select pg_temp.as_user('51000000-0000-0000-0000-00000000000a', 'aal1');
select is(pg_temp.refused('ES403'), 6, 'admin without MFA is refused (ES403) by all six functions');
reset role;
select pg_temp.as_user('51000000-0000-0000-0000-000000000001');
select is(pg_temp.refused('ES403'), 6, 'editor A is refused (ES403) by all six functions');
reset role;
select pg_temp.as_user('51000000-0000-0000-0000-000000000003');
select is(pg_temp.refused('ES403'), 6, 'an applicant is refused (ES403) by all six functions');
reset role;

-- ---------------------------------------------------------------------------
-- Audit hygiene
-- ---------------------------------------------------------------------------
select is_empty($$ select action from public.activity_logs
  where action in ('project.assets_changed', 'project.early_access_changed', 'asset_grant.recorded',
                   'asset_grant.revoked')
    and (details::text like '%@%' or details::text like '%https%' or details::text like '%Footage%'
         or details::text like '%Music%' or details::text like '%Finished%') $$,
  'Phase 5 audit rows hold no emails, links, labels or reasons');

select * from finish();

rollback;
