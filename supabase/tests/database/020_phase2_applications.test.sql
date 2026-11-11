-- Phase 2: editor application, vetting and access workflow. Decisions L, M, E.
-- Never calls a function an API role lacks EXECUTE on (see 000 guardrail note); every
-- public function is executable and authorises in its body with ES4xx errors.
begin;

create extension if not exists pgtap with schema extensions;

select plan(67);

-- Switch identity (call only while running as postgres; use `reset role` to switch back).
create function pg_temp.as_user(p_uid uuid, p_aal text default 'aal1')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('20000000-0000-0000-0000-00000000000a', 'p2-admin@test.local', '{}', '{}'),
  ('20000000-0000-0000-0000-000000000001', 'p2-editor-a@test.local', '{}', '{}'),
  ('20000000-0000-0000-0000-000000000003', 'p2-applicant@test.local', '{}', '{}'),
  ('20000000-0000-0000-0000-000000000005', 'p2-other@test.local', '{}', '{}');

select private.grant_admin_by_email('p2-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id = '20000000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------------
-- Applicant builds a profile (direct writes, limited by grants + RLS)
-- ---------------------------------------------------------------------------
select pg_temp.as_user('20000000-0000-0000-0000-000000000003');

select is((select count(*)::int from public.profile_options), 8, 'applicant sees the 8 active options');

select throws_ok(
  $$ select public.submit_editor_application('draft-0', 'draft-0') $$,
  'ES422', null, 'an incomplete application cannot be submitted');

select lives_ok($$
  update public.profiles set full_name = 'Test Applicant', phone = '+94 70 000 0000'
  where id = '20000000-0000-0000-0000-000000000003';
  update public.editor_profiles
  set region = 'Colombo', experience_years = 4, experience_summary = 'Weddings and reels',
      availability = 'Weekdays', typical_turnaround = '3 days'
  where user_id = '20000000-0000-0000-0000-000000000003';
$$, 'applicant can fill in their own profile fields');

select throws_ok($$
  insert into public.editor_portfolio_links (editor_id, url)
  values ('20000000-0000-0000-0000-000000000003', 'http://insecure.example/reel')
$$, '23514', null, 'portfolio links must be https');

select lives_ok($$
  insert into public.editor_portfolio_links (editor_id, url, label)
  values ('20000000-0000-0000-0000-000000000003', 'https://vimeo.com/123', 'Showreel')
$$, 'applicant can add an https portfolio link');

select lives_ok($$
  insert into public.editor_profile_options (editor_id, kind, code) values
    ('20000000-0000-0000-0000-000000000003', 'specialisation', 'short_form_social'),
    ('20000000-0000-0000-0000-000000000003', 'software', 'davinci_resolve')
$$, 'applicant can pick specialisations and software');

select throws_ok($$
  insert into public.editor_profile_options (editor_id, kind, code)
  values ('20000000-0000-0000-0000-000000000005', 'software', 'capcut')
$$, '42501', null, 'applicant cannot add options to someone else''s profile');

select throws_ok(
  $$ update public.editor_profiles set level = 'specialist' $$,
  '42501', null, 'applicant cannot set their own level');

select throws_ok(
  $$ select public.submit_editor_application('', 'draft-0') $$,
  'ES422', null, 'terms acceptance is required');

select lives_ok(
  $$ select public.submit_editor_application('draft-0', 'draft-0') $$,
  'a complete application can be submitted');

select is(
  (select status::text from public.editor_applications), 'submitted', 'application is submitted');

select is(
  (select submitted_snapshot ->> 'full_name' from public.editor_applications), 'Test Applicant',
  'submission stores a snapshot');

select throws_ok(
  $$ select public.submit_editor_application('draft-0', 'draft-0') $$,
  'ES409', null, 'cannot submit twice');

select throws_ok(
  $$ update public.editor_applications set status = 'approved' $$,
  '42501', null, 'applicant cannot change application status directly');

select throws_ok(
  $$ select public.admin_start_application_review(
       (select id from public.editor_applications limit 1)) $$,
  'ES403', null, 'applicant cannot call admin functions');

select is((select count(*)::int from public.editor_vetting_notes), 0, 'applicant sees no vetting notes');

reset role;

-- Other applicant and active editor A cannot see this application or its links.
select pg_temp.as_user('20000000-0000-0000-0000-000000000005');
select is((select count(*)::int from public.editor_applications), 0, 'another applicant sees no applications');
select is((select count(*)::int from public.editor_portfolio_links), 0, 'another applicant sees no portfolio links');
reset role;

select pg_temp.as_user('20000000-0000-0000-0000-000000000001');
select is((select count(*)::int from public.editor_applications), 0, 'editor A sees no applications');
reset role;

-- Admin without MFA is refused.
select pg_temp.as_user('20000000-0000-0000-0000-00000000000a', 'aal1');
select throws_ok(
  $$ select public.admin_start_application_review(
       (select id from public.editor_applications where editor_id = '20000000-0000-0000-0000-000000000003')) $$,
  'ES403', null, 'admin without MFA cannot review applications');
reset role;

-- Anonymous is refused.
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select throws_ok(
  $$ select public.submit_editor_application('draft-0', 'draft-0') $$,
  'ES401', null, 'anonymous users cannot submit an application');
reset role;

-- ---------------------------------------------------------------------------
-- Admin review: info request, test, approval
-- ---------------------------------------------------------------------------
create temp table app as
  select id from public.editor_applications where editor_id = '20000000-0000-0000-0000-000000000003';
grant select on app to authenticated;

select pg_temp.as_user('20000000-0000-0000-0000-00000000000a', 'aal2');

select lives_ok(
  $$ select public.admin_start_application_review((select id from app)) $$, 'admin starts review');
select is((select status::text from public.editor_applications where id = (select id from app)),
  'under_review', 'application is under review');

select lives_ok(
  $$ select public.admin_create_application_request((select id from app), 'info', 'Please share a long-form sample.') $$,
  'admin requests more information');
select is((select status::text from public.editor_applications where id = (select id from app)),
  'info_requested', 'application waits for information');

select lives_ok($$
  insert into public.editor_vetting_notes (application_id, author_id, note)
  values ((select id from app), '20000000-0000-0000-0000-00000000000a', 'Strong reels; check long-form.')
$$, 'admin records a vetting note');

reset role;

select pg_temp.as_user('20000000-0000-0000-0000-000000000003');
select is((select count(*)::int from public.application_requests), 1, 'applicant sees the request');
select lives_ok(
  $$ select public.respond_to_application_request(
       (select id from public.application_requests limit 1), 'Here is my documentary edit.',
       'https://vimeo.com/456') $$,
  'applicant responds to the request');
select is((select status::text from public.editor_applications), 'under_review',
  'answering the last open request returns the application to review');
select throws_ok(
  $$ select public.respond_to_application_request(
       (select id from public.application_requests limit 1), 'again', null) $$,
  'ES409', null, 'a request can only be answered once');
reset role;

select pg_temp.as_user('20000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok(
  $$ select public.admin_create_application_request((select id from app), 'test', 'Cut a 30s reel from the supplied clips.') $$,
  'admin requests a practical test');
select throws_ok(
  $$ select public.admin_approve_application((select id from app), 'professional') $$,
  'ES409', null, 'cannot approve while a request is outstanding');
reset role;

select pg_temp.as_user('20000000-0000-0000-0000-000000000003');
select lives_ok(
  $$ select public.respond_to_application_request(
       (select id from public.application_requests where kind = 'test'), null, 'https://drive.example.com/test') $$,
  'applicant submits the practical test link');
reset role;

select pg_temp.as_user('20000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok(
  $$ select public.admin_record_assessment_result(
       (select id from public.application_requests where application_id = (select id from app) and kind = 'test'),
       'passed', 'Clean pacing.') $$,
  'admin records the test result');
select throws_ok(
  $$ select public.admin_record_assessment_result(
       (select id from public.application_requests where application_id = (select id from app) and kind = 'info'),
       'passed', null) $$,
  'ES409', null, 'results can only be recorded on test requests');
select throws_ok(
  $$ select public.admin_approve_application((select id from app), null) $$,
  'ES422', null, 'approval requires a level');
select lives_ok(
  $$ select public.admin_approve_application((select id from app), 'professional', 'Welcome aboard.') $$,
  'admin approves the application');
select results_eq(
  $$ select access_status::text, level::text from public.editor_profiles
     where user_id = '20000000-0000-0000-0000-000000000003' $$,
  $$ values ('active', 'professional') $$,
  'approval activates editor access and sets the level');
select is((select count(*)::int from public.editor_vetting_notes where application_id = (select id from app)),
  1, 'admin sees vetting notes');
select throws_ok(
  $$ select public.admin_reject_application((select id from app), null) $$,
  'ES409', null, 'an approved application cannot be rejected');
reset role;

-- Snapshot is frozen.
select pg_temp.as_user('20000000-0000-0000-0000-000000000003');
select ok(private.is_active_editor(), 'the approved applicant is now an active editor');
update public.editor_profiles set experience_summary = 'Changed later'
where user_id = '20000000-0000-0000-0000-000000000003';
reset role;
select is(
  (select submitted_snapshot ->> 'experience_summary' from public.editor_applications where id = (select id from app)),
  'Weddings and reels', 'later profile edits do not change the submitted snapshot');

-- ---------------------------------------------------------------------------
-- Access transitions
-- ---------------------------------------------------------------------------
select pg_temp.as_user('20000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok(
  $$ select public.admin_set_editor_access('20000000-0000-0000-0000-000000000003', 'suspended', '') $$,
  'ES422', null, 'suspension requires a reason');
select lives_ok(
  $$ select public.admin_set_editor_access('20000000-0000-0000-0000-000000000003', 'suspended', 'Missed deadlines') $$,
  'admin suspends an editor');
select lives_ok(
  $$ select public.admin_set_editor_access('20000000-0000-0000-0000-000000000003', 'revoked', 'Contract ended') $$,
  'admin revokes a suspended editor');
select throws_ok(
  $$ select public.admin_set_editor_access('20000000-0000-0000-0000-000000000003', 'active', 'Try again') $$,
  'ES409', null, 'revocation is final');
select throws_ok(
  $$ select public.admin_set_editor_access('20000000-0000-0000-0000-000000000005', 'active', 'Skip review') $$,
  'ES409', null, 'access cannot be activated without an approved application');
reset role;

-- ---------------------------------------------------------------------------
-- Rejection and admin-only reopen (decision M)
-- ---------------------------------------------------------------------------
update public.profiles set full_name = 'Other', phone = '1' where id = '20000000-0000-0000-0000-000000000005';
update public.editor_profiles set region = 'Kandy', experience_years = 1, experience_summary = 'x',
  availability = 'x', typical_turnaround = 'x', software_other = 'Vegas'
  where user_id = '20000000-0000-0000-0000-000000000005';
insert into public.editor_portfolio_links (editor_id, url) values ('20000000-0000-0000-0000-000000000005', 'https://example.com/a');
insert into public.editor_profile_options (editor_id, kind, code) values ('20000000-0000-0000-0000-000000000005', 'specialisation', 'long_form');

select pg_temp.as_user('20000000-0000-0000-0000-000000000005');
select lives_ok($$ select public.submit_editor_application('draft-0', 'draft-0') $$, 'second applicant submits');
reset role;

select pg_temp.as_user('20000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok(
  $$ select public.admin_reject_application(
       (select id from public.editor_applications where editor_id = '20000000-0000-0000-0000-000000000005'), 'Not at this time.') $$,
  'admin rejects the second applicant');
reset role;

select pg_temp.as_user('20000000-0000-0000-0000-000000000005');
select throws_ok(
  $$ select public.submit_editor_application('draft-0', 'draft-0') $$,
  'ES409', null, 'a rejected applicant cannot re-apply on their own');
select throws_ok($$ select public.withdraw_editor_application() $$, 'ES409', null,
  'nothing to withdraw after rejection');
reset role;

select pg_temp.as_user('20000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok(
  $$ select public.admin_reopen_application('20000000-0000-0000-0000-000000000005') $$,
  'admin reopens the application');
reset role;

select pg_temp.as_user('20000000-0000-0000-0000-000000000005');
select lives_ok($$ select public.submit_editor_application('draft-0', 'draft-0') $$,
  'the reopened application can be submitted');
select results_eq(
  $$ select attempt::int, status::text from public.editor_applications order by attempt $$,
  $$ values (1, 'rejected'), (2, 'submitted') $$,
  'each attempt is kept as its own record');
select lives_ok($$ select public.withdraw_editor_application() $$, 'applicant can withdraw');
reset role;

-- ---------------------------------------------------------------------------
-- save_editor_profile (atomic profile save used by the app)
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data)
values ('20000000-0000-0000-0000-000000000006', 'p2-saver@test.local', '{}', '{}');

