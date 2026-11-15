-- Phase 8: submissions and revision_requests schema, constraints, guard triggers and the RLS
-- matrix (admin aal2, admin aal1, editor A, editor B, pending applicant, anon).
begin;

create extension if not exists pgtap with schema extensions;

select plan(43);

-- Phase 12C: work needs a verified client deposit (KB9b-4). Runs as the admin.
create function pg_temp.verify_deposit(p_project uuid) returns void language plpgsql as $$
declare
  v uuid;
begin
  perform public.admin_update_project(p_project, '{"client_price": 20000}');
  perform public.admin_create_client_milestones(p_project, '{100}');
  select id into v from public.client_milestones where project_id = p_project and kind = 'deposit' and voided_at is null;
  perform public.admin_record_client_payment(v, 'TEST-DEPOSIT');
  perform public.admin_verify_client_payment(v);
end;
$$;
grant execute on function pg_temp.verify_deposit(uuid) to authenticated;

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

-- An in-progress assignment for p_editor (brief confirmed, work started).
create function pg_temp.started(p_title text, p_editor uuid)
returns uuid language plpgsql as $$
declare
  v_project uuid;
  v_id uuid;
begin
  perform pg_temp.as_user('80000000-0000-0000-0000-00000000000a', 'aal2');
  v_project := public.admin_create_project(jsonb_build_object('title', p_title, 'brief_type', 'fully_instructed',
    'deadline', '2099-12-31', 'brief', jsonb_build_object('instructions', 'Cut it'),
    'deliverables', jsonb_build_array(jsonb_build_object('name', 'Main'))));
  perform public.admin_set_project_status(v_project, 'open');
  perform public.admin_agree_terms(v_project, 1);
  perform pg_temp.verify_deposit(v_project);
  v_id := public.admin_make_offer(v_project, p_editor, 10000, 'LKR');
  perform pg_temp.as_user(p_editor);
  perform public.editor_respond_offer(v_id, 'accept');
  perform pg_temp.as_user('80000000-0000-0000-0000-00000000000a', 'aal2');
  perform public.admin_confirm_assignment(v_id);
  perform pg_temp.as_user(p_editor);
  perform public.editor_confirm_brief(v_id, 1, '2099-12-31', 10000, 'LKR');
  perform public.editor_start_work(v_id);
  reset role;
  return v_id;
end;
$$;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('80000000-0000-0000-0000-00000000000a', 'p8s-admin@test.local', '{}', '{}'),
  ('80000000-0000-0000-0000-000000000001', 'p8s-editor-a@test.local', '{}', '{}'),
  ('80000000-0000-0000-0000-000000000002', 'p8s-editor-b@test.local', '{}', '{}'),
  ('80000000-0000-0000-0000-000000000003', 'p8s-applicant@test.local', '{}', '{}');
