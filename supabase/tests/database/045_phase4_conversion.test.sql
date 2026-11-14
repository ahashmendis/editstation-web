-- Phase 4: clients and atomic inquiry conversion (spec §5, §9, §14). Review Focus 6 and 7.
begin;

create extension if not exists pgtap with schema extensions;

select plan(62);

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

-- Inquiry fixture, inserted as postgres.
create function pg_temp.inquiry(p_id uuid, p_email text, p_status public.inquiry_status,
  p_company text default null, p_name text default 'Asha Perera')
returns void language sql as $$
  insert into public.client_inquiries (id, contact_name, company, email, phone, service_type_code,
    service_type_label, description, budget_label, expected_deadline, privacy_notice_version, status)
  values (p_id, p_name, p_company, p_email, '+94 77 000 0000', 'long_form', 'Long-form video',
    'A brand film for our launch.', 'LKR 100,000 - 200,000', '2026-12-31', 'v', p_status);
$$;

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('45000000-0000-0000-0000-00000000000a', 'p4v-admin@test.local', '{}', '{}'),
  ('45000000-0000-0000-0000-000000000001', 'p4v-editor-a@test.local', '{}', '{}'),
  ('45000000-0000-0000-0000-000000000002', 'p4v-editor-b@test.local', '{}', '{}'),
  ('45000000-0000-0000-0000-000000000003', 'p4v-applicant@test.local', '{}', '{}');