select pg_temp.as_user('20000000-0000-0000-0000-000000000006');
select lives_ok($$
  select public.save_editor_profile('Saver', '+94 71', 'Galle', 2::smallint, 'Docs', 'Evenings', '1 week',
    null, null, array['long_form'], array['capcut'],
    '[{"url":"https://example.com/one","label":"One"}]'::jsonb)
$$, 'applicant saves their profile atomically');
select is(
  (select count(*)::int from public.editor_portfolio_links), 1, 'saved links are stored for the caller only');
select throws_ok($$
  select public.save_editor_profile('Saver', null, null, null, null, null, null, null, null, null, null,
    '[{"url":"http://insecure.example"}]'::jsonb)
$$, 'ES422', null, 'insecure links are rejected');
select throws_ok($$
  select public.save_editor_profile('Saver', null, null, null, null, null, null, null, null, null, null,
    (select jsonb_agg(jsonb_build_object('url', 'https://example.com/' || g)) from generate_series(1, 11) g))
$$, 'ES422', null, 'more than 10 links are rejected');
reset role;

select is(
  (select full_name from public.profiles where id = '20000000-0000-0000-0000-000000000005'), 'Other',
  'saving a profile never touches another user''s data');

select pg_temp.as_user('20000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$
  select public.save_editor_profile('Admin', null, null, null, null, null, null, null, null, null, null, null)
$$, 'ES403', null, 'admin accounts have no editor profile to save');
reset role;

