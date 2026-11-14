-- Phase 7: editor_submit_interpretation and admin_review_interpretation, driven through the
-- Phase 6 functions to a confirmed assignment. Review Focus 1, 4, 5, 6, 7.
begin;

create extension if not exists pgtap with schema extensions;

select plan(48);

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

-- Creates and opens a project, offers it to the editor, the editor accepts, and (optionally) the
-- admin confirms. Returns the assignment id. Runs as postgres again afterwards.
create function pg_temp.assignment(p_title text, p_editor uuid, p_interp boolean, p_confirm boolean default true)
returns uuid language plpgsql as $$
declare
  v_project uuid;
  v_id uuid;
begin
  perform pg_temp.as_user('62000000-0000-0000-0000-00000000000a', 'aal2');
  v_project := public.admin_create_project(jsonb_build_object('title', p_title, 'brief_type', 'fully_instructed',
    'deadline', '2026-12-31', 'requires_interpretation', p_interp, 'brief', jsonb_build_object('instructions', 'Cut it'),
    'deliverables', jsonb_build_array(jsonb_build_object('name', 'Main'))));
  perform public.admin_set_project_status(v_project, 'open');
  v_id := public.admin_make_offer(v_project, p_editor, 10000, 'LKR');
  perform pg_temp.as_user(p_editor);
  perform public.editor_respond_offer(v_id, 'accept');
  if p_confirm then
    perform pg_temp.as_user('62000000-0000-0000-0000-00000000000a', 'aal2');
    perform public.admin_confirm_assignment(v_id);
  end if;
  reset role;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('62000000-0000-0000-0000-00000000000a', 'p7i-admin@test.local', '{}', '{}'),
  ('62000000-0000-0000-0000-000000000001', 'p7i-editor-a@test.local', '{}', '{}'),
  ('62000000-0000-0000-0000-000000000002', 'p7i-editor-b@test.local', '{}', '{}'),
  ('62000000-0000-0000-0000-000000000003', 'p7i-applicant@test.local', '{}', '{}');
