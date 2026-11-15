-- Phase 8: submit, review outcomes, rounds and the allowance flag, acknowledgement, dispute and
-- classification, approval (payment not_due -> pending_approval), completion, cancel/reassign.
begin;

create extension if not exists pgtap with schema extensions;

select plan(69);

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

create function pg_temp.started(p_title text, p_editor uuid, p_deadline date default '2099-12-31',
  p_start boolean default true)
returns uuid language plpgsql as $$
declare
  v_project uuid;
  v_id uuid;
begin
  perform pg_temp.as_user('81000000-0000-0000-0000-00000000000a', 'aal2');
  v_project := public.admin_create_project(jsonb_build_object('title', p_title, 'brief_type', 'fully_instructed',
    'deadline', p_deadline, 'brief', jsonb_build_object('instructions', 'Cut it'),
    'deliverables', jsonb_build_array(jsonb_build_object('name', 'Main'))));
  perform public.admin_set_project_status(v_project, 'open');
  perform public.admin_agree_terms(v_project, 1);
  perform pg_temp.verify_deposit(v_project);
  v_id := public.admin_make_offer(v_project, p_editor, 10000, 'LKR');
  perform pg_temp.as_user(p_editor);
  perform public.editor_respond_offer(v_id, 'accept');
  perform pg_temp.as_user('81000000-0000-0000-0000-00000000000a', 'aal2');
  perform public.admin_confirm_assignment(v_id);
  perform pg_temp.as_user(p_editor);
  perform public.editor_confirm_brief(v_id, 1, p_deadline, 10000, 'LKR');
  if p_start then
    perform public.editor_start_work(v_id);
  end if;
  reset role;
  return v_id;
end;
$$;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('81000000-0000-0000-0000-00000000000a', 'p8w-admin@test.local', '{}', '{}'),
  ('81000000-0000-0000-0000-000000000001', 'p8w-editor-a@test.local', '{}', '{}'),
  ('81000000-0000-0000-0000-000000000002', 'p8w-editor-b@test.local', '{}', '{}');
