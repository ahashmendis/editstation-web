-- Phase 7: the gate (private.assignment_gate), get_assignment_gate, the in_progress triggers,
-- editor stage while in_progress and carry-forward on brief versions. Review Focus 7, 8, 10.
begin;

create extension if not exists pgtap with schema extensions;

select plan(49);

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

-- A confirmation row for an assignment's current version, matching its project and pay.
create function pg_temp.confirm(p_assignment uuid) returns uuid language plpgsql as $$
declare
  v_id uuid;
begin
  insert into public.brief_confirmations (assignment_id, project_id, editor_id, brief_version_id, brief_version, kind,
    confirmed_deadline, confirmed_deliverables, confirmed_amount, confirmed_currency, created_by, confirmed_at)
  select a.id, a.project_id, a.editor_id, bv.id, bv.version, 'confirmed', p.deadline, bv.deliverables,
         a.agreed_amount, a.agreed_currency, a.editor_id, clock_timestamp()
  from public.assignments a
  join public.projects p on p.id = a.project_id
  join public.brief_versions bv on bv.project_id = p.id and bv.version = p.current_brief_version
  where a.id = p_assignment
  returning id into v_id;
  return v_id;
end;
$$;

-- Adds brief version n+1 (as postgres) and makes it current.
create function pg_temp.new_version(p_project uuid, p_reack boolean, p_deliverables jsonb default null)
returns uuid language plpgsql as $$
declare
  v_id uuid;
  v_next int := (select current_brief_version + 1 from public.projects where id = p_project);
begin
  insert into public.brief_versions (project_id, version, change_summary, instructions, requires_reacknowledgement,
    deliverables, created_by)
  select p_project, v_next, 'Change ' || v_next, 'Cut it v' || v_next, p_reack,
         coalesce(p_deliverables, bv.deliverables), '61000000-0000-0000-0000-00000000000a'
  from public.brief_versions bv
  join public.projects p on p.id = bv.project_id and bv.version = p.current_brief_version
  where bv.project_id = p_project
  returning id into v_id;
  update public.projects set current_brief_version = v_next where id = p_project;
  return v_id;
end;
$$;

create function pg_temp.gx(p_assignment uuid) returns text language sql as $$
  select row(compensation_approved, interpretation_required, interpretation_accepted, current_brief_version,
          confirmed_brief_version, reacknowledgement_required, deadline_changed, amount_changed, deliverables_changed,
          brief_confirmed, ready)::text
  from private.assignment_gate(p_assignment) $$;

-- ---------------------------------------------------------------------------
-- Fixtures (as postgres)
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('61000000-0000-0000-0000-00000000000a', 'p7g-admin@test.local', '{}', '{}'),
  ('61000000-0000-0000-0000-000000000001', 'p7g-editor-a@test.local', '{}', '{}'),
  ('61000000-0000-0000-0000-000000000002', 'p7g-editor-b@test.local', '{}', '{}'),
  ('61000000-0000-0000-0000-000000000003', 'p7g-applicant@test.local', '{}', '{}'),
  ('61000000-0000-0000-0000-000000000004', 'p7g-suspended@test.local', '{}', '{}');
