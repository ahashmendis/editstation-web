-- Phase 4: admin_save_brief and immutable brief versioning (spec §8, §14). Review Focus 4.
begin;

create extension if not exists pgtap with schema extensions;

select plan(46);

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

-- Live deliverables of a project, as input items with ids (admin can read them).
create function pg_temp.live_deliverables(p_project uuid)
returns jsonb language sql as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'format', format,
    'resolution', resolution, 'aspect_ratio', aspect_ratio, 'duration_seconds', duration_seconds,
    'notes', notes, 'sort_order', sort_order) order by sort_order, id), '[]'::jsonb)
  from public.project_deliverables where project_id = p_project;
$$;
create function pg_temp.live_references(p_project uuid)
returns jsonb language sql as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'title', title, 'url', url,
    'start_seconds', start_seconds, 'end_seconds', end_seconds, 'priority', priority,
    'sort_order', sort_order) order by sort_order, id), '[]'::jsonb)
  from public.project_references where project_id = p_project;
$$;
create function pg_temp.versions(p_project uuid)
returns int language sql as $$
  select count(*)::int from public.brief_versions where project_id = p_project;
$$;

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('43000000-0000-0000-0000-00000000000a', 'p4b-admin@test.local', '{}', '{}'),
  ('43000000-0000-0000-0000-000000000001', 'p4b-editor-a@test.local', '{}', '{}'),
  ('43000000-0000-0000-0000-000000000002', 'p4b-editor-b@test.local', '{}', '{}'),
  ('43000000-0000-0000-0000-000000000003', 'p4b-applicant@test.local', '{}', '{}');
