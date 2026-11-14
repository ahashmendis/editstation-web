-- Phase 4: brief helpers and admin_create_project. Review Focus 1-3.
begin;

create extension if not exists pgtap with schema extensions;

select plan(67);

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
-- Fixtures
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('42000000-0000-0000-0000-00000000000a', 'p4c-admin@test.local', '{}', '{}'),
  ('42000000-0000-0000-0000-000000000001', 'p4c-editor-a@test.local', '{}', '{}'),
  ('42000000-0000-0000-0000-000000000002', 'p4c-editor-b@test.local', '{}', '{}'),
  ('42000000-0000-0000-0000-000000000003', 'p4c-applicant@test.local', '{}', '{}');
select private.grant_admin_by_email('p4c-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('42000000-0000-0000-0000-000000000001', '42000000-0000-0000-0000-000000000002');

insert into public.clients (id, name, email) values
  ('42000000-0000-0000-0000-0000000000c1', 'Good Client', 'good@example.com'),
  ('42000000-0000-0000-0000-0000000000c2', 'Merge Target', 'target@example.com');
insert into public.clients (id, name, email, merged_into_id) values
  ('42000000-0000-0000-0000-0000000000c3', 'Merged Client', 'merged@example.com', '42000000-0000-0000-0000-0000000000c2');
insert into public.clients (id, name, email, archived_at) values
  ('42000000-0000-0000-0000-0000000000c4', 'Archived Client', 'archived@example.com', now());

-- An unrelated project whose deliverable id must not be accepted elsewhere.
insert into public.projects (id, title, brief_type) values ('42000000-0000-0000-0000-0000000000f9', 'Other', 'creative_led');
insert into public.project_deliverables (id, project_id, name)
values ('42000000-0000-0000-0000-0000000000d9', '42000000-0000-0000-0000-0000000000f9', 'Foreign');

create temp table made (kind text primary key, id uuid not null);
grant select, insert on made to authenticated;

-- A valid minimal input to vary in the validation tests.
create function pg_temp.base(p_extra jsonb default '{}')
returns jsonb language sql as $$
  select '{"title":"Valid","brief_type":"creative_led"}'::jsonb || p_extra;
$$;

-- ---------------------------------------------------------------------------
-- Admin with MFA: one project of each brief type
-- ---------------------------------------------------------------------------
select pg_temp.as_user('42000000-0000-0000-0000-00000000000a', 'aal2');

select lives_ok($$
  insert into made select 'fi', public.admin_create_project('{
    "title": "  Launch reel  ", "brief_type": "fully_instructed", "service_type_code": "short_form_social",
    "summary": "Ten reels", "deadline": "2026-12-31", "proposed_amount": 15000, "proposed_currency": "LKR",
    "client_id": "42000000-0000-0000-0000-0000000000c1", "client_price": 50000, "internal_notes": "VIP",
    "brief": {"instructions": "  Cut to the beat.  ", "audience": ""},
    "deliverables": [
      {"name": " Main edit ", "format": "MP4", "resolution": "1080x1920", "aspect_ratio": "9:16", "duration_seconds": 30},
      {"name": "Cutdown", "duration_seconds": 15}],
    "references": []}'::jsonb)
$$, 'admin creates a fully instructed project');

select lives_ok($$
  insert into made select 'rb', public.admin_create_project('{
    "title": "Reference job", "brief_type": "reference_based", "deadline": "2026-12-01",
    "deliverables": [{"name": "Main edit"}],
    "references": [{"title": "Pacing", "url": "https://example.com/a", "start_seconds": 5, "end_seconds": 12,
                    "priority": "essential", "category": "pacing", "observation_notes": "Fast cuts"}]}'::jsonb)
$$, 'admin creates a reference-based project');

select lives_ok($$
  insert into made select 'cl', public.admin_create_project('{
    "title": "Creative job", "brief_type": "creative_led",
    "brief": {"desired_outcome": "Make people feel at home", "audience": "Families", "core_message": "Comfort"}}'::jsonb)
$$, 'admin creates a creative-led project with no client');

select is((select count(*)::int from public.project_deliverables where project_id = (select id from made where kind = 'fi')),
  2, 'deliverables are stored');
select is((select count(*)::int from public.project_references where project_id = (select id from made where kind = 'rb')),
  1, 'references are stored');
select is((select count(*)::int from public.brief_versions where project_id in (select id from made) and version = 1),
  3, 'each project has brief version 1');
select is((select title from public.projects where id = (select id from made where kind = 'fi')),
  'Launch reel', 'title is trimmed');
select is((select instructions from public.brief_versions where project_id = (select id from made where kind = 'fi')),
  'Cut to the beat.', 'instructions are trimmed');
select is((select audience from public.brief_versions where project_id = (select id from made where kind = 'fi')),
  null, 'empty brief fields are stored as null');
select is((select name from public.project_deliverables where project_id = (select id from made where kind = 'fi') order by sort_order limit 1),
  'Main edit', 'deliverable names are trimmed');
select is((select array_agg(requires_interpretation order by kind) from public.projects p join made m on m.id = p.id),
  array[true, false, true], 'requires_interpretation defaults by brief type (cl, fi, rb)');
select ok((select bool_and(status = 'draft' and current_brief_version = 1
  and created_by = '42000000-0000-0000-0000-00000000000a') from public.projects where id in (select id from made)),
  'projects start as draft at brief version 1, created by the admin');
select is((select client_id from public.project_internal where project_id = (select id from made where kind = 'fi')),
  '42000000-0000-0000-0000-0000000000c1'::uuid, 'client is linked in project_internal');
select is((select client_price from public.project_internal where project_id = (select id from made where kind = 'fi')),
  50000.00::numeric, 'client price is stored in project_internal');
select ok((select client_id is null from public.project_internal where project_id = (select id from made where kind = 'cl')),
  'a project can have no client');
select is((select proposed_amount from public.projects where id = (select id from made where kind = 'fi')),
  15000.00::numeric, 'proposed pay is stored on the project');

-- Review Focus 1: jsonb shapes.
select throws_ok($$ select public.admin_create_project(null) $$, 'ES422', null, 'null input is refused');
select throws_ok($$ select public.admin_create_project('[]') $$, 'ES422', null, 'an array input is refused');
select throws_ok($$ select public.admin_create_project('{}') $$, 'ES422', null, 'an empty object is refused (no title)');
select throws_ok($$ select public.admin_create_project('"text"') $$, 'ES422', null, 'a string input is refused');
select lives_ok($$ insert into made select 'unknown_keys', public.admin_create_project(pg_temp.base('{"bogus": 1, "status": "completed"}')) $$,
  'unknown keys are ignored');
select is((select status from public.projects where id = (select id from made where kind = 'unknown_keys')),
  'draft'::public.project_status, 'a status key in the input is ignored');
select throws_ok($$ select public.admin_create_project(pg_temp.base('{"deliverables": {}}')) $$,
  'ES422', null, 'deliverables as an object is refused');
select throws_ok($$ select public.admin_create_project(pg_temp.base('{"references": "x"}')) $$,
  'ES422', null, 'references as a string is refused');
select throws_ok($$ select public.admin_create_project(pg_temp.base('{"deliverables": [1]}')) $$,
  'ES422', null, 'a deliverable that is not an object is refused');
select throws_ok($$ select public.admin_create_project(pg_temp.base('{"brief": []}')) $$,
  'ES422', null, 'brief as an array is refused');
select lives_ok($$ select public.admin_create_project(pg_temp.base('{"deliverables": null, "references": [], "brief": null}')) $$,
  'null and empty lists are accepted');

-- Review Focus 2: item caps.
select throws_ok($$ select public.admin_create_project(pg_temp.base(jsonb_build_object('deliverables',
  (select jsonb_agg(jsonb_build_object('name', 'D' || g)) from generate_series(1, 51) g)))) $$,
  'ES422', null, 'more than 50 deliverables are refused');
select throws_ok($$ select public.admin_create_project(pg_temp.base(jsonb_build_object('references',
  (select jsonb_agg(jsonb_build_object('url', 'https://e.com/' || g)) from generate_series(1, 101) g)))) $$,
  'ES422', null, 'more than 100 references are refused');
select lives_ok($$ select public.admin_create_project(pg_temp.base(jsonb_build_object('deliverables',
  (select jsonb_agg(jsonb_build_object('name', 'D' || g)) from generate_series(1, 50) g)))) $$,
  'exactly 50 deliverables are accepted');

-- Review Focus 3: timecodes, URLs, deadlines.
select throws_ok($$ select public.admin_create_project(pg_temp.base('{"references": [{"url": "https://e.com", "start_seconds": -1}]}')) $$,
  'ES422', null, 'negative timecodes are refused');
select throws_ok($$ select public.admin_create_project(pg_temp.base('{"references": [{"url": "https://e.com", "start_seconds": 1.5}]}')) $$,
  'ES422', null, 'non-integer timecodes are refused');
select throws_ok($$ select public.admin_create_project(pg_temp.base('{"references": [{"url": "https://e.com", "start_seconds": "5"}]}')) $$,
  'ES422', null, 'timecodes given as text are refused');
select throws_ok($$ select public.admin_create_project(pg_temp.base('{"references": [{"url": "https://e.com", "start_seconds": 20, "end_seconds": 10}]}')) $$,
  'ES422', null, 'a reference ending before it starts is refused');
select throws_ok($$ select public.admin_create_project(pg_temp.base('{"references": [{"url": "http://e.com"}]}')) $$,
  'ES422', null, 'http:// reference URLs are refused');
select throws_ok($$ select public.admin_create_project(pg_temp.base('{"references": [{"title": "No link"}]}')) $$,
  'ES422', null, 'a reference without a URL is refused');
select throws_ok($$ select public.admin_create_project(pg_temp.base(jsonb_build_object('references',
  jsonb_build_array(jsonb_build_object('url', 'https://e.com/' || repeat('a', 2040)))))) $$,
  'ES422', null, 'reference URLs longer than 2048 characters are refused');
select throws_ok($$ select public.admin_create_project(pg_temp.base('{"references": [{"url": "https://e.com", "priority": "urgent"}]}')) $$,
  'ES422', null, 'an unknown reference priority is refused');
select lives_ok($$ select public.admin_create_project(pg_temp.base('{"deadline": "2020-01-01"}')) $$,
  'a past deadline is accepted');
select throws_ok($$ select public.admin_create_project(pg_temp.base('{"deadline": "31/12/2026"}')) $$,
  'ES422', null, 'a malformed deadline is refused');
select throws_ok($$ select public.admin_create_project(pg_temp.base('{"deliverables": [{"name": "X", "duration_seconds": -5}]}')) $$,
  'ES422', null, 'a negative deliverable duration is refused');

-- Other validation.
select throws_ok($$ select public.admin_create_project('{"brief_type": "creative_led"}') $$,
  'ES422', null, 'a title is required');
select throws_ok($$ select public.admin_create_project('{"title": "   ", "brief_type": "creative_led"}') $$,
  'ES422', null, 'a blank title is refused');
select throws_ok($$ select public.admin_create_project(pg_temp.base(jsonb_build_object('title', repeat('t', 201)))) $$,
  'ES422', null, 'a title longer than 200 characters is refused');
select throws_ok($$ select public.admin_create_project('{"title": "X", "brief_type": "vibes"}') $$,
  'ES422', null, 'an unknown brief type is refused');
select throws_ok($$ select public.admin_create_project('{"title": "X"}') $$,
  'ES422', null, 'a brief type is required');
select throws_ok($$ select public.admin_create_project(pg_temp.base('{"service_type_code": "nope"}')) $$,
  'ES422', null, 'an unknown service type is refused');
select throws_ok($$ select public.admin_create_project(pg_temp.base('{"proposed_currency": "RUPEES"}')) $$,
  'ES422', null, 'a bad currency is refused');
select throws_ok($$ select public.admin_create_project(pg_temp.base('{"proposed_amount": -1}')) $$,
  'ES422', null, 'a negative proposed amount is refused');
select throws_ok($$ select public.admin_create_project(pg_temp.base('{"revision_allowance": 21}')) $$,
  'ES422', null, 'a revision allowance above 20 is refused');
select throws_ok($$ select public.admin_create_project(pg_temp.base('{"client_id": "42000000-0000-0000-0000-0000000000c3"}')) $$,
  'ES422', null, 'a merged client cannot be linked');
select throws_ok($$ select public.admin_create_project(pg_temp.base('{"client_id": "42000000-0000-0000-0000-0000000000c4"}')) $$,
  'ES422', null, 'an archived client cannot be linked');
select throws_ok($$ select public.admin_create_project(pg_temp.base('{"client_id": "42000000-0000-0000-0000-0000000000ff"}')) $$,
  'ES422', null, 'an unknown client is refused');
select throws_ok($$ select public.admin_create_project(pg_temp.base('{"deliverables": [{"format": "MP4"}]}')) $$,
  'ES422', null, 'a deliverable needs a name');
select throws_ok($$ select public.admin_create_project(pg_temp.base('{"deliverables": [{"id": "42000000-0000-0000-0000-0000000000d9", "name": "Steal"}]}')) $$,
  'ES422', null, 'a deliverable id from another project is refused');
reset role;

-- Snapshot equals the live rows (as postgres: private helper).
select is((select deliverables from public.brief_versions where project_id = (select id from made where kind = 'fi')),
  private.brief_snapshot((select id from made where kind = 'fi')) -> 'deliverables',
  'v1 deliverables snapshot equals the live rows');
select is((select "references" from public.brief_versions where project_id = (select id from made where kind = 'rb')),
  private.brief_snapshot((select id from made where kind = 'rb')) -> 'references',
  'v1 references snapshot equals the live rows');

-- ---------------------------------------------------------------------------
-- Non-admin identities
-- ---------------------------------------------------------------------------
select pg_temp.as_anon();
select throws_ok($$ select public.admin_create_project(pg_temp.base()) $$, 'ES401', null, 'anon cannot create projects');
reset role;
select pg_temp.as_user('42000000-0000-0000-0000-00000000000a', 'aal1');
select throws_ok($$ select public.admin_create_project(pg_temp.base()) $$, 'ES403', null, 'admin without MFA cannot create projects');
reset role;
select pg_temp.as_user('42000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.admin_create_project(pg_temp.base()) $$, 'ES403', null, 'editor A cannot create projects');
reset role;
select pg_temp.as_user('42000000-0000-0000-0000-000000000002');
select throws_ok($$ select public.admin_create_project(pg_temp.base()) $$, 'ES403', null, 'editor B cannot create projects');
reset role;
select pg_temp.as_user('42000000-0000-0000-0000-000000000003');
select throws_ok($$ select public.admin_create_project(pg_temp.base()) $$, 'ES403', null, 'an applicant cannot create projects');
reset role;

-- ---------------------------------------------------------------------------
-- Privileges and audit
-- ---------------------------------------------------------------------------
select ok(has_function_privilege('anon', 'public.admin_create_project(jsonb)', 'execute'),
  'admin_create_project is executable by anon (it authorises in its body)');
select ok(not has_function_privilege('anon', 'private.parse_deliverables(jsonb)', 'execute'),
  'private.parse_deliverables is not executable by anon');
select ok(not has_function_privilege('authenticated', 'private.sync_brief_rows(uuid, jsonb, jsonb)', 'execute'),
  'private.sync_brief_rows is not executable by authenticated');
select is((select count(*)::int from public.activity_logs
  where action = 'project.created' and entity_id = (select id from made where kind = 'fi')::text),
  1, 'one project.created audit row');
select ok((select bool_and(not (details ? 'title') and details::text not like '%Launch%')
  from public.activity_logs where action = 'project.created' and entity_id = (select id from made where kind = 'fi')::text),
  'the audit row holds no title');

select * from finish();

rollback;
