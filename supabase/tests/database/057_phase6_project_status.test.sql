-- Phase 6: Phase 4 status changes. open -> draft refused once editors were given access (plan
-- call 16); cancellation from assigned, closing live assignments and revoking access (call 15).
begin;

create extension if not exists pgtap with schema extensions;

select plan(16);

create function pg_temp.as_user(p_uid uuid, p_aal text default 'aal1')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('57000000-0000-0000-0000-00000000000a', 'p6p-admin@test.local', '{}', '{}'),
  ('57000000-0000-0000-0000-000000000001', 'p6p-editor-a@test.local', '{}', '{}'),
  ('57000000-0000-0000-0000-000000000002', 'p6p-editor-b@test.local', '{}', '{}'),
  ('57000000-0000-0000-0000-000000000005', 'p6p-editor-c@test.local', '{}', '{}');
select private.grant_admin_by_email('p6p-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('57000000-0000-0000-0000-000000000001', '57000000-0000-0000-0000-000000000002',
                  '57000000-0000-0000-0000-000000000005');

insert into public.projects (id, title, brief_type, status, first_opened_at) values
  ('57000000-0000-0000-0000-0000000000d0', 'No access', 'fully_instructed', 'open', now()),
  ('57000000-0000-0000-0000-0000000000d1', 'Live access', 'fully_instructed', 'open', now()),
  ('57000000-0000-0000-0000-0000000000d2', 'Revoked access', 'fully_instructed', 'open', now()),
  ('57000000-0000-0000-0000-0000000000d3', 'Declined offer', 'fully_instructed', 'open', now()),
  ('57000000-0000-0000-0000-0000000000a1', 'To cancel when assigned', 'fully_instructed', 'open', now()),
  ('57000000-0000-0000-0000-0000000000a2', 'To cancel when open', 'fully_instructed', 'open', now()),
  ('57000000-0000-0000-0000-0000000000a3', 'Assigned', 'fully_instructed', 'assigned', now());
insert into public.project_access (project_id, editor_id, reason, revoked_at) values
  ('57000000-0000-0000-0000-0000000000d1', '57000000-0000-0000-0000-000000000001', 'invited', null),
  ('57000000-0000-0000-0000-0000000000d2', '57000000-0000-0000-0000-000000000001', 'invited', now());
insert into public.assignments (project_id, editor_id, status, proposed_amount, closed_at) values
  ('57000000-0000-0000-0000-0000000000d3', '57000000-0000-0000-0000-000000000001', 'declined', 100, now());

create temp table ids (kind text primary key, id uuid not null);
grant select, insert on ids to authenticated;
create function pg_temp.a(p_kind text) returns uuid language sql as $$ select id from ids where kind = p_kind $$;
grant execute on function pg_temp.a(text) to authenticated;

-- a1: A confirmed (with a folder share); a2: B offered and C accepted.
select pg_temp.as_user('57000000-0000-0000-0000-00000000000a', 'aal2');
insert into ids select 'a1', public.admin_make_offer('57000000-0000-0000-0000-0000000000a1',
  '57000000-0000-0000-0000-000000000001', 5000);
insert into ids select 'g1', public.admin_record_asset_grant('57000000-0000-0000-0000-0000000000a1',
  '57000000-0000-0000-0000-000000000001', 'a@drive.example.com', 'google_drive');
insert into ids select 'b2', public.admin_make_offer('57000000-0000-0000-0000-0000000000a2',
  '57000000-0000-0000-0000-000000000002', 5000);
insert into ids select 'c2', public.admin_make_offer('57000000-0000-0000-0000-0000000000a2',
  '57000000-0000-0000-0000-000000000005', 5000);
reset role;
update public.assignments set status = 'accepted', agreed_amount = proposed_amount, agreed_currency = currency
where id in (pg_temp.a('a1'), pg_temp.a('c2'));
select pg_temp.as_user('57000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_confirm_assignment(pg_temp.a('a1'));

-- ---------------------------------------------------------------------------
-- open -> draft
-- ---------------------------------------------------------------------------
select lives_ok($$ select public.admin_set_project_status('57000000-0000-0000-0000-0000000000d0', 'draft') $$,
  'open -> draft works when no editor was ever given access');
select throws_ok($$ select public.admin_set_project_status('57000000-0000-0000-0000-0000000000d1', 'draft') $$,
  'ES409', 'Editors have already been given access to this project, so it cannot go back to draft.',
  'open -> draft is refused with a live access row');
select throws_ok($$ select public.admin_set_project_status('57000000-0000-0000-0000-0000000000d2', 'draft') $$,
  'ES409', null, 'open -> draft is refused with only a revoked access row');
select throws_ok($$ select public.admin_set_project_status('57000000-0000-0000-0000-0000000000d3', 'draft') $$,
  'ES409', null, 'open -> draft is refused with only a declined assignment');
select throws_ok($$ select public.admin_set_project_status('57000000-0000-0000-0000-0000000000d1', 'assigned') $$,
  'ES409', null, 'assigned is still refused as a target (only confirmation sets it)');
select lives_ok($$ select public.admin_set_project_status('57000000-0000-0000-0000-0000000000d0', 'cancelled') $$,
  'a draft project can still be cancelled');

-- ---------------------------------------------------------------------------
-- Cancellation from assigned and from open
-- ---------------------------------------------------------------------------
select lives_ok($$ select public.admin_set_project_status('57000000-0000-0000-0000-0000000000a1', 'cancelled') $$,
  'an assigned project can be cancelled');
select ok((select status = 'cancelled' from public.projects where id = '57000000-0000-0000-0000-0000000000a1')
  and (select status = 'withdrawn' and closed_at is not null from public.assignments where id = pg_temp.a('a1')),
  'the confirmed assignment is withdrawn and closed');
select ok(exists (select 1 from public.negotiation_offers where assignment_id = pg_temp.a('a1')
  and from_role = 'admin' and action = 'withdraw' and message is null),
  'an admin withdraw row is recorded for the confirmed editor');
select is((select count(*)::int from public.project_access where project_id = '57000000-0000-0000-0000-0000000000a1'
  and revoked_at is null), 0, 'the confirmed editor''s access is revoked');
select is((select reason from public.admin_pending_revocations() where grant_id = pg_temp.a('g1')), 'project_closed',
  'the editor''s folder share appears on the revoke checklist');
reset role;
select pg_temp.as_user('57000000-0000-0000-0000-000000000001');
select is(private.editor_project_stage('57000000-0000-0000-0000-0000000000a1'), 'none',
  'the cancelled project is no longer visible to the editor');
reset role;

select pg_temp.as_user('57000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok($$ select public.admin_set_project_status('57000000-0000-0000-0000-0000000000a2', 'cancelled') $$,
  'an open project with live offers can be cancelled');
select ok((select bool_and(status = 'withdrawn' and closed_at is not null) from public.assignments
  where id in (pg_temp.a('b2'), pg_temp.a('c2'))), 'the offered and accepted rows are withdrawn');
select is((select count(*)::int from public.project_access where project_id = '57000000-0000-0000-0000-0000000000a2'
  and revoked_at is null), 0, 'every access row is revoked');
select throws_ok($$ select public.admin_set_project_status('57000000-0000-0000-0000-0000000000a3', 'on_hold') $$,
  'ES409', null, 'an assigned project still cannot be put on hold');
reset role;

select * from finish();

rollback;
