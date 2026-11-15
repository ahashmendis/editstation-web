-- Phase 12B: asset access workflow. Reports only by the assigned editor of that project, the admin
-- notification, confirm-is-not-verify, admin verify/resolve, link change resets verification,
-- removal requested/confirmed states, and ending an assignment never marking removal.
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

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('97000000-0000-0000-0000-00000000000a', 'p12bf-admin@test.local', '{}', '{}'),
  ('97000000-0000-0000-0000-000000000001', 'p12bf-editor-a@test.local', '{}', '{}'),
  ('97000000-0000-0000-0000-000000000002', 'p12bf-editor-b@test.local', '{}', '{}');
select private.grant_admin_by_email('p12bf-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('97000000-0000-0000-0000-000000000001', '97000000-0000-0000-0000-000000000002');

insert into public.projects (id, title, brief_type, status, first_opened_at) values
  ('97000000-0000-0000-0000-0000000000f1', 'Assets Flow P1', 'fully_instructed', 'assigned', now()),
  ('97000000-0000-0000-0000-0000000000f2', 'Assets Flow P2', 'fully_instructed', 'assigned', now());
insert into public.assignments (id, project_id, editor_id, status, proposed_amount, agreed_amount, agreed_currency,
  confirmed_at) values
  ('97000000-0000-0000-0000-0000000000e1', '97000000-0000-0000-0000-0000000000f1',
   '97000000-0000-0000-0000-000000000001', 'confirmed', 1000, 1000, 'LKR', now()),
  ('97000000-0000-0000-0000-0000000000e2', '97000000-0000-0000-0000-0000000000f2',
   '97000000-0000-0000-0000-000000000002', 'confirmed', 1000, 1000, 'LKR', now());
insert into public.project_assets (id, project_id, label, url, provider, sort_order) values
  ('97000000-0000-0000-0000-0000000000a1', '97000000-0000-0000-0000-0000000000f1', 'X1', 'https://drive.example.com/x1', 'google_drive', 0),
  ('97000000-0000-0000-0000-0000000000a3', '97000000-0000-0000-0000-0000000000f1', 'X3', 'https://drive.example.com/x3', 'google_drive', 1),
  ('97000000-0000-0000-0000-0000000000a2', '97000000-0000-0000-0000-0000000000f2', 'X2', 'https://drive.example.com/x2', 'dropbox', 0);

create temp table ids (kind text primary key, id uuid not null);
grant select, insert on ids to authenticated;

-- ---------------------------------------------------------------------------
-- Editor A (assigned to P1)
-- ---------------------------------------------------------------------------
select pg_temp.as_user('97000000-0000-0000-0000-000000000001');
select lives_ok($$ insert into ids select 'r1', public.editor_report_asset_inaccessible(
  '97000000-0000-0000-0000-0000000000a1', '  Secretnote access denied  ') $$, 'editor A reports an asset on their project');
select throws_ok($$ select public.editor_report_asset_inaccessible('97000000-0000-0000-0000-0000000000a1', 'again') $$,
  'ES409', null, 'a second open report on the same asset is refused');
select throws_ok($$ select public.editor_report_asset_inaccessible('97000000-0000-0000-0000-0000000000a3', '   ') $$,
  'ES422', null, 'a report needs a note');
select throws_ok($$ select public.editor_report_asset_inaccessible('97000000-0000-0000-0000-0000000000a2', 'not mine') $$,
  'ES403', null, 'editor A cannot report an asset on another editor''s project');
select throws_ok($$ select public.editor_confirm_asset_access('97000000-0000-0000-0000-0000000000a1') $$,
  'ES409', null, 'editor A cannot say they can open an asset they reported until the report is closed');
select lives_ok($$ select public.editor_confirm_asset_access('97000000-0000-0000-0000-0000000000a3') $$,
  'editor A says they can open X3');
select results_eq($$ select note from public.asset_access_reports $$, array['Secretnote access denied'],
  'editor A reads their own trimmed report');
reset role;

-- ---------------------------------------------------------------------------
-- Editor B (assigned to P2 only)
-- ---------------------------------------------------------------------------
select pg_temp.as_user('97000000-0000-0000-0000-000000000002');
select throws_ok($$ select public.editor_report_asset_inaccessible('97000000-0000-0000-0000-0000000000a1', 'x') $$,
  'ES403', null, 'editor B cannot report an asset on P1');
select throws_ok($$ select public.editor_confirm_asset_access('97000000-0000-0000-0000-0000000000a1') $$,
  'ES403', null, 'editor B cannot confirm an asset on P1');
select throws_ok($$ select public.editor_report_asset_inaccessible(gen_random_uuid(), 'x') $$,
  'ES403', null, 'an unknown asset is refused like a foreign one');
select is((select count(*)::int from public.asset_access_reports), 0, 'editor B cannot read editor A''s report');
reset role;

-- ---------------------------------------------------------------------------
-- Effects (as postgres)
-- ---------------------------------------------------------------------------
select is((select access_status::text from public.project_assets where id = '97000000-0000-0000-0000-0000000000a1'),
  'inaccessible', 'the reported asset is inaccessible');
select ok((select access_status = 'awaiting_access' and editor_confirmed_at is not null
  from public.project_assets where id = '97000000-0000-0000-0000-0000000000a3'),
  '"I can open this" is recorded but never verifies the asset');
select hasnt_column('public', 'project_assets', 'editor_confirmed_by',
  'no editor id is stored on the editor-readable asset row');
select is((select count(*)::int from regexp_matches(
  (select prosrc from pg_proc where oid = 'private.lock_asset_for_editor(uuid)'::regprocedure),
  'editor_project_stage', 'g')), 2, 'the editor stage is checked again after the project lock');

-- A repeat "I can open this" in the same assignment is a no-op; one older than the assignment's
-- confirmation is stale and is recorded again.
select pg_temp.as_user('97000000-0000-0000-0000-000000000001');
select public.editor_confirm_asset_access('97000000-0000-0000-0000-0000000000a3');
reset role;
select is((select count(*)::int from public.activity_logs where action = 'asset.editor_can_open'), 1,
  'a repeat confirmation in the same assignment is not recorded twice');
update public.project_assets set editor_confirmed_at = now() - interval '1 day'
where id = '97000000-0000-0000-0000-0000000000a3';
select pg_temp.as_user('97000000-0000-0000-0000-000000000001');
select public.editor_confirm_asset_access('97000000-0000-0000-0000-0000000000a3');
reset role;
select ok((select count(*)::int = 2 from public.activity_logs where action = 'asset.editor_can_open')
  and (select editor_confirmed_at = now() from public.project_assets where id = '97000000-0000-0000-0000-0000000000a3'),
  'a stale confirmation (before the current assignment) is recorded again');
select results_eq($$ select recipient_id, kind::text, entity_type, entity_id from public.notifications
  where kind = 'asset_inaccessible' $$,
  $$ values ('97000000-0000-0000-0000-00000000000a'::uuid, 'asset_inaccessible', 'project',
             '97000000-0000-0000-0000-0000000000f1'::uuid) $$,
  'the admin is notified once, about the project');
select ok(exists (select 1 from private.notification_outbox where kind = 'asset_inaccessible'),
  'an email row is queued in the outbox');
select is_empty($$ select id from public.notifications where kind = 'asset_inaccessible'
  and (title || body) like '%Secretnote%' $$, 'the notification does not repeat the editor''s note');
select is((select array_agg(k order by k) from public.activity_logs l, jsonb_object_keys(l.details) k
  where l.action = 'asset.reported_inaccessible'), array['asset_id', 'project_id', 'report_id'],
  'the report audit row holds ids only');

-- ---------------------------------------------------------------------------
-- Admin: verify and resolve
-- ---------------------------------------------------------------------------
select pg_temp.as_user('97000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_verify_asset('97000000-0000-0000-0000-0000000000a1') $$,
  'ES409', null, 'an asset with an open report cannot be verified');
select lives_ok($$ select public.admin_resolve_asset_report((select id from ids where kind = 'r1')) $$,
  'the admin resolves the report');
select is((select access_status::text from public.project_assets where id = '97000000-0000-0000-0000-0000000000a1'),
  'awaiting_access', 'with no open report the asset awaits access again');
select throws_ok($$ select public.admin_resolve_asset_report((select id from ids where kind = 'r1')) $$,
  'ES409', null, 'a report is resolved only once');
select throws_ok($$ select public.admin_resolve_asset_report(gen_random_uuid()) $$,
  'ES422', null, 'an unknown report is not found');
select lives_ok($$ select public.admin_verify_asset('97000000-0000-0000-0000-0000000000a1') $$, 'the admin verifies X1');
select ok((select access_status = 'verified' and verified_by = '97000000-0000-0000-0000-00000000000a'
  and verified_at is not null from public.project_assets where id = '97000000-0000-0000-0000-0000000000a1'),
  'X1 is verified by the admin');
select throws_ok($$ select public.admin_verify_asset('97000000-0000-0000-0000-0000000000a1') $$,
  'ES409', null, 'a verified asset cannot be verified twice');
select lives_ok($$ select public.admin_save_assets('97000000-0000-0000-0000-0000000000f1', jsonb_build_array(
  jsonb_build_object('id', '97000000-0000-0000-0000-0000000000a1', 'label', 'X1', 'url', 'https://drive.example.com/x1-new',
    'provider', 'google_drive', 'description', 'Raw camera A', 'access_instructions', 'Use your own Google account'),
  jsonb_build_object('id', '97000000-0000-0000-0000-0000000000a3', 'label', 'X3', 'url', 'https://drive.example.com/x3',
    'provider', 'google_drive'))) $$, 'the admin changes the X1 link and adds a description');
select ok((select access_status = 'awaiting_access' and verified_at is null and description = 'Raw camera A'
  and access_instructions = 'Use your own Google account'
  from public.project_assets where id = '97000000-0000-0000-0000-0000000000a1'),
  'a changed link resets verification; description and instructions are saved');
select ok((select editor_confirmed_at is not null from public.project_assets
  where id = '97000000-0000-0000-0000-0000000000a3'), 'an unchanged asset keeps its state');
reset role;

-- A link change must not hide an open report.
select pg_temp.as_user('97000000-0000-0000-0000-000000000001');
select lives_ok($$ select public.editor_report_asset_inaccessible('97000000-0000-0000-0000-0000000000a1', 'new link fails') $$,
  'editor A reports the new X1 link');
reset role;
select pg_temp.as_user('97000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok($$ select public.admin_save_assets('97000000-0000-0000-0000-0000000000f1', jsonb_build_array(
  jsonb_build_object('id', '97000000-0000-0000-0000-0000000000a1', 'label', 'X1', 'url', 'https://drive.example.com/x1-v3',
    'provider', 'google_drive'),
  jsonb_build_object('id', '97000000-0000-0000-0000-0000000000a3', 'label', 'X3', 'url', 'https://drive.example.com/x3',
    'provider', 'google_drive'))) $$, 'the admin changes the X1 link while a report is open');
