-- Phase 4: projects, briefs and clients schema. Admin-only reads, no direct writes for anyone,
-- guard triggers on first opening and brief versions, status audit trigger.
begin;

create extension if not exists pgtap with schema extensions;

select plan(65);

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

-- Row counts of all six tables for the current identity.
create function pg_temp.visible_counts()
returns int[] language sql as $$
  select array[
    (select count(*)::int from public.clients),
    (select count(*)::int from public.projects),
    (select count(*)::int from public.project_internal),
    (select count(*)::int from public.brief_versions),
    (select count(*)::int from public.project_deliverables),
    (select count(*)::int from public.project_references)];
$$;
grant execute on function pg_temp.visible_counts() to authenticated;

-- ---------------------------------------------------------------------------
-- Fixtures (as postgres): one row per table
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('40000000-0000-0000-0000-00000000000a', 'p4s-admin@test.local', '{}', '{}'),
  ('40000000-0000-0000-0000-000000000001', 'p4s-editor-a@test.local', '{}', '{}'),
  ('40000000-0000-0000-0000-000000000002', 'p4s-editor-b@test.local', '{}', '{}'),
  ('40000000-0000-0000-0000-000000000003', 'p4s-applicant@test.local', '{}', '{}');
select private.grant_admin_by_email('p4s-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('40000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000002');

insert into public.clients (id, name, email)
values ('40000000-0000-0000-0000-0000000000c1', 'Seed Client', 'seed@example.com');
insert into public.projects (id, title, brief_type)
values ('40000000-0000-0000-0000-0000000000f1', 'Seed project', 'fully_instructed');
insert into public.project_internal (project_id, client_id, client_price)
values ('40000000-0000-0000-0000-0000000000f1', '40000000-0000-0000-0000-0000000000c1', 1000);
insert into public.brief_versions (project_id, version, instructions)
values ('40000000-0000-0000-0000-0000000000f1', 1, 'Cut to the beat.');
insert into public.project_deliverables (project_id, name)
values ('40000000-0000-0000-0000-0000000000f1', 'Main edit');
insert into public.project_references (project_id, url, start_seconds, end_seconds)
values ('40000000-0000-0000-0000-0000000000f1', 'https://example.com/ref', 10, 20);

-- ---------------------------------------------------------------------------
-- Anonymous: no access at all
-- ---------------------------------------------------------------------------
select pg_temp.as_anon();
select throws_ok($$ select 1 from public.clients $$, '42501', null, 'anon cannot read clients');
select throws_ok($$ select 1 from public.projects $$, '42501', null, 'anon cannot read projects');
select throws_ok($$ select 1 from public.project_internal $$, '42501', null, 'anon cannot read project_internal');
select throws_ok($$ select 1 from public.brief_versions $$, '42501', null, 'anon cannot read brief_versions');
select throws_ok($$ select 1 from public.project_deliverables $$, '42501', null, 'anon cannot read project_deliverables');
select throws_ok($$ select 1 from public.project_references $$, '42501', null, 'anon cannot read project_references');
select throws_ok($$ insert into public.projects (title, brief_type) values ('x', 'creative_led') $$,
  '42501', null, 'anon cannot insert projects');
reset role;

-- ---------------------------------------------------------------------------
-- Signed-in non-admins see nothing
-- ---------------------------------------------------------------------------
select pg_temp.as_user('40000000-0000-0000-0000-000000000001');
select is(pg_temp.visible_counts(), array[0,0,0,0,0,0], 'editor A sees no rows in any Phase 4 table');
select throws_ok($$ insert into public.projects (title, brief_type) values ('x', 'creative_led') $$,
  '42501', null, 'editor A cannot insert projects');
select throws_ok($$ update public.projects set title = 'x' $$, '42501', null, 'editor A cannot update projects');
reset role;

select pg_temp.as_user('40000000-0000-0000-0000-000000000002');
select is(pg_temp.visible_counts(), array[0,0,0,0,0,0], 'editor B sees no rows in any Phase 4 table');
reset role;

select pg_temp.as_user('40000000-0000-0000-0000-000000000003');
select is(pg_temp.visible_counts(), array[0,0,0,0,0,0], 'a pending applicant sees no rows in any Phase 4 table');
select throws_ok($$ delete from public.clients $$, '42501', null, 'an applicant cannot delete clients');
reset role;

-- Admin without MFA.
select pg_temp.as_user('40000000-0000-0000-0000-00000000000a', 'aal1');
select is(pg_temp.visible_counts(), array[0,0,0,0,0,0], 'admin without MFA sees no rows');
reset role;

-- ---------------------------------------------------------------------------
-- Admin with MFA: reads everything, writes nothing directly
-- ---------------------------------------------------------------------------
select pg_temp.as_user('40000000-0000-0000-0000-00000000000a', 'aal2');
select is(pg_temp.visible_counts(), array[1,1,1,1,1,1], 'admin with MFA sees the seeded row in every table');

select throws_ok($$ insert into public.clients (name, email) values ('X', 'x@example.com') $$,
  '42501', null, 'admin cannot insert clients directly');
select throws_ok($$ update public.clients set name = 'X' $$, '42501', null, 'admin cannot update clients directly');
select throws_ok($$ delete from public.clients $$, '42501', null, 'admin cannot delete clients directly');

select throws_ok($$ insert into public.projects (title, brief_type) values ('X', 'creative_led') $$,
  '42501', null, 'admin cannot insert projects directly');
select throws_ok($$ update public.projects set title = 'X' $$, '42501', null, 'admin cannot update projects directly');
select throws_ok($$ delete from public.projects $$, '42501', null, 'admin cannot delete projects directly');

select throws_ok($$ insert into public.project_internal (project_id) values ('40000000-0000-0000-0000-0000000000f1') $$,
  '42501', null, 'admin cannot insert project_internal directly');
select throws_ok($$ update public.project_internal set client_price = 1 $$, '42501', null,
  'admin cannot update project_internal directly');
select throws_ok($$ delete from public.project_internal $$, '42501', null, 'admin cannot delete project_internal directly');

select throws_ok($$ insert into public.brief_versions (project_id, version) values ('40000000-0000-0000-0000-0000000000f1', 2) $$,
  '42501', null, 'admin cannot insert brief_versions directly');
select throws_ok($$ update public.brief_versions set instructions = 'X' $$, '42501', null,
  'admin cannot update brief_versions directly');
select throws_ok($$ delete from public.brief_versions $$, '42501', null, 'admin cannot delete brief_versions directly');

select throws_ok($$ insert into public.project_deliverables (project_id, name) values ('40000000-0000-0000-0000-0000000000f1', 'X') $$,
  '42501', null, 'admin cannot insert project_deliverables directly');
select throws_ok($$ update public.project_deliverables set name = 'X' $$, '42501', null,
  'admin cannot update project_deliverables directly');
select throws_ok($$ delete from public.project_deliverables $$, '42501', null,
  'admin cannot delete project_deliverables directly');

select throws_ok($$ insert into public.project_references (project_id, url) values ('40000000-0000-0000-0000-0000000000f1', 'https://e.com') $$,
  '42501', null, 'admin cannot insert project_references directly');
select throws_ok($$ update public.project_references set title = 'X' $$, '42501', null,
  'admin cannot update project_references directly');
select throws_ok($$ delete from public.project_references $$, '42501', null,
  'admin cannot delete project_references directly');
reset role;

-- ---------------------------------------------------------------------------
-- Guard triggers (as postgres: they hold even for the table owner)
-- ---------------------------------------------------------------------------
select lives_ok($$ update public.brief_versions set instructions = 'Edited before opening'
  where project_id = '40000000-0000-0000-0000-0000000000f1' $$,
  'brief version 1 can be edited while the project has never been opened');
select throws_ok($$ delete from public.brief_versions where project_id = '40000000-0000-0000-0000-0000000000f1' $$,
  'ES409', null, 'brief versions can never be deleted, even before opening');

select lives_ok($$ update public.projects set first_opened_at = now()
  where id = '40000000-0000-0000-0000-0000000000f1' $$, 'first_opened_at can be set from null');
select throws_ok($$ update public.projects set first_opened_at = now() + interval '1 day'
  where id = '40000000-0000-0000-0000-0000000000f1' $$,
  'ES409', null, 'first_opened_at cannot be changed once set');
select throws_ok($$ update public.projects set first_opened_at = null
  where id = '40000000-0000-0000-0000-0000000000f1' $$,
  'ES409', null, 'first_opened_at cannot be cleared once set');
select lives_ok($$ update public.projects set title = 'Renamed'
  where id = '40000000-0000-0000-0000-0000000000f1' $$,
  'other project columns stay editable after opening');

select throws_ok($$ update public.brief_versions set instructions = 'Edited after opening'
  where project_id = '40000000-0000-0000-0000-0000000000f1' $$,
  'ES409', null, 'brief versions cannot be updated once the project has been opened');
select throws_ok($$ delete from public.brief_versions where project_id = '40000000-0000-0000-0000-0000000000f1' $$,
  'ES409', null, 'brief versions cannot be deleted after opening');
select is((select instructions from public.brief_versions where project_id = '40000000-0000-0000-0000-0000000000f1'),
  'Edited before opening', 'the opened version is unchanged');

-- Clients: normalised, unique among unmerged.
select throws_ok($$ insert into public.clients (name, email) values ('Pad', ' A@B.com') $$,
  '23514', null, 'client email must be stored lower-cased and trimmed');
select throws_ok($$ insert into public.clients (name, email) values ('Dup', 'seed@example.com') $$,
  '23505', null, 'a second unmerged client with the same email is refused');
insert into public.clients (id, name, email)
values ('40000000-0000-0000-0000-0000000000c2', 'Target Client', 'target@example.com');
update public.clients set merged_into_id = '40000000-0000-0000-0000-0000000000c2'
where id = '40000000-0000-0000-0000-0000000000c1';
select lives_ok($$ insert into public.clients (name, email) values ('New owner', 'seed@example.com') $$,
  'a merged client frees its email for a new client');
select throws_ok($$ update public.clients set merged_into_id = id where id = '40000000-0000-0000-0000-0000000000c2' $$,
  '23514', null, 'a client cannot be merged into itself');

-- Archived clients stay in the unique index.
insert into public.clients (name, email, archived_at) values ('Archived', 'arch@example.com', now());
select throws_ok($$ insert into public.clients (name, email) values ('Arch dup', 'arch@example.com') $$,
  '23505', null, 'an archived client still blocks a duplicate email');

-- References: https only, end >= start.
select throws_ok($$ insert into public.project_references (project_id, url, start_seconds, end_seconds)
  values ('40000000-0000-0000-0000-0000000000f1', 'https://e.com', 20, 10) $$,
  '23514', null, 'reference end before start is refused');
select throws_ok($$ insert into public.project_references (project_id, url)
  values ('40000000-0000-0000-0000-0000000000f1', 'http://e.com') $$,
  '23514', null, 'reference URLs must be https');
select throws_ok($$ insert into public.project_references (project_id, url, start_seconds)
  values ('40000000-0000-0000-0000-0000000000f1', 'https://e.com', -1) $$,
  '23514', null, 'negative timecodes are refused');

-- Money and other checks.
select throws_ok($$ insert into public.projects (title, brief_type, proposed_currency) values ('X', 'creative_led', 'lkr') $$,
  '23514', null, 'currency must be three upper-case letters');
select throws_ok($$ insert into public.projects (title, brief_type, revision_allowance) values ('X', 'creative_led', 21) $$,
  '23514', null, 'revision allowance is at most 20');
select throws_ok($$ insert into public.projects (title, brief_type) values ('', 'creative_led') $$,
  '23514', null, 'project title cannot be empty');
select throws_ok($$ insert into public.projects (title, brief_type, proposed_amount) values ('X', 'creative_led', -1) $$,
  '23514', null, 'proposed amount cannot be negative');
select throws_ok($$ insert into public.brief_versions (project_id, version, instructions)
  values ('40000000-0000-0000-0000-0000000000f1', 1, 'dup') $$,
  '23505', null, 'brief version numbers are unique per project');
select throws_ok($$ insert into public.projects (title, brief_type, status) values ('X', 'creative_led', 'on_hold') $$,
  '23514', null, 'on_hold requires status_before_hold');

-- Defaults.
select is((select revision_allowance from public.projects where id = '40000000-0000-0000-0000-0000000000f1'),
  3::smallint, 'revision allowance defaults to 3');
select is((select status from public.projects where id = '40000000-0000-0000-0000-0000000000f1'),
  'draft'::public.project_status, 'projects start as draft');
select is((select proposed_currency from public.projects where id = '40000000-0000-0000-0000-0000000000f1'),
  'LKR', 'currency defaults to LKR');

-- Status audit trigger.
select is((select count(*)::int from public.activity_logs
  where entity_type = 'project' and entity_id = '40000000-0000-0000-0000-0000000000f1' and action = 'project.created'),
  1, 'creating a project writes one project.created audit row');
update public.projects set status = 'open' where id = '40000000-0000-0000-0000-0000000000f1';
select is((select count(*)::int from public.activity_logs
  where entity_type = 'project' and entity_id = '40000000-0000-0000-0000-0000000000f1' and action = 'project.open'),
  1, 'changing status writes a project.open audit row');
update public.projects set title = 'Again' where id = '40000000-0000-0000-0000-0000000000f1';
select is((select count(*)::int from public.activity_logs
  where entity_type = 'project' and entity_id = '40000000-0000-0000-0000-0000000000f1'),
  2, 'non-status updates are not audited by the trigger');
select is((select details from public.activity_logs
  where entity_type = 'project' and entity_id = '40000000-0000-0000-0000-0000000000f1' and action = 'project.open'),
  '{"from": "draft", "to": "open"}'::jsonb, 'status audit details hold status names only');

-- Trigger functions are not reachable by API roles.
select ok(not has_function_privilege('authenticated', 'private.guard_brief_versions()', 'execute'),
  'guard_brief_versions is not executable by authenticated');
select ok(not has_function_privilege('anon', 'private.audit_projects()', 'execute'),
  'audit_projects is not executable by anon');

select * from finish();

rollback;