select private.grant_admin_by_email('p7i-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('62000000-0000-0000-0000-000000000001', '62000000-0000-0000-0000-000000000002');

create temp table ids (kind text primary key, id uuid not null);
grant select, insert on ids to authenticated;
create function pg_temp.a(p_kind text) returns uuid language sql as $$ select id from ids where kind = p_kind $$;
grant execute on function pg_temp.a(text) to authenticated;
create function pg_temp.project(p_kind text) returns uuid language sql as $$
  select project_id from public.assignments where id = (select id from ids where kind = p_kind) $$;
grant execute on function pg_temp.project(text) to authenticated;

insert into ids select 'p', pg_temp.assignment('P interp', '62000000-0000-0000-0000-000000000001', true);
insert into ids select 'n', pg_temp.assignment('N no interp', '62000000-0000-0000-0000-000000000001', false);
insert into ids select 'x', pg_temp.assignment('X accepted', '62000000-0000-0000-0000-000000000001', true, false);
insert into ids select 'r', pg_temp.assignment('R archived', '62000000-0000-0000-0000-000000000001', true);
insert into ids select 's1', pg_temp.assignment('S1 stale true', '62000000-0000-0000-0000-000000000001', true);
insert into ids select 's2', pg_temp.assignment('S2 stale false', '62000000-0000-0000-0000-000000000001', true);
update public.projects set archived_at = now() where id = pg_temp.project('r');

-- ---------------------------------------------------------------------------
-- Submit, request changes, resubmit, accept
-- ---------------------------------------------------------------------------
select pg_temp.as_user('62000000-0000-0000-0000-000000000001');
insert into ids select 'i1', public.editor_submit_interpretation(pg_temp.a('p'), 1, '  Keep the pacing  ',
  'Swap the music', 'Is the logo final?');
reset role;
select ok((select status = 'submitted' and will_reproduce = 'Keep the pacing' and will_adapt = 'Swap the music'
    and questions_limitations = 'Is the logo final?' and submitted_by = '62000000-0000-0000-0000-000000000001'
    and brief_version_id = (select id from public.brief_versions where project_id = pg_temp.project('p') and version = 1)
  from public.editor_interpretations where id = pg_temp.a('i1')),
  'the submission is stored for the current version, trimmed, as submitted');
select ok((select (select array_agg(k order by k) from jsonb_object_keys(details) k)
    = array['assignment_id', 'brief_version', 'interpretation_id'] and details::text not like '%pacing%'
  from public.activity_logs where action = 'interpretation.submitted' and entity_id = pg_temp.a('i1')::text),
  'the submission is audited with ids and the version only');

select pg_temp.as_user('62000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_submit_interpretation(pg_temp.a('p'), 1, 'Again', null) $$, 'ES409',
  'Your interpretation is waiting for review.', 'a second submission while one is pending is refused');
reset role;

select pg_temp.as_user('62000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_review_interpretation(pg_temp.a('i1'), 'request_changes') $$, 'ES422', null,
  'request_changes needs feedback');
select throws_ok($$ select public.admin_review_interpretation(pg_temp.a('i1'), 'request_changes', '   ') $$, 'ES422',
  null, 'request_changes with blank feedback is refused');
select throws_ok($$ select public.admin_review_interpretation(pg_temp.a('i1'), null) $$, 'ES422', null,
  'a missing decision is refused');
select throws_ok($$ select public.admin_review_interpretation(pg_temp.a('i1'), 'Accept') $$, 'ES422', null,
  'decisions are case-sensitive');
select throws_ok($$ select public.admin_review_interpretation(pg_temp.a('i1'), 'reject') $$, 'ES422', null,
  'an unknown decision is refused');
select throws_ok($$ select public.admin_review_interpretation(gen_random_uuid(), 'accept') $$, 'ES422',
  'Interpretation not found.', 'an unknown interpretation id is refused');
select lives_ok($$ select public.admin_review_interpretation(pg_temp.a('i1'), 'request_changes', 'More detail please') $$,
  'admin requests changes with feedback');
select throws_ok($$ select public.admin_review_interpretation(pg_temp.a('i1'), 'accept') $$, 'ES409',
  'This interpretation has already been reviewed.', 'a reviewed interpretation cannot be reviewed again');
reset role;
select ok((select status = 'changes_requested' and admin_feedback = 'More detail please'
    and reviewed_by = '62000000-0000-0000-0000-00000000000a' and reviewed_at is not null
  from public.editor_interpretations where id = pg_temp.a('i1')), 'the review is stored');
select ok(exists (select 1 from public.activity_logs where action = 'interpretation.changes_requested'
  and entity_id = pg_temp.a('i1')::text and details::text not like '%detail%'), 'the review is audited without text');

select pg_temp.as_user('62000000-0000-0000-0000-000000000001');
select is((select admin_feedback from public.editor_interpretations where id = pg_temp.a('i1')), 'More detail please',
  'the editor reads the feedback through RLS');
insert into ids select 'i2', public.editor_submit_interpretation(pg_temp.a('p'), 1, 'Keep the pacing exactly', null);
reset role;
select ok((select status = 'changes_requested' and will_reproduce = 'Keep the pacing'
  from public.editor_interpretations where id = pg_temp.a('i1')), 'a resubmission leaves the old row unchanged');

select pg_temp.as_user('62000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok($$ select public.admin_review_interpretation(pg_temp.a('i2'), 'accept') $$, 'admin accepts');
select ok((select interpretation_accepted from public.get_assignment_gate(pg_temp.a('p'))),
  'the gate shows the interpretation accepted');
reset role;
select ok(exists (select 1 from public.activity_logs where action = 'interpretation.accepted'
  and entity_id = pg_temp.a('i2')::text), 'the acceptance is audited');

select pg_temp.as_user('62000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_submit_interpretation(pg_temp.a('p'), 1, 'Once more', null) $$, 'ES409',
  'Your interpretation has already been accepted.', 'no new submission once one is accepted and still valid');

-- ---------------------------------------------------------------------------
-- Input classes (Review Focus 1, 4) and states
-- ---------------------------------------------------------------------------
select throws_ok($$ select public.editor_submit_interpretation(pg_temp.a('s1'), null, 'x', null) $$, 'ES422', null,
  'a missing brief version is refused');
select throws_ok($$ select public.editor_submit_interpretation(pg_temp.a('s1'), 0, 'x', null) $$, 'ES422', null,
  'brief version 0 is refused');
select throws_ok($$ select public.editor_submit_interpretation(pg_temp.a('s1'), 5, 'x', null) $$, 'ES409', null,
  'a future brief version is refused');
select throws_ok($$ select public.editor_submit_interpretation(pg_temp.a('s1'), 1, null, null, null) $$, 'ES422', null,
  'all fields empty is refused');
select throws_ok($$ select public.editor_submit_interpretation(pg_temp.a('s1'), 1, null, null, 'Only a question') $$,
  'ES422', null, 'only questions is refused');
select throws_ok($$ select public.editor_submit_interpretation(pg_temp.a('s1'), 1, '   ', E'\n\t') $$, 'ES422', null,
  'whitespace-only fields count as empty');
select throws_ok($$ select public.editor_submit_interpretation(pg_temp.a('s1'), 1, repeat('x', 4001), null) $$,
  'ES422', null, 'more than 4000 characters is refused');
insert into ids select 'i_s1', public.editor_submit_interpretation(pg_temp.a('s1'), 1, 'Keep it', null, '   ');
reset role;
select ok((select questions_limitations is null and will_adapt is null from public.editor_interpretations
  where id = pg_temp.a('i_s1')), 'whitespace-only optional fields are stored as null');

select pg_temp.as_user('62000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_submit_interpretation(pg_temp.a('n'), 1, 'x', null) $$, 'ES409',
  'This project does not need an interpretation.', 'a project without requires_interpretation refuses submissions');
select throws_ok($$ select public.editor_submit_interpretation(pg_temp.a('x'), 1, 'x', null) $$, 'ES409', null,
  'an accepted (not confirmed) assignment refuses submissions');
select throws_ok($$ select public.editor_submit_interpretation(pg_temp.a('r'), 1, 'x', null) $$, 'ES409', null,
  'an archived project refuses submissions');
reset role;

-- Review Focus 6: another editor's or an unknown id gives the same message.
select pg_temp.as_user('62000000-0000-0000-0000-000000000002');
select throws_ok($$ select public.editor_submit_interpretation(pg_temp.a('s2'), 1, 'x', null) $$, 'ES422',
  'Assignment not found.', 'editor B cannot submit on A''s assignment');
select throws_ok($$ select public.editor_submit_interpretation(gen_random_uuid(), 1, 'x', null) $$, 'ES422',
  'Assignment not found.', 'an unknown assignment gives the same message');
reset role;

-- ---------------------------------------------------------------------------
-- Stale acceptance (call 7)
-- ---------------------------------------------------------------------------
select pg_temp.as_user('62000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_save_brief(pg_temp.project('s1'), '{"brief": {"instructions": "Cut it shorter"},
  "change_summary": "Shorter", "requires_reacknowledgement": true}');
select throws_ok($$ select public.admin_review_interpretation(pg_temp.a('i_s1'), 'accept') $$, 'ES409', null,
  'accepting an interpretation written before a material brief change is refused');
select lives_ok($$ select public.admin_review_interpretation(pg_temp.a('i_s1'), 'request_changes', 'Brief changed') $$,
  'requesting changes on it is allowed');
reset role;
select pg_temp.as_user('62000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_submit_interpretation(pg_temp.a('s1'), 1, 'x', null) $$, 'ES409',
  'The brief changed; review it again.', 'an older brief version is refused');
select lives_ok($$ select public.editor_submit_interpretation(pg_temp.a('s1'), 2, 'Keep it short', null) $$,
  'a submission for the current version is accepted');
insert into ids select 'i_s2', public.editor_submit_interpretation(pg_temp.a('s2'), 1, 'Keep it', null);
reset role;
select pg_temp.as_user('62000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_save_brief(pg_temp.project('s2'), '{"brief": {"instructions": "Cut it neatly"},
  "change_summary": "Wording", "requires_reacknowledgement": false}');
select lives_ok($$ select public.admin_review_interpretation(pg_temp.a('i_s2'), 'accept') $$,
  'a non-material brief change does not block acceptance');
reset role;

-- ---------------------------------------------------------------------------
-- Roles
-- ---------------------------------------------------------------------------
select pg_temp.as_anon();
select throws_ok($$ select public.editor_submit_interpretation(gen_random_uuid(), 1, 'x', null) $$, 'ES401', null,
  'anon cannot submit');
select throws_ok($$ select public.admin_review_interpretation(gen_random_uuid(), 'accept') $$, 'ES401', null,
  'anon cannot review');
reset role;
select pg_temp.as_user('62000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.admin_review_interpretation(pg_temp.a('i1'), 'accept') $$, 'ES403', null,
  'an editor cannot review');
select throws_ok($$ update public.editor_interpretations set status = 'accepted' where id = pg_temp.a('i1') $$,
  '42501', null, 'an editor cannot update interpretations directly');
reset role;
select pg_temp.as_user('62000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.editor_submit_interpretation(pg_temp.a('p'), 1, 'x', null) $$, 'ES403', null,
  'an admin cannot submit as an editor');
reset role;
select pg_temp.as_user('62000000-0000-0000-0000-00000000000a', 'aal1');
select throws_ok($$ select public.admin_review_interpretation(pg_temp.a('i1'), 'accept') $$, 'ES403', null,
  'admin without MFA cannot review');
select throws_ok($$ select public.editor_submit_interpretation(pg_temp.a('p'), 1, 'x', null) $$, 'ES403', null,
  'admin without MFA cannot submit');
reset role;
select pg_temp.as_user('62000000-0000-0000-0000-000000000003');
select throws_ok($$ select public.admin_review_interpretation(pg_temp.a('i1'), 'accept') $$, 'ES403', null,
  'an applicant cannot review');
select throws_ok($$ select public.editor_submit_interpretation(pg_temp.a('p'), 1, 'x', null) $$, 'ES403', null,
  'an applicant cannot submit');
reset role;
update public.editor_profiles set access_status = 'suspended' where user_id = '62000000-0000-0000-0000-000000000001';
select pg_temp.as_user('62000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_submit_interpretation(pg_temp.a('s2'), 1, 'x', null) $$, 'ES403', null,
  'a suspended editor cannot submit (Review Focus 7)');
select is((select count(*)::int from public.editor_interpretations), 0,
  'a suspended editor no longer sees their interpretations');
reset role;

select * from finish();

rollback;