select private.grant_admin_by_email('p4b-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('43000000-0000-0000-0000-000000000001', '43000000-0000-0000-0000-000000000002');

insert into public.projects (id, title, brief_type) values ('43000000-0000-0000-0000-0000000000f9', 'Other', 'creative_led');
insert into public.project_deliverables (id, project_id, name)
values ('43000000-0000-0000-0000-0000000000d9', '43000000-0000-0000-0000-0000000000f9', 'Foreign');

create temp table p (id uuid);
grant select, insert on p to authenticated;
grant select on p to anon;
create temp table v1_before (row jsonb);

select pg_temp.as_user('43000000-0000-0000-0000-00000000000a', 'aal2');
insert into p select public.admin_create_project('{
  "title": "Brief test", "brief_type": "reference_based", "deadline": "2026-12-31",
  "brief": {"instructions": "First draft"},
  "deliverables": [{"name": "Main edit", "format": "MP4"}],
  "references": [{"url": "https://example.com/a", "start_seconds": 1, "end_seconds": 2}]}'::jsonb);

-- ---------------------------------------------------------------------------
-- Before the first opening: v1 is edited in place
-- ---------------------------------------------------------------------------
select is(public.admin_save_brief((select id from p), jsonb_build_object(
    'brief', jsonb_build_object('instructions', 'Second draft'),
    'deliverables', pg_temp.live_deliverables((select id from p)) || '[{"name": "Teaser"}]'::jsonb,
    'references', pg_temp.live_references((select id from p)))),
  1, 'a pre-open save returns version 1');
select is(pg_temp.versions((select id from p)), 1, 'a pre-open save creates no new version');
select is((select instructions from public.brief_versions where project_id = (select id from p)),
  'Second draft', 'v1 instructions are updated in place');
select is((select jsonb_array_length(deliverables) from public.brief_versions where project_id = (select id from p)),
  2, 'the v1 snapshot is updated in place');
select is((select current_brief_version from public.projects where id = (select id from p)), 1,
  'current_brief_version stays 1 before opening');
select is((select count(*)::int from public.activity_logs where action = 'project.brief_version'
  and entity_id = (select id from p)::text), 0, 'in-place edits write no version audit row');
reset role;

-- Open the project (as postgres, the status function comes in a later migration).
update public.projects set first_opened_at = now(), status = 'open' where id = (select id from p);
insert into v1_before select to_jsonb(b) from public.brief_versions b where project_id = (select id from p) and version = 1;

select pg_temp.as_user('43000000-0000-0000-0000-00000000000a', 'aal2');

-- ---------------------------------------------------------------------------
-- After opening: no change -> no version (Review Focus 4)
-- ---------------------------------------------------------------------------
select is(public.admin_save_brief((select id from p), jsonb_build_object(
    'brief', jsonb_build_object('instructions', 'Second draft'),
    'deliverables', pg_temp.live_deliverables((select id from p)),
    'references', pg_temp.live_references((select id from p)))),
  1, 'identical content returns the current version');
select is(pg_temp.versions((select id from p)), 1, 'identical content creates no version');

select is(public.admin_save_brief((select id from p), jsonb_build_object(
    'brief', jsonb_build_object('instructions', E'  Second draft \n'),
    'deliverables', (select jsonb_agg(e || jsonb_build_object('name', '  ' || (e ->> 'name') || '  '))
                     from jsonb_array_elements(pg_temp.live_deliverables((select id from p))) e),
    'references', pg_temp.live_references((select id from p)))),
  1, 'whitespace-only edits return the current version');
select is(pg_temp.versions((select id from p)), 1, 'whitespace-only edits create no version');

select is(public.admin_save_brief((select id from p), jsonb_build_object(
    'brief', jsonb_build_object('instructions', 'Second draft'),
    'deliverables', (select jsonb_agg(e || jsonb_build_object('sort_order', 10 - (e ->> 'sort_order')::int))
                     from jsonb_array_elements(pg_temp.live_deliverables((select id from p))) e),
    'references', pg_temp.live_references((select id from p)))),
  1, 'reordering returns the current version');
select is(pg_temp.versions((select id from p)), 1, 'reordering alone creates no version');

-- ---------------------------------------------------------------------------
-- After opening: content changes create versions
-- ---------------------------------------------------------------------------
select throws_ok($$ select public.admin_save_brief((select id from p), jsonb_build_object(
    'brief', jsonb_build_object('instructions', 'Third draft'),
    'deliverables', pg_temp.live_deliverables((select id from p)),
    'references', pg_temp.live_references((select id from p)))) $$,
  'ES422', null, 'a change summary is required from version 2 on');
select is(pg_temp.versions((select id from p)), 1, 'the refused save left no trace');

select is(public.admin_save_brief((select id from p), jsonb_build_object(
    'brief', jsonb_build_object('instructions', 'Third draft'),
    'deliverables', pg_temp.live_deliverables((select id from p)),
    'references', pg_temp.live_references((select id from p)),
    'change_summary', 'Fixed a typo', 'requires_reacknowledgement', false)),
  2, 'an instructions change after opening creates version 2');
select is((select current_brief_version from public.projects where id = (select id from p)), 2,
  'current_brief_version moves to 2');
select is((select requires_reacknowledgement from public.brief_versions where project_id = (select id from p) and version = 2),
  false, 'requires_reacknowledgement false is honoured for an instructions-only change');
select is((select change_summary from public.brief_versions where project_id = (select id from p) and version = 2),
  'Fixed a typo', 'the change summary is stored');
select is((select instructions from public.brief_versions where project_id = (select id from p) and version = 2),
  'Third draft', 'v2 holds the new instructions');
reset role;

select is((select deliverables from public.brief_versions where project_id = (select id from p) and version = 2),
  private.brief_snapshot((select id from p)) -> 'deliverables', 'v2 deliverables snapshot is faithful');
select is((select "references" from public.brief_versions where project_id = (select id from p) and version = 2),
  private.brief_snapshot((select id from p)) -> 'references', 'v2 references snapshot is faithful');
select is((select to_jsonb(b) from public.brief_versions b where project_id = (select id from p) and version = 1),
  (select row from v1_before), 'v1 is unchanged after version 2 is created');

select pg_temp.as_user('43000000-0000-0000-0000-00000000000a', 'aal2');
select is(public.admin_save_brief((select id from p), jsonb_build_object(
    'brief', jsonb_build_object('instructions', 'Third draft'),
    'deliverables', (select jsonb_agg(e || '{"format": "MOV"}'::jsonb)
                     from jsonb_array_elements(pg_temp.live_deliverables((select id from p))) e),
    'references', pg_temp.live_references((select id from p)),
    'change_summary', 'Changed format', 'requires_reacknowledgement', false)),
  3, 'a deliverables change creates version 3');
select is((select requires_reacknowledgement from public.brief_versions where project_id = (select id from p) and version = 3),
  true, 'requires_reacknowledgement is forced true when deliverables change');

select is(public.admin_save_brief((select id from p), jsonb_build_object(
    'brief', jsonb_build_object('instructions', 'Third draft'),
    'deliverables', pg_temp.live_deliverables((select id from p)),
    'references', '[]'::jsonb,
    'change_summary', 'Dropped the reference')),
  4, 'removing a reference creates version 4');
select is((select requires_reacknowledgement from public.brief_versions where project_id = (select id from p) and version = 4),
  true, 'requires_reacknowledgement defaults to true');
select is((select count(*)::int from public.project_references where project_id = (select id from p)), 0,
  'the removed reference is gone from the live rows');
select is((select jsonb_array_length("references") from public.brief_versions where project_id = (select id from p) and version = 3),
  1, 'the earlier version still holds the reference');

select throws_ok($$ select public.admin_save_brief((select id from p), jsonb_build_object(
    'brief', jsonb_build_object('instructions', 'Third draft'),
    'deliverables', '[{"id": "43000000-0000-0000-0000-0000000000d9", "name": "Steal"}]'::jsonb,
    'change_summary', 'x')) $$,
  'ES422', null, 'a deliverable id from another project is refused');
select throws_ok($$ select public.admin_save_brief((select id from p), null) $$,
  'ES422', null, 'null input is refused');
select throws_ok($$ select public.admin_save_brief('43000000-0000-0000-0000-0000000000ff', '{}') $$,
  'ES422', null, 'an unknown project is refused');
reset role;

-- open -> draft does not reopen the in-place window.
update public.projects set status = 'draft' where id = (select id from p);
select pg_temp.as_user('43000000-0000-0000-0000-00000000000a', 'aal2');
select is(public.admin_save_brief((select id from p), jsonb_build_object(
    'brief', jsonb_build_object('instructions', 'Back in draft'),
    'deliverables', pg_temp.live_deliverables((select id from p)),
    'change_summary', 'Edited after reverting to draft')),
  5, 'editing after open -> draft still creates a new version');
reset role;

-- on_hold allows edits; cancelled and archived refuse them.
update public.projects set status = 'on_hold', status_before_hold = 'draft' where id = (select id from p);
select pg_temp.as_user('43000000-0000-0000-0000-00000000000a', 'aal2');
select is(public.admin_save_brief((select id from p), jsonb_build_object(
    'brief', jsonb_build_object('instructions', 'On hold edit'),
    'deliverables', pg_temp.live_deliverables((select id from p)),
    'change_summary', 'Edited while on hold')),
  6, 'an on-hold project can be edited');
select is(public.admin_save_brief((select id from p), '{"brief": {"instructions": "On hold edit"}}'),
  6, 'absent deliverables and references keys keep the current lists (no new version)');
select is((select count(*)::int from public.project_deliverables where project_id = (select id from p)), 2,
  'deliverables are untouched when the key is absent');
reset role;

update public.projects set status = 'cancelled', status_before_hold = null where id = (select id from p);
select pg_temp.as_user('43000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_save_brief((select id from p), jsonb_build_object(
    'brief', jsonb_build_object('instructions', 'Cancelled edit'), 'change_summary', 'x')) $$,
  'ES409', null, 'a cancelled project cannot be edited');