select private.grant_admin_by_email('p4v-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('45000000-0000-0000-0000-000000000001', '45000000-0000-0000-0000-000000000002');

select pg_temp.inquiry('45000000-0000-0000-0000-0000000000e1', 'Asha@Example.COM', 'reviewing', 'Lanka Agency');
select pg_temp.inquiry('45000000-0000-0000-0000-0000000000e2', 'ravi@example.com', 'new', null, 'Ravi Silva');
select pg_temp.inquiry('45000000-0000-0000-0000-0000000000e3', 'd@example.com', 'declined');
select pg_temp.inquiry('45000000-0000-0000-0000-0000000000e4', 'c@example.com', 'closed');
select pg_temp.inquiry('45000000-0000-0000-0000-0000000000e5', 's@example.com', 'spam');
select pg_temp.inquiry('45000000-0000-0000-0000-0000000000e6', 'arch@example.com', 'contacted');
select pg_temp.inquiry('45000000-0000-0000-0000-0000000000e7', 'fail@example.com', 'reviewing');
select pg_temp.inquiry('45000000-0000-0000-0000-0000000000e8', 'other@example.com', 'in_discussion');

insert into public.clients (id, name, email, archived_at) values
  ('45000000-0000-0000-0000-0000000000c4', 'Archived Client', 'arch@example.com', now());

create temp table ids (kind text primary key, id uuid not null);
grant select, insert on ids to authenticated, anon;
create temp table counts as select
  (select count(*) from public.clients) as clients,
  (select count(*) from public.projects) as projects;
grant select, update on counts to authenticated;

-- ---------------------------------------------------------------------------
-- Clients
-- ---------------------------------------------------------------------------
select pg_temp.as_user('45000000-0000-0000-0000-00000000000a', 'aal2');

select lives_ok($$ insert into ids select 'asha', public.admin_create_client(
  '{"name": "Asha Perera", "company": "Lanka Agency", "email": "asha@example.com", "phone": "+94 77"}') $$,
  'admin creates a client');
select throws_ok($$ select public.admin_create_client('{"name": "Asha again", "email": "  ASHA@Example.com "}') $$,
  'ES409', null, 'a padded, mixed-case duplicate email is refused');
select lives_ok($$ insert into ids select 'mixed', public.admin_create_client('{"name": "Mixed", "email": " Mixed@Example.COM "}') $$,
  'a padded, mixed-case email is accepted for a new client');
select is((select email from public.clients where id = (select id from ids where kind = 'mixed')),
  'mixed@example.com', 'client email is stored as lower(btrim(email))');
select throws_ok($$ select public.admin_create_client('{"email": "noname@example.com"}') $$,
  'ES422', null, 'a client needs a name');
select throws_ok($$ select public.admin_create_client('{"name": "Bad", "email": "not-an-email"}') $$,
  'ES422', null, 'a client needs a valid email');
select throws_ok($$ select public.admin_create_client(null) $$, 'ES422', null, 'null client input is refused');

update counts set clients = (select count(*) from public.clients), projects = (select count(*) from public.projects);

-- ---------------------------------------------------------------------------
-- Conversion: happy path, reusing the client (Review Focus 7)
-- ---------------------------------------------------------------------------
select lives_ok($$ insert into ids select 'p1', public.admin_convert_inquiry('45000000-0000-0000-0000-0000000000e1',
  '{"brief_type": "creative_led"}') $$, 'admin converts an inquiry');
select is((select count(*) from public.clients), (select clients from counts),
  'a mixed-case inquiry email reuses the existing client');
select is((select count(*) from public.projects), (select projects from counts) + 1, 'exactly one project is created');
select ok((select client_id = (select id from ids where kind = 'asha')
  and source_inquiry_id = '45000000-0000-0000-0000-0000000000e1' and client_price is null
  from public.project_internal where project_id = (select id from ids where kind = 'p1')),
  'project_internal links the client and the source inquiry, with no client price copied');
select is((select count(*)::int from public.brief_versions where project_id = (select id from ids where kind = 'p1')),
  1, 'brief version 1 is created');
select ok((select status = 'converted' and converted_project_id = (select id from ids where kind = 'p1')
  and status_changed_by = '45000000-0000-0000-0000-00000000000a' and status_changed_at is not null
  from public.client_inquiries where id = '45000000-0000-0000-0000-0000000000e1'),
  'the inquiry is converted and linked to the project');
select ok((select title = 'Long-form video' and service_type_code = 'long_form'
  and deadline = '2026-12-31' and summary = 'A brand film for our launch.' and status = 'draft'
  from public.projects where id = (select id from ids where kind = 'p1')),
  'the project is prefilled from the inquiry');
select is((select count(*)::int from public.activity_logs where action = 'inquiry.converted'
  and entity_id = '45000000-0000-0000-0000-0000000000e1'), 1, 'the conversion is audited');
select is((select count(*)::int from public.activity_logs where action = 'project.created'
  and entity_id = (select id from ids where kind = 'p1')::text), 1, 'the project creation is audited');

select throws_ok($$ select public.admin_convert_inquiry('45000000-0000-0000-0000-0000000000e1', '{"brief_type": "creative_led"}') $$,
  'ES409', null, 'a converted inquiry cannot be converted again');
select throws_ok($$ select public.admin_set_inquiry_status('45000000-0000-0000-0000-0000000000e1', 'reviewing') $$,
  'ES409', null, 'a converted inquiry never leaves converted');

-- New client created from the inquiry; title from the service type only; p_input overrides.
select lives_ok($$ insert into ids select 'p2', public.admin_convert_inquiry('45000000-0000-0000-0000-0000000000e2',
  '{"brief_type": "fully_instructed", "summary": "Admin summary", "client_price": 120000}') $$,
  'admin converts an inquiry from a new email');
select is((select count(*) from public.clients), (select clients from counts) + 1, 'one new client is created');
select ok((select name = 'Ravi Silva' and email = 'ravi@example.com' and phone = '+94 77 000 0000' and company is null
  from public.clients where email = 'ravi@example.com'), 'the new client is filled from the inquiry contact fields');
select ok((select title = 'Long-form video' and summary = 'Admin summary'
  from public.projects where id = (select id from ids where kind = 'p2')),
  'the default title is the service type alone and input overrides the defaults');
select is((select count(*)::int from public.projects pr
  join public.project_internal pi on pi.project_id = pr.id
  join public.client_inquiries ci on ci.id = pi.source_inquiry_id
  where pr.id in ((select id from ids where kind = 'p1'), (select id from ids where kind = 'p2'))
    and (pr.title ilike '%' || ci.contact_name || '%'
         or (ci.company is not null and pr.title ilike '%' || ci.company || '%'))), 0,
  'a converted project''s default title holds neither the inquiry company nor contact name');
select is((select client_price from public.project_internal where project_id = (select id from ids where kind = 'p2')),
  120000.00::numeric, 'a client price given by the admin is stored');

-- Refused inquiry states.
select throws_ok($$ select public.admin_convert_inquiry('45000000-0000-0000-0000-0000000000e3', '{"brief_type": "creative_led"}') $$,
  'ES409', null, 'a declined inquiry must be reopened first');
select throws_ok($$ select public.admin_convert_inquiry('45000000-0000-0000-0000-0000000000e4', '{"brief_type": "creative_led"}') $$,
  'ES409', null, 'a closed inquiry must be reopened first');
select throws_ok($$ select public.admin_convert_inquiry('45000000-0000-0000-0000-0000000000e5', '{"brief_type": "creative_led"}') $$,
  'ES409', null, 'a spam inquiry must be reopened first');
select throws_ok($$ select public.admin_convert_inquiry('45000000-0000-0000-0000-0000000000ff', '{"brief_type": "creative_led"}') $$,
  'ES422', null, 'an unknown inquiry is refused');
select throws_ok($$ select public.admin_convert_inquiry('45000000-0000-0000-0000-0000000000e7', '[]') $$,
  'ES422', null, 'non-object input is refused');

update counts set clients = (select count(*) from public.clients), projects = (select count(*) from public.projects);

-- Archived matching client: refused, nothing created.
select throws_ok($$ select public.admin_convert_inquiry('45000000-0000-0000-0000-0000000000e6', '{"brief_type": "creative_led"}') $$,
  'ES409', 'This client is archived. Restore it first.', 'an archived matching client blocks conversion');
select ok((select count(*) from public.projects) = (select projects from counts)
  and (select status from public.client_inquiries where id = '45000000-0000-0000-0000-0000000000e6') = 'contacted',
  'the refused conversion created nothing and left the inquiry unchanged');

-- Forced failure after the client insert: everything rolls back.
select throws_ok($$ select public.admin_convert_inquiry('45000000-0000-0000-0000-0000000000e7',
  '{"brief_type": "creative_led", "deliverables": [{"format": "MP4"}]}') $$,
  'ES422', null, 'an invalid deliverable fails the conversion');
select is((select count(*)::int from public.clients where email = 'fail@example.com'), 0,
  'the client created during the failed conversion is rolled back');
select is((select count(*) from public.projects), (select projects from counts), 'no project remains after the failure');
select is((select status from public.client_inquiries where id = '45000000-0000-0000-0000-0000000000e7'),
  'reviewing'::public.inquiry_status, 'the inquiry is unchanged after the failure');
select throws_ok($$ select public.admin_convert_inquiry('45000000-0000-0000-0000-0000000000e7', '{}') $$,
  'ES422', null, 'a brief type is required to convert');
select is((select count(*)::int from public.clients where email = 'fail@example.com'), 0,
  'still no client after a missing brief type');

-- Explicit client instead of matching.
select lives_ok($$ insert into ids select 'p3', public.admin_convert_inquiry('45000000-0000-0000-0000-0000000000e8',
  jsonb_build_object('brief_type', 'creative_led', 'client_id', (select id from ids where kind = 'asha'), 'title', 'Custom title')) $$,
  'admin converts an inquiry onto an existing client');
select ok((select client_id = (select id from ids where kind = 'asha') from public.project_internal
  where project_id = (select id from ids where kind = 'p3'))
  and not exists (select 1 from public.clients where email = 'other@example.com')
  and (select title from public.projects where id = (select id from ids where kind = 'p3')) = 'Custom title',
  'the given client is used and no client is created from the inquiry email');
reset role;

-- Review Focus 6: the conversion serialises on the inquiry row, and the unique index is the
-- last line of defence (pgTAP cannot open two sessions).
select ok((select prosrc ~* 'from\s+public\.client_inquiries\s+where\s+id\s*=\s*p_inquiry_id\s+for\s+update'
  from pg_proc where oid = 'public.admin_convert_inquiry(uuid, jsonb)'::regprocedure),
  'admin_convert_inquiry locks the inquiry row with for update');
insert into public.projects (id, title, brief_type) values ('45000000-0000-0000-0000-0000000000f9', 'Dup', 'creative_led');
select throws_ok($$ insert into public.project_internal (project_id, source_inquiry_id)
  values ('45000000-0000-0000-0000-0000000000f9', '45000000-0000-0000-0000-0000000000e1') $$,
  '23505', null, 'a second project for the same inquiry is rejected by the unique index');

-- ---------------------------------------------------------------------------
-- Update, restore, merge
-- ---------------------------------------------------------------------------
select pg_temp.as_user('45000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_update_client((select id from ids where kind = 'mixed'), '{"email": "ASHA@example.com"}') $$,
  'ES409', null, 'changing an email to one already in use is refused');
select lives_ok($$ select public.admin_update_client('45000000-0000-0000-0000-0000000000c4', '{"archived": false}') $$,
  'admin restores an archived client');
select ok((select archived_at is null from public.clients where id = '45000000-0000-0000-0000-0000000000c4'),
  'the client is no longer archived');
select lives_ok($$ select public.admin_convert_inquiry('45000000-0000-0000-0000-0000000000e6', '{"brief_type": "creative_led"}') $$,
  'conversion succeeds once the client is restored');
select lives_ok($$ select public.admin_update_client((select id from ids where kind = 'mixed'),
  '{"name": "Mixed Media", "phone": null, "archived": true}') $$, 'admin edits and archives a client');
select ok((select name = 'Mixed Media' and phone is null and archived_at is not null
  from public.clients where id = (select id from ids where kind = 'mixed')), 'client edits are stored');

-- Merge: 'ravi' (source, has project p2) into 'asha' (target).
select throws_ok($$ select public.admin_merge_clients((select id from ids where kind = 'asha'), (select id from ids where kind = 'asha')) $$,
  'ES422', null, 'a client cannot be merged into itself');
select throws_ok($$ select public.admin_merge_clients((select id from public.clients where email = 'ravi@example.com'), (select id from ids where kind = 'mixed')) $$,
  'ES409', null, 'an archived client cannot be a merge target');
select lives_ok($$ select public.admin_merge_clients((select id from public.clients where email = 'ravi@example.com'), (select id from ids where kind = 'asha')) $$,
  'admin merges two clients');
select is((select client_id from public.project_internal where project_id = (select id from ids where kind = 'p2')),
  (select id from ids where kind = 'asha'), 'the merge repoints the source''s projects to the target');
select is((select merged_into_id from public.clients where email = 'ravi@example.com'),
  (select id from ids where kind = 'asha'), 'the source records its merge target');
select throws_ok($$ select public.admin_merge_clients((select id from ids where kind = 'mixed'), (select id from public.clients where email = 'ravi@example.com')) $$,
  'ES409', null, 'a merged client cannot be a merge target');
select throws_ok($$ select public.admin_update_client((select id from public.clients where email = 'ravi@example.com'), '{"name": "X"}') $$,
  'ES409', null, 'a merged client cannot be edited');
select lives_ok($$ select public.admin_create_client('{"name": "New Ravi", "email": "ravi@example.com"}') $$,
  'a merged client''s email can belong to a new client');
select is((select count(*)::int from public.activity_logs where action = 'client.merged'), 1, 'the merge is audited');
select ok((select bool_and(details::text not like '%@%' and not (details ? 'name'))
  from public.activity_logs where action = 'client.merged'), 'the merge audit row holds no personal data');
reset role;

-- ---------------------------------------------------------------------------
-- Non-admin identities
-- ---------------------------------------------------------------------------
create function pg_temp.denied_for(p_code text)
returns int language plpgsql as $$
declare
  v_denied int := 0;
  v_client uuid := (select id from ids where kind = 'asha');
begin
  begin perform public.admin_create_client('{"name": "X", "email": "x@example.com"}');
  exception when others then if sqlstate = p_code then v_denied := v_denied + 1; end if; end;
  begin perform public.admin_update_client(v_client, '{"name": "X"}');
  exception when others then if sqlstate = p_code then v_denied := v_denied + 1; end if; end;
  begin perform public.admin_merge_clients(v_client, v_client);
  exception when others then if sqlstate = p_code then v_denied := v_denied + 1; end if; end;
  begin perform public.admin_convert_inquiry('45000000-0000-0000-0000-0000000000e7', '{"brief_type": "creative_led"}');
  exception when others then if sqlstate = p_code then v_denied := v_denied + 1; end if; end;
  return v_denied;
end;
$$;

select pg_temp.as_anon();
select is(pg_temp.denied_for('ES401'), 4, 'anon is refused by all four client and conversion functions');
reset role;
select pg_temp.as_user('45000000-0000-0000-0000-00000000000a', 'aal1');
select is(pg_temp.denied_for('ES403'), 4, 'admin without MFA is refused by all four functions');
reset role;
select pg_temp.as_user('45000000-0000-0000-0000-000000000001');
select is(pg_temp.denied_for('ES403'), 4, 'editor A is refused by all four functions');
reset role;
select pg_temp.as_user('45000000-0000-0000-0000-000000000002');
select is(pg_temp.denied_for('ES403'), 4, 'editor B is refused by all four functions');
reset role;
select pg_temp.as_user('45000000-0000-0000-0000-000000000003');
select is(pg_temp.denied_for('ES403'), 4, 'an applicant is refused by all four functions');
reset role;

select * from finish();

rollback;