select ok((select access_status = 'inaccessible' and verified_at is null and editor_confirmed_at is null
  from public.project_assets where id = '97000000-0000-0000-0000-0000000000a1'),
  'with an open report the asset stays inaccessible after a link change');

-- ---------------------------------------------------------------------------
-- Removal request and confirmation
-- ---------------------------------------------------------------------------
insert into ids select 'gb', public.admin_record_asset_grant('97000000-0000-0000-0000-0000000000f1',
  '97000000-0000-0000-0000-000000000002', 'b@share.example.com', 'google_drive', null, 'anyone_with_link');
insert into ids select 'ga', public.admin_record_asset_grant('97000000-0000-0000-0000-0000000000f1',
  '97000000-0000-0000-0000-000000000001', 'a@share.example.com', 'google_drive');
select throws_ok($$ select public.admin_confirm_access_removal((select id from ids where kind = 'gb')) $$,
  'ES409', null, 'removal cannot be confirmed before it is requested');
select lives_ok($$ select public.admin_request_access_removal((select id from ids where kind = 'gb')) $$,
  'the admin records the removal request');
select throws_ok($$ select public.admin_request_access_removal((select id from ids where kind = 'gb')) $$,
  'ES409', null, 'removal is requested only once');
select results_eq($$ select access_type::text, removal_requested_at is not null, reason
  from public.admin_pending_revocations() where grant_id = (select id from ids where kind = 'gb') $$,
  $$ values ('anyone_with_link', true, 'no_active_assignment') $$,
  'the checklist shows the access type and the requested state');