reset role;

update public.projects set status = 'draft', archived_at = now() where id = (select id from p);
select pg_temp.as_user('43000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_save_brief((select id from p), jsonb_build_object(
    'brief', jsonb_build_object('instructions', 'Archived edit'), 'change_summary', 'x')) $$,
  'ES409', null, 'an archived project cannot be edited');
reset role;

-- Audit: one row per created version, ids and numbers only.
select is((select count(*)::int from public.activity_logs where action = 'project.brief_version'
  and entity_id = (select id from p)::text), 5, 'each created version writes one audit row');
select ok((select bool_and(not (details ? 'title') and not (details ? 'change_summary'))
  from public.activity_logs where action = 'project.brief_version' and entity_id = (select id from p)::text),
  'version audit rows hold no text content');

-- Trigger: direct update of an opened version is refused even for postgres.
select throws_ok($$ update public.brief_versions set instructions = 'Tampered'
  where project_id = (select id from p) and version = 1 $$,
  'ES409', null, 'a direct update of v1 after opening is refused');
select is((select to_jsonb(b) from public.brief_versions b where project_id = (select id from p) and version = 1),
  (select row from v1_before), 'v1 is byte-for-byte unchanged at the end');

-- ---------------------------------------------------------------------------
-- Non-admin identities
-- ---------------------------------------------------------------------------
select pg_temp.as_anon();
select throws_ok($$ select public.admin_save_brief((select id from p), '{}') $$, 'ES401', null, 'anon cannot save briefs');
reset role;
select pg_temp.as_user('43000000-0000-0000-0000-00000000000a', 'aal1');
select throws_ok($$ select public.admin_save_brief((select id from p), '{}') $$, 'ES403', null, 'admin without MFA cannot save briefs');
reset role;
select pg_temp.as_user('43000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.admin_save_brief((select id from p), '{}') $$, 'ES403', null, 'editor A cannot save briefs');
reset role;
select pg_temp.as_user('43000000-0000-0000-0000-000000000002');
select throws_ok($$ select public.admin_save_brief((select id from p), '{}') $$, 'ES403', null, 'editor B cannot save briefs');
reset role;
select pg_temp.as_user('43000000-0000-0000-0000-000000000003');
select throws_ok($$ select public.admin_save_brief((select id from p), '{}') $$, 'ES403', null, 'an applicant cannot save briefs');
reset role;

select * from finish();

rollback;
