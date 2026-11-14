-- Phase 7: schema. assignment_status.in_progress, editor_interpretations, brief_confirmations,
-- widened assignment constraints and indexes, insert checks, immutability guards and RLS.
begin;

create extension if not exists pgtap with schema extensions;

select plan(69);

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
    (select count(*)::int from public.editor_interpretations),
    (select count(*)::int from public.brief_confirmations)];
$$;
grant execute on function pg_temp.visible_counts() to authenticated;

-- ---------------------------------------------------------------------------
-- Enums and catalogue
-- ---------------------------------------------------------------------------
select enum_has_labels('public', 'assignment_status', array['offered', 'counteroffer_pending', 'accepted',
  'confirmed', 'in_progress', 'declined', 'withdrawn', 'not_selected', 'reassigned'], 'assignment_status labels');
select enum_has_labels('public', 'interpretation_status', array['submitted', 'accepted', 'changes_requested'],
  'interpretation_status labels');
select enum_has_labels('public', 'brief_confirmation_kind', array['confirmed', 'carried_forward'],
  'brief_confirmation_kind labels');
select has_column('public', 'assignments', 'started_at', 'assignments.started_at exists');
select has_column('public', 'assignments', 'started_by', 'assignments.started_by exists');
select has_table('public', 'editor_interpretations', 'editor_interpretations exists');
select has_table('public', 'brief_confirmations', 'brief_confirmations exists');
select ok((select array_agg(conname::text) from pg_constraint
  where conrelid in ('public.assignments'::regclass, 'public.editor_interpretations'::regclass,
                     'public.brief_confirmations'::regclass))
  @> array['assignments_agreed_chk', 'assignments_confirmed_chk', 'assignments_started_chk',
        'editor_interpretations_content_chk', 'editor_interpretations_review_chk', 'brief_confirmations_kind_chk'],
  'the named constraints exist');
select ok(to_regclass('public.assignments_one_active_key') is not null
      and to_regclass('public.assignments_one_confirmed_key') is null
      and to_regclass('public.assignments_live_key') is not null
      and to_regclass('public.editor_interpretations_pending_key') is not null
      and to_regclass('public.brief_confirmations_carried_key') is not null,
  'the one-active, live, pending and carried unique indexes exist (one-confirmed is gone)');

-- ---------------------------------------------------------------------------
-- Fixtures (as postgres)
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('60000000-0000-0000-0000-00000000000a', 'p7s-admin@test.local', '{}', '{}'),
  ('60000000-0000-0000-0000-000000000001', 'p7s-editor-a@test.local', '{}', '{}'),
  ('60000000-0000-0000-0000-000000000002', 'p7s-editor-b@test.local', '{}', '{}'),
  ('60000000-0000-0000-0000-000000000003', 'p7s-applicant@test.local', '{}', '{}'),
  ('60000000-0000-0000-0000-000000000004', 'p7s-suspended@test.local', '{}', '{}');
