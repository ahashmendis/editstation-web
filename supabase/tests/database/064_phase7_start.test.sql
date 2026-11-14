-- Phase 7: editor_start_work and admin_start_work. Call 10 message order, states (Review
-- Focus 9), suspension, the project status function, and a material change after start.
begin;

create extension if not exists pgtap with schema extensions;

select plan(52);

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

-- Confirmed (or only accepted) assignment; with p_brief the editor also confirms the brief.
create function pg_temp.assignment(p_title text, p_editor uuid, p_interp boolean, p_confirm boolean default true,
  p_brief boolean default false)
returns uuid language plpgsql as $$
declare
  v_project uuid;
  v_id uuid;
begin
  perform pg_temp.as_user('64000000-0000-0000-0000-00000000000a', 'aal2');
  v_project := public.admin_create_project(jsonb_build_object('title', p_title, 'brief_type', 'fully_instructed',
    'deadline', '2026-12-31', 'requires_interpretation', p_interp, 'brief', jsonb_build_object('instructions', 'Cut it'),
    'deliverables', jsonb_build_array(jsonb_build_object('name', 'Main'))));
  perform public.admin_set_project_status(v_project, 'open');
  v_id := public.admin_make_offer(v_project, p_editor, 10000, 'LKR');
  perform pg_temp.as_user(p_editor);
  perform public.editor_respond_offer(v_id, 'accept');
  if p_confirm then
    perform pg_temp.as_user('64000000-0000-0000-0000-00000000000a', 'aal2');
    perform public.admin_confirm_assignment(v_id);
  end if;
  if p_brief then
    perform pg_temp.as_user(p_editor);
    perform public.editor_confirm_brief(v_id, 1, '2026-12-31', 10000, 'LKR');
  end if;
  reset role;
  return v_id;
end;
$$;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('64000000-0000-0000-0000-00000000000a', 'p7w-admin@test.local', '{}', '{}'),
  ('64000000-0000-0000-0000-000000000001', 'p7w-editor-a@test.local', '{}', '{}'),
  ('64000000-0000-0000-0000-000000000002', 'p7w-editor-b@test.local', '{}', '{}');