select private.grant_admin_by_email('p8s-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('80000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000002');

create temp table ids (kind text primary key, id uuid not null);
grant select, insert on ids to authenticated, anon;

-- ---------------------------------------------------------------------------
-- Catalogue
-- ---------------------------------------------------------------------------
select has_table('public', 'submissions', 'submissions exists');
select has_table('public', 'revision_requests', 'revision_requests exists');
select enum_has_labels('public', 'submission_outcome',
  array['approved', 'revision_requested', 'rejected_needs_discussion', 'scope_change_required'], 'outcome enum');
select enum_has_labels('public', 'revision_type', array['client_revision', 'editor_correction', 'scope_change'],
  'revision type enum');
select enum_has_labels('public', 'revision_status',
  array['requested', 'acknowledged', 'in_progress', 'resubmitted', 'approved', 'disputed'], 'revision status enum');
select columns_are('public', 'submissions', array['id', 'assignment_id', 'project_id', 'editor_id', 'version', 'link',
  'notes', 'export_details', 'revision_request_id', 'confirmed_deadline', 'is_late', 'submitted_by', 'submitted_at',
  'outcome', 'feedback', 'reviewed_by', 'reviewed_at', 'created_at'], 'submissions columns');
select columns_are('public', 'revision_requests', array['id', 'project_id', 'assignment_id', 'submission_id', 'type',
  'counts_against_allowance', 'round_number', 'beyond_allowance', 'reason', 'status', 'acknowledged_at',
  'resubmitted_at', 'resolved_at', 'created_by', 'classified_by', 'classified_at', 'created_at', 'updated_at'],
  'revision_requests columns');
select ok((select relrowsecurity from pg_class where oid = 'public.submissions'::regclass), 'RLS on submissions');
select ok((select relrowsecurity from pg_class where oid = 'public.revision_requests'::regclass),
  'RLS on revision_requests');
select set_eq($$ select tablename::text || '.' || cmd from pg_policies
  where schemaname = 'public' and tablename in ('submissions', 'revision_requests') $$,
  array['submissions.SELECT', 'revision_requests.SELECT'], 'one select-only policy per table');
select ok(not has_table_privilege('authenticated', 'public.submissions', 'insert')
  and not has_table_privilege('authenticated', 'public.submissions', 'update')
  and not has_table_privilege('authenticated', 'public.submissions', 'delete')
  and not has_table_privilege('authenticated', 'public.revision_requests', 'insert')
  and not has_table_privilege('authenticated', 'public.revision_requests', 'update')
  and not has_table_privilege('authenticated', 'public.revision_requests', 'delete'), 'no write grants');
select ok(not has_table_privilege('anon', 'public.submissions', 'select')
  and not has_table_privilege('anon', 'public.revision_requests', 'select'), 'anon has no select');
select is_empty($$ select table_name || '.' || column_name from information_schema.columns
  where table_schema = 'public' and table_name in ('submissions', 'revision_requests')
    and column_name ~ '(client|email|phone|company|contact|price|margin|amount|_fee)' $$,
  'no client, pricing or money columns');

-- ---------------------------------------------------------------------------
-- Data: A submits on P, admin requests a client revision; B has project Q with a submission.
-- ---------------------------------------------------------------------------
insert into ids select 'p', pg_temp.started('P', '80000000-0000-0000-0000-000000000001');
insert into ids select 'q', pg_temp.started('Q', '80000000-0000-0000-0000-000000000002');
select pg_temp.as_user('80000000-0000-0000-0000-000000000001');
insert into ids select 'sp', public.editor_submit_work((select id from ids where kind = 'p'), 'https://drive.example/v1',
  'First cut', '1080p H.264');
select pg_temp.as_user('80000000-0000-0000-0000-000000000002');
insert into ids select 'sq', public.editor_submit_work((select id from ids where kind = 'q'), 'https://drive.example/q1');
select pg_temp.as_user('80000000-0000-0000-0000-00000000000a', 'aal2');
insert into ids select 'rp', public.admin_review_submission((select id from ids where kind = 'sp'), 'revision_requested',
  'Tighten the intro', 'client_revision', 'Client asked for a shorter intro');
reset role;

-- ---------------------------------------------------------------------------
-- RLS matrix
-- ---------------------------------------------------------------------------
select pg_temp.as_user('80000000-0000-0000-0000-00000000000a', 'aal2');
select is((select count(*)::int from public.submissions where id in (select id from ids)), 2, 'admin aal2 sees both submissions');
select is((select count(*)::int from public.revision_requests where id in (select id from ids)), 1, 'admin aal2 sees the request');
select pg_temp.as_user('80000000-0000-0000-0000-00000000000a', 'aal1');
select is((select count(*)::int from public.submissions), 0, 'admin aal1 sees no submissions');
select is((select count(*)::int from public.revision_requests), 0, 'admin aal1 sees no requests');
select pg_temp.as_user('80000000-0000-0000-0000-000000000001');
select is((select array_agg(id) from public.submissions), (select array_agg(id) from ids where kind = 'sp'),
  'editor A sees only her submission');
select is((select count(*)::int from public.revision_requests), 1, 'editor A sees her revision request');
select pg_temp.as_user('80000000-0000-0000-0000-000000000002');
select is((select array_agg(id) from public.submissions), (select array_agg(id) from ids where kind = 'sq'),
  'editor B sees only his submission');
select is((select count(*)::int from public.revision_requests), 0, 'editor B sees no revision requests of A');
select pg_temp.as_user('80000000-0000-0000-0000-000000000003');
select is((select count(*)::int from public.submissions), 0, 'pending applicant sees no submissions');
select is((select count(*)::int from public.revision_requests), 0, 'pending applicant sees no requests');
select pg_temp.as_anon();
select throws_ok($$ select count(*) from public.submissions $$, '42501', null, 'anon cannot read submissions');
select throws_ok($$ select count(*) from public.revision_requests $$, '42501', null, 'anon cannot read requests');
reset role;

-- Suspended editor loses visibility; cancelled project hides history from the editor.
update public.editor_profiles set access_status = 'suspended' where user_id = '80000000-0000-0000-0000-000000000002';
select pg_temp.as_user('80000000-0000-0000-0000-000000000002');
select is((select count(*)::int from public.submissions), 0, 'a suspended editor sees no submissions');
reset role;
update public.editor_profiles set access_status = 'active' where user_id = '80000000-0000-0000-0000-000000000002';

-- Editor writes are refused.
select pg_temp.as_user('80000000-0000-0000-0000-000000000001');
select throws_ok($$ update public.submissions set link = 'https://x.example' $$, '42501', null,
  'editor cannot update submissions directly');
select throws_ok($$ update public.revision_requests set status = 'approved' $$, '42501', null,
  'editor cannot update revision requests directly');
reset role;

-- ---------------------------------------------------------------------------
-- Constraints and guards (table owner)
-- ---------------------------------------------------------------------------
select throws_ok($$ update public.submissions set link = 'https://other.example' where id = (select id from ids where kind = 'sp') $$,
  'ES409', 'This submission cannot be changed.', 'submission content is immutable');
select throws_ok($$ delete from public.submissions where id = (select id from ids where kind = 'sp') $$,
  'ES409', 'This history cannot be deleted.', 'submissions cannot be deleted');
select throws_ok($$ update public.submissions set outcome = 'approved', reviewed_at = now() where id = (select id from ids where kind = 'sp') $$,
  'ES409', 'This submission cannot be changed.', 'a reviewed submission cannot be reviewed again');
select throws_ok($$ delete from public.revision_requests where id = (select id from ids where kind = 'rp') $$,
  'ES409', 'This history cannot be deleted.', 'revision requests cannot be deleted');
select throws_ok($$ update public.revision_requests set submission_id = (select id from ids where kind = 'sq')
  where id = (select id from ids where kind = 'rp') $$,
  'ES409', 'This part of a revision request cannot change.', 'revision request links are immutable');
select throws_ok($$ update public.revision_requests set status = 'approved' where id = (select id from ids where kind = 'rp') $$,
  'ES409', 'This change request cannot move from requested to approved.', 'invalid revision status moves are refused');
select throws_ok($$ insert into public.submissions (assignment_id, project_id, editor_id, version, link, confirmed_deadline, is_late)
  values ((select id from ids where kind = 'p'), (select project_id from public.assignments where id = (select id from ids where kind = 'q')),
  '80000000-0000-0000-0000-000000000001', 9, 'https://x.example', '2099-12-31', false) $$,
  'ES409', 'A submission must match its assignment.', 'a submission must match its assignment');
select throws_ok($$ insert into public.submissions (assignment_id, project_id, editor_id, version, link, confirmed_deadline, is_late)
  select a.id, a.project_id, a.editor_id, 9, 'http://x.example', '2099-12-31', false from public.assignments a
  where a.id = (select id from ids where kind = 'q') $$,
  '23514', null, 'submission links must be https');
select throws_ok($$ insert into public.revision_requests (project_id, assignment_id, submission_id, type, reason)
  select a.project_id, a.id, (select id from ids where kind = 'sq'), 'client_revision', 'x' from public.assignments a
  where a.id = (select id from ids where kind = 'q') $$,
  '23514', null, 'a client revision needs a round number');
select throws_ok($$ insert into public.revision_requests (project_id, assignment_id, submission_id, type, round_number, reason)
  select a.project_id, a.id, (select id from ids where kind = 'sq'), 'editor_correction', 1, 'x' from public.assignments a
  where a.id = (select id from ids where kind = 'q') $$,
  '23514', null, 'a correction has no round number');
select is((select counts_against_allowance from public.revision_requests where id = (select id from ids where kind = 'rp')),
  true, 'a client revision counts against the allowance (generated)');
select throws_ok($$ update public.projects set status = 'approved'
  where id = (select project_id from public.assignments where id = (select id from ids where kind = 'q')) $$,
  'ES409', null, 'a project cannot be approved without an approved submission, even by the table owner');
select throws_ok($$ update public.projects set status = 'completed'
  where id = (select project_id from public.assignments where id = (select id from ids where kind = 'q')) $$,
  'ES409', null, 'a project cannot be completed unless approved');
select throws_ok($$ update public.projects set status = 'revision_requested'
  where id = (select project_id from public.assignments where id = (select id from ids where kind = 'q')) $$,
  'ES409', null, 'revision_requested needs an open revision request');
select lives_ok($$ update public.submissions set submitted_by = null where id = (select id from ids where kind = 'sq') $$,
  'clearing an actor column (on delete set null) is allowed');

select * from finish();
rollback;