-- ---------------------------------------------------------------------------
-- Portfolio link limit and audit trail
-- ---------------------------------------------------------------------------
select pg_temp.as_user('20000000-0000-0000-0000-000000000003');
insert into public.editor_portfolio_links (editor_id, url)
  select '20000000-0000-0000-0000-000000000003', 'https://example.com/' || g from generate_series(1, 9) g;  -- 1 existing + 9 = 10
select throws_ok($$
  insert into public.editor_portfolio_links (editor_id, url)
  values ('20000000-0000-0000-0000-000000000003', 'https://example.com/eleven')
$$, 'ES422', null, 'at most 10 portfolio links');
reset role;

select ok(
  (select count(*) from public.activity_logs
   where entity_type = 'editor_application' and action in ('application.submitted', 'application.approved',
         'application.rejected', 'application.draft', 'application.withdrawn')) >= 6,
  'application status changes are audited');

-- ---------------------------------------------------------------------------
-- Account deletion anonymises the audit log instead of failing
-- ---------------------------------------------------------------------------
select lives_ok(
  $$ delete from auth.users where id = '20000000-0000-0000-0000-000000000005' $$,
  'an account with audit history can be deleted');
select ok(
  exists (select 1 from public.activity_logs
          where entity_id in (select id::text from public.editor_applications
                              where editor_id = '20000000-0000-0000-0000-000000000005')
             or details ->> 'editor_id' = '20000000-0000-0000-0000-000000000005'),
  'audit entries about the deleted account are kept');
select is(
  (select count(*)::int from public.activity_logs where actor_id = '20000000-0000-0000-0000-000000000005'),
  0, 'the deleted account is no longer linked as an actor');
select throws_ok(
  $$ update public.activity_logs set actor_id = null, action = 'tampered'
     where actor_id is not null $$,
  '42501', null, 'clearing the actor cannot be combined with other changes');

select * from finish();

rollback;