select private.grant_admin_by_email('p7g-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('61000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000002');
update public.editor_profiles set access_status = 'suspended'
where user_id = '61000000-0000-0000-0000-000000000004';

-- P: A confirmed. P2: A confirmed, interpretation required. P3: A accepted only. P4: B confirmed.
-- P5: A confirmed, interpretation required (carry-forward chain, then started).
insert into public.projects (id, title, brief_type, status, first_opened_at, deadline, requires_interpretation) values
  ('61000000-0000-0000-0000-0000000000f1', 'P', 'fully_instructed', 'assigned', now(), '2026-12-31', false),
  ('61000000-0000-0000-0000-0000000000f2', 'P2', 'reference_based', 'assigned', now(), '2026-12-31', true),
  ('61000000-0000-0000-0000-0000000000f3', 'P3', 'fully_instructed', 'open', now(), '2026-12-31', false),
  ('61000000-0000-0000-0000-0000000000f4', 'P4', 'fully_instructed', 'assigned', now(), '2026-12-31', false),
  ('61000000-0000-0000-0000-0000000000f5', 'P5', 'creative_led', 'assigned', now(), '2026-12-31', true);
insert into public.brief_versions (project_id, version, instructions, deliverables)
select id, 1, 'Cut it', '[{"name": "Main"}]' from public.projects where title in ('P', 'P2', 'P3', 'P4', 'P5')
  and id::text like '61000000-%';
insert into public.assignments (id, project_id, editor_id, status, proposed_amount, agreed_amount, agreed_currency,
  confirmed_at) values
  ('61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-0000000000f1',
   '61000000-0000-0000-0000-000000000001', 'confirmed', 10000, 10000, 'LKR', now()),
  ('61000000-0000-0000-0000-0000000000a2', '61000000-0000-0000-0000-0000000000f2',
   '61000000-0000-0000-0000-000000000001', 'confirmed', 10000, 10000, 'LKR', now()),
  ('61000000-0000-0000-0000-0000000000a3', '61000000-0000-0000-0000-0000000000f3',
   '61000000-0000-0000-0000-000000000001', 'accepted', 10000, 10000, 'LKR', null),
  ('61000000-0000-0000-0000-0000000000b4', '61000000-0000-0000-0000-0000000000f4',
   '61000000-0000-0000-0000-000000000002', 'confirmed', 10000, 10000, 'LKR', now()),
  ('61000000-0000-0000-0000-0000000000a5', '61000000-0000-0000-0000-0000000000f5',
   '61000000-0000-0000-0000-000000000001', 'confirmed', 10000, 10000, 'LKR', now());
insert into public.project_references (project_id, url, title) values
  ('61000000-0000-0000-0000-0000000000f5', 'https://ref.example.com/p5', 'Ref');
insert into public.project_assets (project_id, label, url) values
  ('61000000-0000-0000-0000-0000000000f5', 'Footage', 'https://drive.example.com/p5');

create temp table ids (kind text primary key, id uuid not null);

-- ---------------------------------------------------------------------------
-- Gate cells
-- ---------------------------------------------------------------------------
select is(pg_temp.gx('61000000-0000-0000-0000-0000000000a1'),
  '(t,f,f,1,,t,f,f,f,f,f)', 'no confirmation: re-acknowledgement required, not ready');
insert into ids select 'c1', pg_temp.confirm('61000000-0000-0000-0000-0000000000a1');
select is(pg_temp.gx('61000000-0000-0000-0000-0000000000a1'),
  '(t,f,f,1,1,f,f,f,f,t,t)', 'a matching confirmation for v1: brief confirmed and ready');
select is((select count(*)::int from private.assignment_gate(gen_random_uuid())), 0,
  'an unknown assignment has no gate row');

insert into ids select 'c2', pg_temp.confirm('61000000-0000-0000-0000-0000000000a2');
select is(pg_temp.gx('61000000-0000-0000-0000-0000000000a2'),
  '(t,t,f,1,1,f,f,f,f,t,f)', 'interpretation required and not accepted: not ready');
insert into public.editor_interpretations (assignment_id, brief_version_id, will_reproduce, status, reviewed_at)
select '61000000-0000-0000-0000-0000000000a2', id, 'Pacing', 'accepted', now()
from public.brief_versions where project_id = '61000000-0000-0000-0000-0000000000f2' and version = 1;
select is(pg_temp.gx('61000000-0000-0000-0000-0000000000a2'),
  '(t,t,t,1,1,f,f,f,f,t,t)', 'an accepted v1 interpretation: ready');

select ok((select not compensation_approved and not ready
  from private.assignment_gate('61000000-0000-0000-0000-0000000000a3')),
  'an accepted (not confirmed) assignment has no approved compensation');

update public.projects set deadline = '2027-01-15' where id = '61000000-0000-0000-0000-0000000000f1';
select is(pg_temp.gx('61000000-0000-0000-0000-0000000000a1'),
  '(t,f,f,1,1,f,t,f,f,f,f)', 'a moved deadline: deadline_changed, not ready');
update public.projects set deadline = null where id = '61000000-0000-0000-0000-0000000000f1';
select ok((select deadline_changed and not ready from private.assignment_gate('61000000-0000-0000-0000-0000000000a1')),
  'a cleared deadline counts as changed (Review Focus 3)');
update public.projects set deadline = '2026-12-31' where id = '61000000-0000-0000-0000-0000000000f1';

update public.assignments set proposed_amount = 12000, agreed_amount = 12000
where id = '61000000-0000-0000-0000-0000000000a1';
select is(pg_temp.gx('61000000-0000-0000-0000-0000000000a1'),
  '(t,f,f,1,1,f,f,t,f,f,f)', 'changed agreed pay: amount_changed, not ready');
update public.assignments set proposed_amount = 10000, agreed_amount = 10000
where id = '61000000-0000-0000-0000-0000000000a1';
select ok((select ready from private.assignment_gate('61000000-0000-0000-0000-0000000000a1')),
  'restoring deadline and pay makes it ready again');

-- Review Focus 10: direct updates without the gate. Then v2 with new deliverables (re-ack true).
insert into ids select 'p_v2', pg_temp.new_version('61000000-0000-0000-0000-0000000000f1', true,
  '[{"name": "Main"}, {"name": "Teaser"}]');
select is(pg_temp.gx('61000000-0000-0000-0000-0000000000a1'),
  '(t,f,f,2,1,t,f,f,t,f,f)', 'v2 with re-acknowledgement and new deliverables: re-confirmation required');
select is((select count(*)::int from public.brief_confirmations where assignment_id = '61000000-0000-0000-0000-0000000000a1'),
  1, 'a re-acknowledgement version carries nothing forward');
select throws_ok($$ update public.assignments set status = 'in_progress', started_at = now()
  where id = '61000000-0000-0000-0000-0000000000a1' $$, 'ES409', null,
  'a direct update to in_progress without the gate is refused, even for the table owner');
select throws_ok($$ update public.projects set status = 'in_progress' where id = '61000000-0000-0000-0000-0000000000f1' $$,
  'ES409', 'A project starts only when its editor starts work.',
  'a project cannot move to in_progress without an in_progress assignment');
insert into ids select 'p_v3', pg_temp.new_version('61000000-0000-0000-0000-0000000000f1', false);
select is((select count(*)::int from public.brief_confirmations where assignment_id = '61000000-0000-0000-0000-0000000000a1'),
  1, 'v2 true then v3 false without re-confirmation: no carried row (the latest is not for v2)');
select ok((select reacknowledgement_required and not ready
  from private.assignment_gate('61000000-0000-0000-0000-0000000000a1')), 'and the gate still needs confirmation');

-- Interpretation validity across versions on P2.
insert into ids select 'p2_v2', pg_temp.new_version('61000000-0000-0000-0000-0000000000f2', true);
select ok((select not interpretation_accepted from private.assignment_gate('61000000-0000-0000-0000-0000000000a2')),
  'a material v2 invalidates a v1 interpretation');

-- ---------------------------------------------------------------------------
-- Carry-forward chains (Review Focus 8)
-- ---------------------------------------------------------------------------
insert into public.editor_interpretations (assignment_id, brief_version_id, will_adapt, status, reviewed_at)
select '61000000-0000-0000-0000-0000000000a5', id, 'Colour', 'accepted', now()
from public.brief_versions where project_id = '61000000-0000-0000-0000-0000000000f5' and version = 1;
insert into ids select 'c5', pg_temp.confirm('61000000-0000-0000-0000-0000000000a5');
insert into ids select 'p5_v2', pg_temp.new_version('61000000-0000-0000-0000-0000000000f5', false,
  '[{"name": "Main", "notes": "v2 snapshot"}]');
insert into ids select 'p5_v3', pg_temp.new_version('61000000-0000-0000-0000-0000000000f5', false);
select is((select count(*)::int from public.brief_confirmations where assignment_id = '61000000-0000-0000-0000-0000000000a5'),
  3, 'v2 false then v3 false: two carried rows');
select ok((select kind = 'carried_forward' and brief_version = 2 and brief_version_id = (select id from ids where kind = 'p5_v2')
    and carried_from_id = (select id from ids where kind = 'c5')
  from public.brief_confirmations where assignment_id = '61000000-0000-0000-0000-0000000000a5' and brief_version = 2),
  'the v2 row is carried forward from the v1 confirmation');
select ok((select kind = 'carried_forward' and brief_version = 3
    and carried_from_id = (select c.id from public.brief_confirmations c
                           where c.assignment_id = '61000000-0000-0000-0000-0000000000a5' and c.brief_version = 2)
  from public.brief_confirmations where assignment_id = '61000000-0000-0000-0000-0000000000a5' and brief_version = 3),
  'the v3 row is carried forward from the v2 row (chained)');
select ok((select bool_and(c.confirmed_deadline = '2026-12-31' and c.confirmed_amount = 10000
    and c.confirmed_currency = 'LKR' and c.confirmed_deliverables = bv.deliverables
    and c.created_by = '61000000-0000-0000-0000-00000000000a')
  from public.brief_confirmations c join public.brief_versions bv on bv.id = c.brief_version_id
  where c.assignment_id = '61000000-0000-0000-0000-0000000000a5' and c.kind = 'carried_forward'),
  'carried rows copy deadline and pay, take deliverables from the new snapshot, and are created by the admin');
select ok((select confirmed_deliverables = '[{"name": "Main", "notes": "v2 snapshot"}]'::jsonb
  from public.brief_confirmations where assignment_id = '61000000-0000-0000-0000-0000000000a5' and brief_version = 2),
  'the v2 carried row holds the v2 deliverables snapshot');
select is(pg_temp.gx('61000000-0000-0000-0000-0000000000a5'),
  '(t,t,t,3,3,f,f,f,f,t,t)', 'after two carried versions the gate is confirmed and the interpretation still valid');
select is((select count(*)::int from public.activity_logs where action = 'brief_confirmation.carried_forward'
  and details ->> 'assignment_id' = '61000000-0000-0000-0000-0000000000a5'), 2, 'each carried row is audited');
select ok((select bool_and((select array_agg(k order by k) from jsonb_object_keys(details) k)
    = array['assignment_id', 'brief_version', 'carried_from_id', 'confirmation_id'])
  from public.activity_logs where action = 'brief_confirmation.carried_forward'),
  'carry-forward audit details have exactly the id and version keys');

-- An accepted (not confirmed) assignment with a seeded confirmation is not carried.
insert into public.brief_confirmations (assignment_id, project_id, editor_id, brief_version_id, brief_version, kind,
  confirmed_deadline, confirmed_deliverables, confirmed_amount, confirmed_currency)
select '61000000-0000-0000-0000-0000000000a3', '61000000-0000-0000-0000-0000000000f3',
  '61000000-0000-0000-0000-000000000001', id, 1, 'confirmed', '2026-12-31', deliverables, 10000, 'LKR'
from public.brief_versions where project_id = '61000000-0000-0000-0000-0000000000f3' and version = 1;
select pg_temp.new_version('61000000-0000-0000-0000-0000000000f3', false);
select is((select count(*)::int from public.brief_confirmations where assignment_id = '61000000-0000-0000-0000-0000000000a3'),
  1, 'v2 false while the assignment is only accepted: no carried row');

-- ---------------------------------------------------------------------------
-- Gate met: direct updates succeed (Review Focus 10)
-- ---------------------------------------------------------------------------
select pg_temp.confirm('61000000-0000-0000-0000-0000000000b4');
select throws_ok($$ update public.assignments set status = 'in_progress', started_at = now(), agreed_amount = 1,
  proposed_amount = 1 where id = '61000000-0000-0000-0000-0000000000b4' $$, 'ES409', null,
  'the agreed pay cannot change in the same update that starts work');
select lives_ok($$ update public.assignments set status = 'in_progress', started_at = now()
  where id = '61000000-0000-0000-0000-0000000000b4' $$, 'with the gate met, the table owner can start the assignment');
select lives_ok($$ update public.projects set status = 'in_progress' where id = '61000000-0000-0000-0000-0000000000f4' $$,
  'and then the project can move to in_progress');

-- ---------------------------------------------------------------------------
-- Stage while in_progress
-- ---------------------------------------------------------------------------
update public.assignments set status = 'in_progress', started_at = now()
where id = '61000000-0000-0000-0000-0000000000a5';
update public.projects set status = 'in_progress' where id = '61000000-0000-0000-0000-0000000000f5';

select pg_temp.as_user('61000000-0000-0000-0000-000000000001');
select is(private.editor_project_stage('61000000-0000-0000-0000-0000000000f5'), 'assigned',
  'editor A is assigned while in_progress');
select is((select count(*)::int from public.brief_versions where project_id = '61000000-0000-0000-0000-0000000000f5'),
  3, 'editor A sees every brief version while in_progress');
select is((select count(*)::int from public.project_references where project_id = '61000000-0000-0000-0000-0000000000f5'),
  1, 'editor A sees all references while in_progress');
select is((select count(*)::int from public.project_assets where project_id = '61000000-0000-0000-0000-0000000000f5'),
  1, 'editor A sees all assets while in_progress');
select is((select count(*)::int from public.projects where id = '61000000-0000-0000-0000-0000000000f5'), 1,
  'editor A sees the in_progress project');
reset role;
select pg_temp.as_user('61000000-0000-0000-0000-000000000002');
select is(private.editor_project_stage('61000000-0000-0000-0000-0000000000f5'), 'none',
  'editor B has no stage on A''s project');
reset role;

-- ---------------------------------------------------------------------------
-- get_assignment_gate (call 11, Review Focus 7)
-- ---------------------------------------------------------------------------
select pg_temp.as_user('61000000-0000-0000-0000-00000000000a', 'aal2');
select is((select ready from public.get_assignment_gate('61000000-0000-0000-0000-0000000000a5')), true,
  'admin reads the gate');
select throws_ok($$ select * from public.get_assignment_gate(gen_random_uuid()) $$, 'ES422', 'Assignment not found.',
  'admin: an unknown assignment is not found');
reset role;
select pg_temp.as_user('61000000-0000-0000-0000-000000000001');
select is((select current_brief_version from public.get_assignment_gate('61000000-0000-0000-0000-0000000000a5')), 3,
  'the owning editor reads the gate');
select throws_ok($$ select * from public.get_assignment_gate('61000000-0000-0000-0000-0000000000b4') $$, 'ES422',
  'Assignment not found.', 'editor A cannot read another editor''s gate');
reset role;
select pg_temp.as_user('61000000-0000-0000-0000-000000000002');
select throws_ok($$ select * from public.get_assignment_gate('61000000-0000-0000-0000-0000000000a5') $$, 'ES422',
  'Assignment not found.', 'editor B gets not found for A''s assignment');
reset role;
select pg_temp.as_user('61000000-0000-0000-0000-000000000004');
select throws_ok($$ select * from public.get_assignment_gate('61000000-0000-0000-0000-0000000000a5') $$, 'ES422',
  null, 'a suspended editor gets not found');
reset role;
select pg_temp.as_user('61000000-0000-0000-0000-000000000003');
select throws_ok($$ select * from public.get_assignment_gate('61000000-0000-0000-0000-0000000000a5') $$, 'ES422',
  null, 'a pending applicant gets not found');
reset role;
select pg_temp.as_user('61000000-0000-0000-0000-00000000000a', 'aal1');
select throws_ok($$ select * from public.get_assignment_gate('61000000-0000-0000-0000-0000000000a5') $$, 'ES422',
  null, 'admin without MFA gets not found');
reset role;
select pg_temp.as_anon();
select throws_ok($$ select * from public.get_assignment_gate('61000000-0000-0000-0000-0000000000a5') $$, 'ES401',
  null, 'anon must sign in');
reset role;
update public.editor_profiles set access_status = 'suspended' where user_id = '61000000-0000-0000-0000-000000000001';
select pg_temp.as_user('61000000-0000-0000-0000-000000000001');
select throws_ok($$ select * from public.get_assignment_gate('61000000-0000-0000-0000-0000000000a5') $$, 'ES422',
  'Assignment not found.', 'editor A suspended after confirming gets not found (Review Focus 7)');
select is(private.editor_project_stage('61000000-0000-0000-0000-0000000000f5'), 'none',
  'a suspended editor has no stage, even in_progress');
reset role;

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------
select ok(not exists (select 1 from unnest(array[
    'private.material_brief_version(uuid)', 'private.latest_confirmation(uuid)', 'private.assignment_gate(uuid)',
    'private.gate_refusal(uuid, boolean)', 'private.guard_assignment_start()',
    'private.guard_project_in_progress()', 'private.carry_forward_confirmations()']) f
  where has_function_privilege('anon', f::regprocedure, 'execute')
     or has_function_privilege('authenticated', f::regprocedure, 'execute')),
  'the gate helpers and trigger functions are executable by no API role');
select ok(has_function_privilege('authenticated', 'private.editor_project_stage(uuid)', 'execute')
      and not has_function_privilege('anon', 'private.editor_project_stage(uuid)', 'execute'),
  'editor_project_stage stays executable by authenticated only');
select ok(has_function_privilege('anon', 'public.get_assignment_gate(uuid)', 'execute')
      and has_function_privilege('authenticated', 'public.get_assignment_gate(uuid)', 'execute'),
  'get_assignment_gate is executable by anon and authenticated (it authorises in its body)');

select * from finish();

rollback;