select private.grant_admin_by_email('p7s-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('60000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000002');
update public.editor_profiles set access_status = 'suspended'
where user_id = '60000000-0000-0000-0000-000000000004';

insert into public.projects (id, title, brief_type, status, first_opened_at, deadline) values
  ('60000000-0000-0000-0000-0000000000f1', 'P1', 'fully_instructed', 'assigned', now(), '2026-12-31'),
  ('60000000-0000-0000-0000-0000000000f2', 'P2', 'fully_instructed', 'assigned', now(), '2026-12-31'),
  ('60000000-0000-0000-0000-0000000000f3', 'P3', 'fully_instructed', 'open', now(), '2026-12-31'),
  ('60000000-0000-0000-0000-0000000000f4', 'P4', 'fully_instructed', 'open', now(), '2026-12-31'),
  ('60000000-0000-0000-0000-0000000000f5', 'P5', 'fully_instructed', 'open', now(), '2026-12-31');
insert into public.brief_versions (id, project_id, version, instructions) values
  ('60000000-0000-0000-0000-0000000000e1', '60000000-0000-0000-0000-0000000000f1', 1, 'Cut it'),
  ('60000000-0000-0000-0000-0000000000e2', '60000000-0000-0000-0000-0000000000f2', 1, 'Cut it'),
  ('60000000-0000-0000-0000-0000000000e3', '60000000-0000-0000-0000-0000000000f3', 1, 'Cut it');
insert into public.assignments (id, project_id, editor_id, status, proposed_amount, agreed_amount, agreed_currency,
  confirmed_at) values
  ('60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-0000000000f1',
   '60000000-0000-0000-0000-000000000001', 'confirmed', 10000, 10000, 'LKR', now()),
  ('60000000-0000-0000-0000-0000000000b1', '60000000-0000-0000-0000-0000000000f2',
   '60000000-0000-0000-0000-000000000002', 'confirmed', 10000, 10000, 'LKR', now()),
  ('60000000-0000-0000-0000-0000000000c1', '60000000-0000-0000-0000-0000000000f3',
   '60000000-0000-0000-0000-000000000004', 'accepted', 10000, 10000, 'LKR', null);
insert into public.editor_interpretations (id, assignment_id, brief_version_id, will_reproduce, submitted_by) values
  ('60000000-0000-0000-0000-0000000001a1', '60000000-0000-0000-0000-0000000000a1',
   '60000000-0000-0000-0000-0000000000e1', 'The pacing', '60000000-0000-0000-0000-000000000001'),
  ('60000000-0000-0000-0000-0000000001c1', '60000000-0000-0000-0000-0000000000c1',
   '60000000-0000-0000-0000-0000000000e3', 'The colour', '60000000-0000-0000-0000-000000000004');
insert into public.brief_confirmations (id, assignment_id, project_id, editor_id, brief_version_id, brief_version, kind,
  confirmed_deadline, confirmed_deliverables, confirmed_amount, confirmed_currency, created_by) values
  ('60000000-0000-0000-0000-0000000002a1', '60000000-0000-0000-0000-0000000000a1',
   '60000000-0000-0000-0000-0000000000f1', '60000000-0000-0000-0000-000000000001',
   '60000000-0000-0000-0000-0000000000e1', 1, 'confirmed', '2026-12-31', '[]', 10000, 'LKR',
   '60000000-0000-0000-0000-000000000001'),
  ('60000000-0000-0000-0000-0000000002c1', '60000000-0000-0000-0000-0000000000c1',
   '60000000-0000-0000-0000-0000000000f3', '60000000-0000-0000-0000-000000000004',
   '60000000-0000-0000-0000-0000000000e3', 1, 'confirmed', '2026-12-31', '[]', 10000, 'LKR',
   '60000000-0000-0000-0000-000000000004');

-- ---------------------------------------------------------------------------
-- Visibility and direct writes
-- ---------------------------------------------------------------------------
select pg_temp.as_anon();
select throws_ok($$ select 1 from public.editor_interpretations $$, '42501', null,
  'anon cannot read editor_interpretations');
select throws_ok($$ select 1 from public.brief_confirmations $$, '42501', null, 'anon cannot read brief_confirmations');
reset role;

select pg_temp.as_user('60000000-0000-0000-0000-000000000001');
select is(pg_temp.visible_counts(), array[1,1], 'editor A sees only their own rows');
select ok((select bool_and(assignment_id = '60000000-0000-0000-0000-0000000000a1') from public.editor_interpretations)
      and (select bool_and(editor_id = '60000000-0000-0000-0000-000000000001') from public.brief_confirmations),
  'the rows editor A sees are their own');
select throws_ok($$ insert into public.editor_interpretations (assignment_id, brief_version_id, will_reproduce)
  values ('60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-0000000000e1', 'x') $$,
  '42501', null, 'editor A cannot insert interpretations directly');
select throws_ok($$ update public.editor_interpretations set status = 'accepted' $$, '42501', null,
  'editor A cannot update interpretations directly');
select throws_ok($$ delete from public.editor_interpretations $$, '42501', null,
  'editor A cannot delete interpretations directly');
select throws_ok($$ insert into public.brief_confirmations (assignment_id, project_id, editor_id, brief_version_id,
  brief_version, kind, confirmed_deadline, confirmed_deliverables, confirmed_amount, confirmed_currency)
  values ('60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-0000000000f1',
  '60000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-0000000000e1', 1, 'confirmed', '2026-12-31',
  '[]', 1, 'LKR') $$, '42501', null, 'editor A cannot insert confirmations directly');
select throws_ok($$ update public.brief_confirmations set confirmed_amount = 1 $$, '42501', null,
  'editor A cannot update confirmations directly');
select throws_ok($$ delete from public.brief_confirmations $$, '42501', null,
  'editor A cannot delete confirmations directly');
reset role;

select pg_temp.as_user('60000000-0000-0000-0000-000000000002');
select is(pg_temp.visible_counts(), array[0,0], 'editor B sees none of these rows');
reset role;
select pg_temp.as_user('60000000-0000-0000-0000-000000000004');
select is(pg_temp.visible_counts(), array[0,0], 'a suspended editor sees none of these rows, even their own');
reset role;
select pg_temp.as_user('60000000-0000-0000-0000-000000000003');
select is(pg_temp.visible_counts(), array[0,0], 'a pending applicant sees none of these rows');
reset role;
select pg_temp.as_user('60000000-0000-0000-0000-00000000000a', 'aal1');
select is(pg_temp.visible_counts(), array[0,0], 'admin without MFA sees none of these rows');
reset role;

select pg_temp.as_user('60000000-0000-0000-0000-00000000000a', 'aal2');
select is(pg_temp.visible_counts(), array[2,2], 'admin with MFA sees every row');
select throws_ok($$ insert into public.editor_interpretations (assignment_id, brief_version_id, will_reproduce)
  values ('60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-0000000000e1', 'x') $$,
  '42501', null, 'admin cannot insert interpretations directly');
select throws_ok($$ update public.editor_interpretations set status = 'accepted' $$, '42501', null,
  'admin cannot update interpretations directly');
select throws_ok($$ delete from public.editor_interpretations $$, '42501', null,
  'admin cannot delete interpretations directly');
select throws_ok($$ insert into public.brief_confirmations (assignment_id, project_id, editor_id, brief_version_id,
  brief_version, kind, confirmed_deadline, confirmed_deliverables, confirmed_amount, confirmed_currency)
  values ('60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-0000000000f1',
  '60000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-0000000000e1', 1, 'confirmed', '2026-12-31',
  '[]', 1, 'LKR') $$, '42501', null, 'admin cannot insert confirmations directly');
select throws_ok($$ update public.brief_confirmations set confirmed_amount = 1 $$, '42501', null,
  'admin cannot update confirmations directly');
select throws_ok($$ delete from public.brief_confirmations $$, '42501', null,
  'admin cannot delete confirmations directly');
reset role;

-- ---------------------------------------------------------------------------
-- Assignment constraints (as postgres)
-- ---------------------------------------------------------------------------
select throws_ok($$ insert into public.assignments (project_id, editor_id, status, proposed_amount, agreed_amount,
  agreed_currency, confirmed_at) values ('60000000-0000-0000-0000-0000000000f4',
  '60000000-0000-0000-0000-000000000001', 'in_progress', 1000, 1000, 'LKR', now()) $$,
  '23514', null, 'in_progress needs started_at');
select throws_ok($$ insert into public.assignments (project_id, editor_id, status, proposed_amount, agreed_amount,
  agreed_currency, started_at) values ('60000000-0000-0000-0000-0000000000f4',
  '60000000-0000-0000-0000-000000000001', 'in_progress', 1000, 1000, 'LKR', now()) $$,
  '23514', null, 'in_progress needs confirmed_at');
select throws_ok($$ insert into public.assignments (project_id, editor_id, status, proposed_amount, confirmed_at,
  started_at) values ('60000000-0000-0000-0000-0000000000f4',
  '60000000-0000-0000-0000-000000000001', 'in_progress', 1000, now(), now()) $$,
  '23514', null, 'in_progress needs an agreed amount');
insert into public.assignments (project_id, editor_id, status, proposed_amount, agreed_amount, agreed_currency,
  confirmed_at) values ('60000000-0000-0000-0000-0000000000f4', '60000000-0000-0000-0000-000000000001',
  'confirmed', 1000, 1000, 'LKR', now());
select throws_ok($$ insert into public.assignments (project_id, editor_id, status, proposed_amount, agreed_amount,
  agreed_currency, confirmed_at, started_at) values ('60000000-0000-0000-0000-0000000000f4',
  '60000000-0000-0000-0000-000000000002', 'in_progress', 1000, 1000, 'LKR', now(), now()) $$,
  '23505', null, 'a confirmed and an in_progress assignment cannot share a project');
insert into public.assignments (project_id, editor_id, status, proposed_amount, agreed_amount, agreed_currency,
  confirmed_at, started_at) values ('60000000-0000-0000-0000-0000000000f5', '60000000-0000-0000-0000-000000000001',
  'in_progress', 1000, 1000, 'LKR', now(), now());
select throws_ok($$ insert into public.assignments (project_id, editor_id, status, proposed_amount, agreed_amount,
  agreed_currency, confirmed_at, started_at) values ('60000000-0000-0000-0000-0000000000f5',
  '60000000-0000-0000-0000-000000000002', 'in_progress', 1000, 1000, 'LKR', now(), now()) $$,
  '23505', null, 'two in_progress assignments cannot share a project');
select throws_ok($$ insert into public.assignments (project_id, editor_id, proposed_amount)
  values ('60000000-0000-0000-0000-0000000000f5', '60000000-0000-0000-0000-000000000001', 1000) $$,
  '23505', null, 'an in_progress assignment is live: no second live row for the same project and editor');

-- ---------------------------------------------------------------------------
-- Interpretations (as postgres)
-- ---------------------------------------------------------------------------
select throws_ok($$ insert into public.editor_interpretations (assignment_id, brief_version_id, questions_limitations)
  values ('60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-0000000000e1', 'Why?') $$,
  '23514', null, 'an interpretation needs what will be reproduced or adapted');
select throws_ok($$ insert into public.editor_interpretations (assignment_id, brief_version_id, will_adapt, status,
  reviewed_at) values ('60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-0000000000e1', 'x',
  'changes_requested', now()) $$,
  '23514', null, 'changes_requested needs feedback');
select throws_ok($$ insert into public.editor_interpretations (assignment_id, brief_version_id, will_adapt)
  values ('60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-0000000000e1', 'x') $$,
  '23505', null, 'at most one submitted interpretation per assignment');
select throws_ok($$ insert into public.editor_interpretations (assignment_id, brief_version_id, will_adapt)
  values ('60000000-0000-0000-0000-0000000000b1', '60000000-0000-0000-0000-0000000000e1', 'x') $$,
  'ES409', null, 'the brief version must belong to the assignment''s project');
select lives_ok($$ update public.editor_interpretations
  set status = 'accepted', reviewed_by = '60000000-0000-0000-0000-00000000000a', reviewed_at = now()
  where id = '60000000-0000-0000-0000-0000000001a1' $$, 'one review update (submitted to accepted) is allowed');
select lives_ok($$ insert into public.editor_interpretations (id, assignment_id, brief_version_id, will_adapt,
  submitted_by) values ('60000000-0000-0000-0000-0000000001a2', '60000000-0000-0000-0000-0000000000a1',
  '60000000-0000-0000-0000-0000000000e1', 'The music', '60000000-0000-0000-0000-000000000001') $$,
  'a new submission is allowed once the previous one is reviewed');
select throws_ok($$ update public.editor_interpretations set status = 'submitted', reviewed_by = null,
  reviewed_at = null where id = '60000000-0000-0000-0000-0000000001a1' $$, 'ES409', null,
  'a reviewed interpretation cannot go back to submitted');
select throws_ok($$ update public.editor_interpretations set will_reproduce = 'Changed'
  where id = '60000000-0000-0000-0000-0000000001a1' $$, 'ES409', null, 'reviewed content cannot change');
select throws_ok($$ update public.editor_interpretations set admin_feedback = 'Later'
  where id = '60000000-0000-0000-0000-0000000001a1' $$, 'ES409', null, 'feedback cannot change after the review');
select throws_ok($$ update public.editor_interpretations set will_adapt = 'Changed'
  where id = '60000000-0000-0000-0000-0000000001a2' $$, 'ES409', null, 'submitted content cannot change');
select throws_ok($$ update public.editor_interpretations set status = 'accepted', reviewed_at = now(),
  will_adapt = 'Changed' where id = '60000000-0000-0000-0000-0000000001a2' $$, 'ES409', null,
  'a review cannot change the content');
select throws_ok($$ delete from public.editor_interpretations where id = '60000000-0000-0000-0000-0000000001a2' $$,
  'ES409', null, 'an interpretation cannot be deleted, even by postgres');
select throws_ok($$ update public.editor_interpretations set submitted_by = null, will_reproduce = 'Changed'
  where id = '60000000-0000-0000-0000-0000000001a1' $$, 'ES409', null,
  'clearing submitted_by together with another column is refused');
select lives_ok($$ update public.editor_interpretations set submitted_by = null
  where id = '60000000-0000-0000-0000-0000000001a2' $$, 'clearing only submitted_by is allowed (account deletion)');
select lives_ok($$ update public.editor_interpretations set reviewed_by = null
  where id = '60000000-0000-0000-0000-0000000001a1' $$, 'clearing only reviewed_by is allowed (account deletion)');

-- ---------------------------------------------------------------------------
-- Brief confirmations (as postgres)
-- ---------------------------------------------------------------------------
select throws_ok($$ insert into public.brief_confirmations (assignment_id, project_id, editor_id, brief_version_id,
  brief_version, kind, confirmed_deadline, confirmed_deliverables, confirmed_amount, confirmed_currency)
  values ('60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-0000000000f1',
  '60000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-0000000000e1', 1, 'carried_forward',
  '2026-12-31', '[]', 10000, 'LKR') $$, '23514', null, 'a carried-forward row needs carried_from_id');
select throws_ok($$ insert into public.brief_confirmations (assignment_id, project_id, editor_id, brief_version_id,
  brief_version, kind, carried_from_id, confirmed_deadline, confirmed_deliverables, confirmed_amount,
  confirmed_currency) values ('60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-0000000000f1',
  '60000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-0000000000e1', 1, 'confirmed',
  '60000000-0000-0000-0000-0000000002a1', '2026-12-31', '[]', 10000, 'LKR') $$, '23514', null,
  'a confirmed row has no carried_from_id');
select throws_ok($$ insert into public.brief_confirmations (assignment_id, project_id, editor_id, brief_version_id,
  brief_version, kind, confirmed_deadline, confirmed_deliverables, confirmed_amount, confirmed_currency)
  values ('60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-0000000000f2',
  '60000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-0000000000e1', 1, 'confirmed',
  '2026-12-31', '[]', 10000, 'LKR') $$, 'ES409', null, 'project_id must be the assignment''s project');
select throws_ok($$ insert into public.brief_confirmations (assignment_id, project_id, editor_id, brief_version_id,
  brief_version, kind, confirmed_deadline, confirmed_deliverables, confirmed_amount, confirmed_currency)
  values ('60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-0000000000f1',
  '60000000-0000-0000-0000-000000000002', '60000000-0000-0000-0000-0000000000e1', 1, 'confirmed',
  '2026-12-31', '[]', 10000, 'LKR') $$, 'ES409', null, 'editor_id must be the assignment''s editor');
select throws_ok($$ insert into public.brief_confirmations (assignment_id, project_id, editor_id, brief_version_id,
  brief_version, kind, confirmed_deadline, confirmed_deliverables, confirmed_amount, confirmed_currency)
  values ('60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-0000000000f1',
  '60000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-0000000000e1', 2, 'confirmed',
  '2026-12-31', '[]', 10000, 'LKR') $$, 'ES409', null, 'brief_version must be the version number of the row');
select throws_ok($$ insert into public.brief_confirmations (assignment_id, project_id, editor_id, brief_version_id,
  brief_version, kind, confirmed_deadline, confirmed_deliverables, confirmed_amount, confirmed_currency)
  values ('60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-0000000000f1',
  '60000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-0000000000e2', 1, 'confirmed',
  '2026-12-31', '[]', 10000, 'LKR') $$, 'ES409', null, 'the brief version must belong to the project');
select throws_ok($$ update public.brief_confirmations set confirmed_deadline = '2027-01-31'
  where id = '60000000-0000-0000-0000-0000000002a1' $$, 'ES409', null, 'a confirmation cannot be changed');
select throws_ok($$ delete from public.brief_confirmations where id = '60000000-0000-0000-0000-0000000002a1' $$,
  'ES409', null, 'a confirmation cannot be deleted, even by postgres');
select throws_ok($$ update public.brief_confirmations set created_by = null, confirmed_amount = 1
  where id = '60000000-0000-0000-0000-0000000002a1' $$, 'ES409', null,
  'clearing created_by together with another column is refused');
select lives_ok($$ update public.brief_confirmations set created_by = null
  where id = '60000000-0000-0000-0000-0000000002a1' $$, 'clearing only created_by is allowed (account deletion)');
select lives_ok($$ insert into public.brief_confirmations (assignment_id, project_id, editor_id, brief_version_id,
  brief_version, kind, carried_from_id, confirmed_deadline, confirmed_deliverables, confirmed_amount,
  confirmed_currency) values ('60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-0000000000f1',
  '60000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-0000000000e1', 1, 'carried_forward',
  '60000000-0000-0000-0000-0000000002a1', '2026-12-31', '[]', 10000, 'LKR') $$,
  'a carried-forward row pointing at its source is accepted');
select throws_ok($$ insert into public.brief_confirmations (assignment_id, project_id, editor_id, brief_version_id,
  brief_version, kind, carried_from_id, confirmed_deadline, confirmed_deliverables, confirmed_amount,
  confirmed_currency) values ('60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-0000000000f1',
  '60000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-0000000000e1', 1, 'carried_forward',
  '60000000-0000-0000-0000-0000000002a1', '2026-12-31', '[]', 10000, 'LKR') $$, '23505', null,
  'at most one carried-forward row per assignment and brief version');
select throws_ok($$ delete from public.brief_versions where id = '60000000-0000-0000-0000-0000000000e1' $$,
  'ES409', null, 'a confirmed brief version cannot be deleted (its own guard)');
alter table public.brief_versions disable trigger brief_versions_guard;
select throws_ok($$ delete from public.brief_versions where id = '60000000-0000-0000-0000-0000000000e1' $$,
  '23503', null, 'without the guard the foreign key still refuses deleting a confirmed brief version');
alter table public.brief_versions enable trigger brief_versions_guard;
select ok(exists (select 1 from public.brief_versions where id = '60000000-0000-0000-0000-0000000000e1'),
  'the brief version is still there');

select col_default_is('public', 'brief_confirmations', 'confirmed_at', 'clock_timestamp()',
  'confirmed_at defaults to clock_timestamp() so rows in one transaction stay ordered');

-- An editor loses sight of their confirmations once the project is cancelled (stage 'none').
select pg_temp.as_user('60000000-0000-0000-0000-000000000001');
select ok((select count(*) from public.brief_confirmations) > 0, 'editor A sees their confirmations on P1');
reset role;
update public.projects set status = 'cancelled' where id = '60000000-0000-0000-0000-0000000000f1';
select pg_temp.as_user('60000000-0000-0000-0000-000000000001');
select is((select count(*)::int from public.brief_confirmations), 0,
  'editor A sees no confirmations once P1 is cancelled');
reset role;

select * from finish();

rollback;