select private.grant_admin_by_email('p8w-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('81000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000002');

create temp table ids (kind text primary key, id uuid not null);
grant select, insert, update on ids to authenticated;
create function pg_temp.a(p_kind text) returns uuid language sql as $$ select id from ids where kind = p_kind $$;
grant execute on function pg_temp.a(text) to authenticated;
create function pg_temp.pstatus(p_kind text) returns text language sql as $$
  select p.status::text from public.projects p join public.assignments a on a.project_id = p.id
  where a.id = (select id from ids where kind = p_kind) $$;
create function pg_temp.rstatus(p_kind text) returns text language sql as $$
  select status::text from public.revision_requests where id = (select id from ids where kind = p_kind) $$;
-- Submit as editor A on assignment p_asg, remember the id under p_kind.
create function pg_temp.submit(p_asg text, p_kind text) returns void language plpgsql as $$
begin
  perform pg_temp.as_user('81000000-0000-0000-0000-000000000001');
  insert into ids select p_kind, public.editor_submit_work(pg_temp.a(p_asg), 'https://drive.example/' || p_kind);
  reset role;
end;
$$;
-- Review as admin; remember the request id (if any) under p_kind.
create function pg_temp.review(p_sub text, p_outcome text, p_type text, p_kind text) returns void
language plpgsql as $$
declare
  v uuid;
begin
  perform pg_temp.as_user('81000000-0000-0000-0000-00000000000a', 'aal2');
  v := public.admin_review_submission(pg_temp.a(p_sub), p_outcome,
    case when p_outcome = 'approved' then null else 'Feedback' end, p_type,
    case when p_outcome = 'approved' then null else 'Reason' end);
  if v is not null then
    insert into ids values (p_kind, v);
  end if;
  reset role;
end;
$$;

insert into ids select 'p', pg_temp.started('P', '81000000-0000-0000-0000-000000000001');
insert into ids select 'c', pg_temp.started('C', '81000000-0000-0000-0000-000000000001', '2099-12-31', false);
insert into ids select 'late', pg_temp.started('Late', '81000000-0000-0000-0000-000000000001', '2020-01-01');
insert into ids select 'x', pg_temp.started('X', '81000000-0000-0000-0000-000000000001');
insert into ids select 'y', pg_temp.started('Y', '81000000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------------
-- Submit refusals
-- ---------------------------------------------------------------------------
select pg_temp.as_user('81000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_submit_work(pg_temp.a('c'), 'https://drive.example/c') $$, 'ES409',
  'You can submit work once work has started.', 'submit before start is refused');
select throws_ok($$ select public.editor_submit_work(pg_temp.a('p'), 'http://drive.example/p') $$, 'ES422',
  'Submission links must start with https:// and be at most 2048 characters.', 'http links are refused');
select throws_ok($$ select public.editor_submit_work(pg_temp.a('p'), '  ') $$, 'ES422',
  'Submission links must start with https:// and be at most 2048 characters.', 'an empty link is refused');
select throws_ok($$ select public.editor_submit_work(pg_temp.a('p'), 'https://d.example', repeat('n', 4001)) $$, 'ES422',
  'The notes can be at most 4000 characters.', 'long notes are refused');
select pg_temp.as_user('81000000-0000-0000-0000-000000000002');
select throws_ok($$ select public.editor_submit_work(pg_temp.a('p'), 'https://drive.example/p') $$, 'ES422',
  'Assignment not found.', 'another editor cannot submit on the assignment');
reset role;

-- ---------------------------------------------------------------------------
-- First submission
-- ---------------------------------------------------------------------------
select pg_temp.as_user('81000000-0000-0000-0000-000000000001');
insert into ids select 's1', public.editor_submit_work(pg_temp.a('p'), ' https://drive.example/v1 ', ' Notes ', '4K ProRes');
reset role;
select is((select (version, link, notes, export_details, is_late, confirmed_deadline, outcome)::text
  from public.submissions where id = pg_temp.a('s1')),
  '(1,https://drive.example/v1,Notes,"4K ProRes",f,2099-12-31,)', 'version 1 stored trimmed, on time, unreviewed');
select is(pg_temp.pstatus('p'), 'in_review', 'the project moves to in_review');
select is((select status::text from public.assignments where id = pg_temp.a('p')), 'in_progress',
  'the assignment stays in_progress');
select pg_temp.as_user('81000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_submit_work(pg_temp.a('p'), 'https://drive.example/again') $$, 'ES409',
  'Your previous submission is still being reviewed.', 'a second submission while one is pending is refused');
reset role;
select pg_temp.submit('late', 'sl');
select is((select is_late from public.submissions where id = pg_temp.a('sl')), true,
  'a submission after the confirmed deadline is flagged late');

-- ---------------------------------------------------------------------------
-- Review refusals
-- ---------------------------------------------------------------------------
select pg_temp.as_user('81000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_review_submission(pg_temp.a('s1'), 'nonsense', 'F', 'client_revision', 'R') $$,
  'ES422', 'Please choose a review outcome.', 'an unknown outcome is refused');
select throws_ok($$ select public.admin_review_submission(pg_temp.a('s1'), 'revision_requested', null, 'client_revision', 'R') $$,
  'ES422', 'Feedback for the editor is required unless you approve.', 'feedback is required');
select throws_ok($$ select public.admin_review_submission(pg_temp.a('s1'), 'revision_requested', 'F', 'scope_change', 'R') $$,
  'ES422', 'A revision request is a client revision or an editor correction.', 'scope_change is not a revision type here');
select throws_ok($$ select public.admin_review_submission(pg_temp.a('s1'), 'revision_requested', 'F', null, 'R') $$,
  'ES422', 'A revision request is a client revision or an editor correction.', 'a revision needs a type');
select throws_ok($$ select public.admin_review_submission(pg_temp.a('s1'), 'revision_requested', 'F', 'client_revision', ' ') $$,
  'ES422', 'Please give the reason for this change request.', 'a reason is required');
select throws_ok($$ select public.admin_review_submission(gen_random_uuid(), 'approved') $$,
  'ES422', 'Submission not found.', 'an unknown submission is refused');
reset role;

-- ---------------------------------------------------------------------------
-- Round 1: client revision, acknowledge, start, resubmit
-- ---------------------------------------------------------------------------
select pg_temp.review('s1', 'revision_requested', 'client_revision', 'r1');
select is((select (type, counts_against_allowance, round_number, beyond_allowance, status, reason)::text
  from public.revision_requests where id = pg_temp.a('r1')),
  '(client_revision,t,1,f,requested,Reason)', 'round 1 recorded as a counted client revision');
select is((select (outcome, feedback)::text from public.submissions where id = pg_temp.a('s1')),
  '(revision_requested,Feedback)', 'the submission keeps its outcome and feedback');
select is(pg_temp.pstatus('p'), 'revision_requested', 'the project moves to revision_requested');
select pg_temp.as_user('81000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_review_submission(pg_temp.a('s1'), 'approved') $$, 'ES409',
  'This submission has already been reviewed.', 'a reviewed submission cannot be reviewed again');
select pg_temp.as_user('81000000-0000-0000-0000-000000000002');
select throws_ok($$ select public.editor_acknowledge_revision(pg_temp.a('r1')) $$, 'ES422',
  'Change request not found.', 'another editor cannot acknowledge');
select pg_temp.as_user('81000000-0000-0000-0000-000000000001');
select lives_ok($$ select public.editor_acknowledge_revision(pg_temp.a('r1')) $$, 'editor acknowledges');
select is(pg_temp.rstatus('r1'), 'acknowledged', 'request acknowledged');
select throws_ok($$ select public.editor_acknowledge_revision(pg_temp.a('r1')) $$, 'ES409',
  'This change request has already been acknowledged.', 'acknowledging twice is refused');
select lives_ok($$ select public.editor_acknowledge_revision(pg_temp.a('r1'), true) $$, 'editor starts the revision');
select is(pg_temp.rstatus('r1'), 'in_progress', 'request in progress');
reset role;
select pg_temp.submit('p', 's2');
select is((select (version, revision_request_id = pg_temp.a('r1'))::text from public.submissions where id = pg_temp.a('s2')),
  '(2,t)', 'version 2 answers round 1');
select is(pg_temp.rstatus('r1'), 'resubmitted', 'the request moves to resubmitted');
select is(pg_temp.pstatus('p'), 'in_review', 'the project is back in review');

-- ---------------------------------------------------------------------------
-- Corrections and scope changes do not consume rounds; rounds beyond the allowance are flagged
-- ---------------------------------------------------------------------------
select pg_temp.review('s2', 'revision_requested', 'editor_correction', 'r2');
select is((select (type, counts_against_allowance, round_number, beyond_allowance)::text
  from public.revision_requests where id = pg_temp.a('r2')), '(editor_correction,f,,f)', 'a correction has no round');
select is(pg_temp.rstatus('r1'), 'resubmitted', 'the superseded request stays resubmitted');
select pg_temp.submit('p', 's3');
select pg_temp.review('s3', 'scope_change_required', 'client_revision', 'r3');
select is((select (type, round_number)::text from public.revision_requests where id = pg_temp.a('r3')),
  '(scope_change,)', 'scope_change_required always records a scope change without a round');
select pg_temp.submit('p', 's4');
select pg_temp.review('s4', 'revision_requested', 'client_revision', 'r4');
select pg_temp.submit('p', 's5');
select pg_temp.review('s5', 'revision_requested', 'client_revision', 'r5');
select pg_temp.submit('p', 's6');
select pg_temp.review('s6', 'revision_requested', 'client_revision', 'r6');
select is((select string_agg(round_number::text || ':' || beyond_allowance::text, ',' order by created_at, id)
  from public.revision_requests where project_id = (select project_id from public.assignments where id = pg_temp.a('p'))
    and type = 'client_revision'), '1:false,2:false,3:false,4:true', 'rounds 1-3 included, round 4 flagged beyond');
select is((select version from public.submissions where id = pg_temp.a('s6')), 6, 'six versions kept');
select is((select count(*)::int from public.submissions
  where project_id = (select project_id from public.assignments where id = pg_temp.a('p'))), 6, 'history never overwritten');

-- Reclassification renumbers and refuses closed requests.
select pg_temp.as_user('81000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_classify_revision(pg_temp.a('r4'), 'editor_correction', 'Our mistake') $$,
  'ES409', 'Only an open change request can be reclassified.', 'a resubmitted request cannot be reclassified');
select throws_ok($$ select public.admin_classify_revision(pg_temp.a('r6'), 'bogus', 'x') $$,
  'ES422', 'Please choose client revision, editor correction or scope change.', 'an unknown type is refused');
select lives_ok($$ select public.admin_classify_revision(pg_temp.a('r6'), 'editor_correction', 'Editor missed the brief') $$,
  'admin reclassifies the open request');
select is((select (type, round_number, beyond_allowance, reason, classified_by is not null)::text
  from public.revision_requests where id = pg_temp.a('r6')),
  '(editor_correction,,f,"Editor missed the brief",t)', 'the correction drops the round and the flag');
select lives_ok($$ select public.admin_classify_revision(pg_temp.a('r6'), 'client_revision', 'Client after all') $$,
  'admin reclassifies back');
select is((select (round_number, beyond_allowance)::text from public.revision_requests where id = pg_temp.a('r6')),
  '(4,t)', 'renumbered as round 4 again');
reset role;

-- ---------------------------------------------------------------------------
-- Rejected / needs discussion: disputed until classified
-- ---------------------------------------------------------------------------
select pg_temp.submit('p', 's7');
select pg_temp.review('s7', 'rejected_needs_discussion', 'scope_change', 'r7');
select is((select (type, status)::text from public.revision_requests where id = pg_temp.a('r7')),
  '(scope_change,disputed)', 'needs discussion opens a disputed request with the provisional type');
select pg_temp.as_user('81000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_submit_work(pg_temp.a('p'), 'https://drive.example/s8') $$, 'ES409',
  'Lenscape is still discussing this change request. Please wait before resubmitting.', 'no resubmission while disputed');
select throws_ok($$ select public.editor_acknowledge_revision(pg_temp.a('r7')) $$, 'ES409',
  'Lenscape is still discussing this change request.', 'no acknowledgement while disputed');
select pg_temp.as_user('81000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_classify_revision(pg_temp.a('r7'), 'editor_correction', 'Agreed: editor fix');
select is(pg_temp.rstatus('r7'), 'requested', 'classification resolves the dispute');
reset role;

-- Material change after start: re-confirmation is required before the next submission.
select pg_temp.as_user('81000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_update_project((select project_id from public.assignments where id = pg_temp.a('p')),
  '{"deadline": "2099-11-30"}');
select pg_temp.as_user('81000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_submit_work(pg_temp.a('p'), 'https://drive.example/s8') $$, 'ES409',
  'The deadline or pay changed since you confirmed. Please confirm again.', 'submission requires the gate');
select public.editor_confirm_brief(pg_temp.a('p'), 1, '2099-11-30', 10000, 'LKR');
reset role;
select pg_temp.submit('p', 's8');
select is((select confirmed_deadline::text from public.submissions where id = pg_temp.a('s8')), '2099-11-30',
  'the re-confirmed deadline is copied');

-- ---------------------------------------------------------------------------
-- Approve, payment, complete
-- ---------------------------------------------------------------------------
-- Phase 12D: default 50/50 editor milestones; the 100% client deposit is verified, so milestone 1
-- became payable at confirmation and milestone 2 waits for approval.
select is((select string_agg(milestone_seq || ':' || status || ':' || coalesce(payable_reason::text, '-'), ',' order by milestone_seq)
  from public.payments where assignment_id = pg_temp.a('p')), '1:pending_approval:client_deposit_verified,2:not_due:-',
  'before approval only milestone 1 is payable');
select pg_temp.review('s8', 'approved', null, 'none');
select is((select (outcome, feedback)::text from public.submissions where id = pg_temp.a('s8')), '(approved,)',
  'approved without feedback');
select is(pg_temp.rstatus('r7'), 'approved', 'the answered request is approved');
select is(pg_temp.pstatus('p'), 'approved', 'the project is approved');
select is((select status::text || ':' || payable_reason::text || ':' || amount::text from public.payments
  where assignment_id = pg_temp.a('p') and milestone_seq = 2), 'pending_approval:client_balance_verified:5000.00',
  'approval moves milestone 2 to pending_approval (the client balance is in; amount unchanged)');
select pg_temp.as_user('81000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_submit_work(pg_temp.a('p'), 'https://drive.example/s9') $$, 'ES409',
  'This project is not accepting submissions.', 'no submissions after approval');
select pg_temp.as_user('81000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_complete_project((select project_id from public.assignments where id = pg_temp.a('late'))) $$,
  'ES409', 'Only an approved project can be completed.', 'an in-review project cannot be completed');
select lives_ok($$ select public.admin_complete_project((select project_id from public.assignments where id = pg_temp.a('p'))) $$,
  'admin completes the approved project');
select is(pg_temp.pstatus('p'), 'completed', 'the project is completed');
select throws_ok($$ select public.admin_complete_project((select project_id from public.assignments where id = pg_temp.a('p'))) $$,
  'ES409', 'Only an approved project can be completed.', 'completing twice is refused');

-- admin_approve_project shortcut
select throws_ok($$ select public.admin_approve_project((select project_id from public.assignments where id = pg_temp.a('x'))) $$,
  'ES409', 'There is no submission waiting for review.', 'approve needs a pending submission');
reset role;
select pg_temp.submit('x', 'sx');
select pg_temp.as_user('81000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok($$ select public.admin_approve_project((select project_id from public.assignments where id = pg_temp.a('x')), 'Great') $$,
  'approve project shortcut');
select is((select (outcome, feedback)::text from public.submissions where id = pg_temp.a('sx')), '(approved,Great)',
  'the shortcut approves the pending submission with feedback');

-- Cancel from in_review and reassign from revision_requested
select lives_ok($$ select public.admin_set_project_status((select project_id from public.assignments where id = pg_temp.a('late')), 'cancelled') $$,
  'an in-review project can be cancelled');
select is((select status::text from public.assignments where id = pg_temp.a('late')), 'withdrawn',
  'cancellation withdraws the assignment');
reset role;
select pg_temp.submit('y', 'sy');
select pg_temp.review('sy', 'revision_requested', 'client_revision', 'ry');
select pg_temp.as_user('81000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok($$ select public.admin_reassign(pg_temp.a('y')) $$, 'a project in revision can be reassigned');
select is(pg_temp.pstatus('y'), 'open', 'reassignment reopens the project');
-- Open requests stay with the closed assignment (history) and can no longer be classified.
select throws_ok($$ select public.admin_classify_revision(pg_temp.a('ry'), 'editor_correction', 'Too late') $$,
  'ES409', 'This change request belongs to an assignment that is no longer active.',
  'a request on a reassigned assignment cannot be classified');
select is(pg_temp.rstatus('ry'), 'requested', 'the old request is left as history');

-- Archive: completed and cancelled projects can be archived; approved (live) work cannot.
select throws_ok($$ select public.admin_archive_project((select project_id from public.assignments where id = pg_temp.a('x')), true) $$,
  'ES409', 'Cancel or finish the assignment before archiving.', 'an approved, not completed project cannot be archived');
select lives_ok($$ select public.admin_archive_project((select project_id from public.assignments where id = pg_temp.a('p')), true) $$,
  'a completed project can be archived');
select lives_ok($$ select public.admin_archive_project((select project_id from public.assignments where id = pg_temp.a('late')), true) $$,
  'a cancelled project can be archived');
reset role;

select * from finish();
rollback;