select lives_ok($$ select public.admin_confirm_access_removal((select id from ids where kind = 'gb')) $$,
  'the admin confirms the client removed the access');
select ok((select removal_confirmed_at is not null and revoked_at is not null and removal_confirmed_by is not null
  from public.asset_access_grants where id = (select id from ids where kind = 'gb')), 'the share is closed as confirmed');
select throws_ok($$ select public.admin_confirm_access_removal((select id from ids where kind = 'gb')) $$,
  'ES409', null, 'removal is confirmed only once');

-- Ending editor A's assignment never marks their access as removed.
select public.admin_reassign('97000000-0000-0000-0000-0000000000e1', null);
select results_eq($$ select removal_requested_at is null, reason from public.admin_pending_revocations()
  where grant_id = (select id from ids where kind = 'ga') $$,
  $$ values (true, 'no_active_assignment') $$,
  'after the assignment ends the share is on the checklist, removal not requested or confirmed');
reset role;

select pg_temp.as_user('97000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_report_asset_inaccessible('97000000-0000-0000-0000-0000000000a3', 'x') $$,
  'ES403', null, 'an editor whose assignment ended can no longer report');
reset role;

select is_empty($$ select action from public.activity_logs
  where action like 'asset%' and (details::text like '%@%' or details::text like '%https://%'
    or details::text like '%Secretnote%' or details::text like '%Raw camera%') $$,
  'no Phase 12B audit row holds an email, a link or free text');

select * from finish();
rollback;