select private.grant_admin_by_email('p7w-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('64000000-0000-0000-0000-000000000001', '64000000-0000-0000-0000-000000000002');

create temp table ids (kind text primary key, id uuid not null);
grant select, insert on ids to authenticated;
create function pg_temp.a(p_kind text) returns uuid language sql as $$ select id from ids where kind = p_kind $$;
grant execute on function pg_temp.a(text) to authenticated;
create function pg_temp.project(p_kind text) returns uuid language sql as $$
  select project_id from public.assignments where id = (select id from ids where kind = p_kind) $$;
grant execute on function pg_temp.project(text) to authenticated;
create function pg_temp.states(p_kind text) returns text language sql as $$
  select a.status::text || '/' || p.status::text from public.assignments a join public.projects p on p.id = a.project_id
  where a.id = (select id from ids where kind = p_kind) $$;

insert into ids select 'p', pg_temp.assignment('P', '64000000-0000-0000-0000-000000000001', false);
insert into ids select 'i', pg_temp.assignment('I', '64000000-0000-0000-0000-000000000001', true);
insert into ids select 'd', pg_temp.assignment('D', '64000000-0000-0000-0000-000000000001', false, true, true);
insert into ids select 'q', pg_temp.assignment('Q', '64000000-0000-0000-0000-000000000001', false, true, true);
insert into ids select 's', pg_temp.assignment('S', '64000000-0000-0000-0000-000000000001', false, true, true);
insert into ids select 'x', pg_temp.assignment('X', '64000000-0000-0000-0000-000000000001', false, false);
insert into ids select 'h', pg_temp.assignment('H', '64000000-0000-0000-0000-000000000001', false, true, true);
insert into ids select 'c', pg_temp.assignment('C', '64000000-0000-0000-0000-000000000001', false, true, true);
insert into ids select 'v', pg_temp.assignment('V', '64000000-0000-0000-0000-000000000001', false, true, true);
update public.projects set status = 'on_hold', status_before_hold = 'assigned' where id = pg_temp.project('h');
update public.projects set status = 'cancelled' where id = pg_temp.project('c');
update public.projects set archived_at = now() where id = pg_temp.project('v');

-- ---------------------------------------------------------------------------
-- Refusals with the call 10 messages
-- ---------------------------------------------------------------------------
select is(private.gate_refusal(pg_temp.a('x'), true), 'The agreed pay has not been approved yet.',
  'pay comes first in the refusal order');
select pg_temp.as_user('64000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_start_work(pg_temp.a('i')) $$, 'ES409',
  'Your interpretation needs to be accepted first.', 'start before interpretation acceptance is refused');
select throws_ok($$ select public.editor_start_work(pg_temp.a('p')) $$, 'ES409',
  'Please confirm the current brief first.', 'start before brief confirmation is refused');
reset role;
select pg_temp.as_user('64000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_update_project(pg_temp.project('d'), '{"deadline": "2027-03-01"}');
select throws_ok($$ select public.admin_start_work(pg_temp.a('p')) $$, 'ES409',
  'The editor needs to confirm the current brief first.', 'admin start uses "the editor" wording');
reset role;
select pg_temp.as_user('64000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_start_work(pg_temp.a('d')) $$, 'ES409',
  'The deadline or pay changed since you confirmed. Please confirm again.', 'start with deadline drift is refused');
select throws_ok($$ select public.editor_start_work(pg_temp.a('x')) $$, 'ES409', null,
  'start from accepted is refused');
select throws_ok($$ select public.editor_start_work(pg_temp.a('h')) $$, 'ES409', null,
  'start on an on-hold project is refused');
select throws_ok($$ select public.editor_start_work(pg_temp.a('c')) $$, 'ES409', null,
  'start on a cancelled project is refused');
select throws_ok($$ select public.editor_start_work(pg_temp.a('v')) $$, 'ES409', null,
  'start on an archived project is refused');
reset role;
select ok((select bool_and(a.status = 'confirmed') from public.assignments a
  where a.id in (pg_temp.a('i'), pg_temp.a('p'), pg_temp.a('d'), pg_temp.a('h'), pg_temp.a('c'), pg_temp.a('v'))),
  'refused starts change nothing');
select is((select count(*)::int from public.activity_logs where action = 'assignment.in_progress'), 0,
  'no in_progress audit row yet');

-- The gate itself checks the project (every path to in_progress inherits it).
select ok((select not project_active and editor_active and not ready from private.assignment_gate(pg_temp.a('h'))),
  'the gate is not ready on an on-hold project');
select ok((select not project_active and not ready from private.assignment_gate(pg_temp.a('v'))),
  'the gate is not ready on an archived project');
select ok((select project_active and editor_active and ready from private.assignment_gate(pg_temp.a('q'))),
  'the gate is ready on an assigned project with an active editor');
select throws_ok($$ update public.assignments set status = 'in_progress', started_at = now() where id = pg_temp.a('h') $$,
  'ES409', 'Work cannot continue while the project is on hold, cancelled or archived.',
  'a direct update on an on-hold project is refused, even for the table owner');
select throws_ok($$ update public.assignments set status = 'in_progress', started_at = now() where id = pg_temp.a('v') $$,
  'ES409', 'Work cannot continue while the project is on hold, cancelled or archived.',
  'a direct update on an archived project is refused, even for the table owner');
select pg_temp.as_user('64000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_start_work(pg_temp.a('h')) $$, 'ES409', null,
  'admin start on an on-hold project is refused');
select throws_ok($$ select public.admin_start_work(pg_temp.a('v')) $$, 'ES409', null,
  'admin start on an archived project is refused');
reset role;
select ok((select bool_and(a.status = 'confirmed') from public.assignments a
  where a.id in (pg_temp.a('h'), pg_temp.a('v'))), 'the on-hold and archived assignments are still confirmed');

-- ---------------------------------------------------------------------------
-- Happy paths
-- ---------------------------------------------------------------------------
select pg_temp.as_user('64000000-0000-0000-0000-000000000001');
select lives_ok($$ select public.editor_confirm_brief(pg_temp.a('p'), 1, '2026-12-31', 10000, 'LKR') $$,
  'editor A confirms P');
select lives_ok($$ select public.editor_start_work(pg_temp.a('p')) $$, 'editor A starts P');
select throws_ok($$ select public.editor_start_work(pg_temp.a('p')) $$, 'ES409', 'Work has already started.',
  'starting twice is refused');
reset role;
select is(pg_temp.states('p'), 'in_progress/in_progress', 'assignment and project are in_progress');
select ok((select started_by = '64000000-0000-0000-0000-000000000001' and started_at is not null
  from public.assignments where id = pg_temp.a('p')), 'the start records the editor and the time');
select ok(exists (select 1 from public.activity_logs where action = 'assignment.in_progress'
    and entity_id = pg_temp.a('p')::text)
  and exists (select 1 from public.activity_logs where action = 'project.in_progress'
    and entity_id = pg_temp.project('p')::text), 'both moves are audited');

select pg_temp.as_user('64000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok($$ select public.admin_start_work(pg_temp.a('q')) $$, 'admin starts Q for the editor');
select throws_ok($$ select public.admin_start_work(gen_random_uuid()) $$, 'ES422', 'Assignment not found.',
  'admin start on an unknown id is refused');
select throws_ok($$ select public.admin_set_project_status(pg_temp.project('s'), 'in_progress') $$, 'ES409', null,
  'admin_set_project_status cannot set in_progress');
reset role;
select ok((select status = 'in_progress' and started_by = '64000000-0000-0000-0000-00000000000a'
  from public.assignments where id = pg_temp.a('q')), 'an admin start records the admin');

-- Suspended editor: admin start refused, editor functions refused.
update public.editor_profiles set access_status = 'suspended' where user_id = '64000000-0000-0000-0000-000000000001';
select pg_temp.as_user('64000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_start_work(pg_temp.a('s')) $$, 'ES409',
  'This editor''s access is not active, so work cannot start.', 'admin cannot start for a suspended editor');
reset role;
select pg_temp.as_user('64000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_start_work(pg_temp.a('s')) $$, 'ES403', null,
  'a suspended editor cannot start');
reset role;
select ok((select not editor_active and project_active and not ready from private.assignment_gate(pg_temp.a('s'))),
  'the gate is not ready for a suspended editor');
select throws_ok($$ update public.assignments set status = 'in_progress', started_at = now() where id = pg_temp.a('s') $$,
  'ES409', 'This editor''s access is not active, so work cannot start.',
  'a direct update for a suspended editor is refused, even for the table owner');
update public.editor_profiles set access_status = 'active' where user_id = '64000000-0000-0000-0000-000000000001';
select is(pg_temp.states('s'), 'confirmed/assigned', 'nothing changed for S');

-- Another editor's id.
select pg_temp.as_user('64000000-0000-0000-0000-000000000002');
select throws_ok($$ select public.editor_start_work(pg_temp.a('s')) $$, 'ES422', 'Assignment not found.',
  'editor B cannot start A''s assignment');
select throws_ok($$ select public.editor_start_work(gen_random_uuid()) $$, 'ES422', 'Assignment not found.',
  'an unknown id gives the same message');
reset role;

-- ---------------------------------------------------------------------------
-- After start: a material change does not move the assignment back (spec call 7)
-- ---------------------------------------------------------------------------
select pg_temp.as_user('64000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_save_brief(pg_temp.project('p'), '{"brief": {"instructions": "Cut it differently"},
  "change_summary": "Material", "requires_reacknowledgement": true}');
select ok((select not ready and reacknowledgement_required from public.get_assignment_gate(pg_temp.a('p'))),
  'the gate is not ready after a material change');
reset role;
select is(pg_temp.states('p'), 'in_progress/in_progress', 'the assignment and project stay in_progress');

-- ---------------------------------------------------------------------------
-- Roles and direct writes
-- ---------------------------------------------------------------------------
select pg_temp.as_anon();
select throws_ok($$ select public.editor_start_work(gen_random_uuid()) $$, 'ES401', null, 'anon cannot start');
select throws_ok($$ select public.admin_start_work(gen_random_uuid()) $$, 'ES401', null, 'anon cannot admin-start');
reset role;
select pg_temp.as_user('64000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.admin_start_work(pg_temp.a('s')) $$, 'ES403', null, 'an editor cannot admin-start');
select throws_ok($$ update public.assignments set status = 'in_progress', started_at = now() where id = pg_temp.a('s') $$,
  '42501', null, 'an editor cannot update assignments directly');
select throws_ok($$ update public.projects set status = 'in_progress' where id = pg_temp.project('s') $$,
  '42501', null, 'an editor cannot update projects directly');
reset role;
select pg_temp.as_user('64000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.editor_start_work(pg_temp.a('s')) $$, 'ES403', null,
  'an admin cannot start as an editor');
select throws_ok($$ update public.assignments set status = 'in_progress', started_at = now() where id = pg_temp.a('s') $$,
  '42501', null, 'an admin cannot update assignments directly');
reset role;
select pg_temp.as_user('64000000-0000-0000-0000-00000000000a', 'aal1');
select throws_ok($$ select public.admin_start_work(pg_temp.a('s')) $$, 'ES403', null,
  'admin without MFA cannot start');
reset role;
select pg_temp.as_user('64000000-0000-0000-0000-000000000002');
select throws_ok($$ select public.admin_start_work(pg_temp.a('s')) $$, 'ES403', null, 'editor B cannot admin-start');
reset role;
select is(pg_temp.states('s'), 'confirmed/assigned', 'S is still waiting');

-- ---------------------------------------------------------------------------
-- Archiving is refused while an assignment is confirmed or in progress
-- ---------------------------------------------------------------------------
select pg_temp.as_user('64000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_archive_project(pg_temp.project('s'), true) $$, 'ES409',
  'Cancel or finish the assignment before archiving.', 'a project with a confirmed assignment cannot be archived');
select throws_ok($$ select public.admin_archive_project(pg_temp.project('q'), true) $$, 'ES409',
  'Cancel or finish the assignment before archiving.', 'a project with an in_progress assignment cannot be archived');
select lives_ok($$ select public.admin_archive_project(pg_temp.project('x'), true) $$,
  'a project whose assignment is only accepted can still be archived');
reset role;
select ok((select archived_at is null from public.projects where id = pg_temp.project('s'))
  and (select archived_at is null from public.projects where id = pg_temp.project('q')),
  'the refused archives changed nothing');

select * from finish();

rollback;
