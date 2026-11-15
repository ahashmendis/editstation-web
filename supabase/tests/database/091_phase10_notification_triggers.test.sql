-- Phase 10: notifications written from the audit trail (KB10 event set), admin fan-out, outbox.
begin;

create extension if not exists pgtap with schema extensions;

select plan(24);

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

create function pg_temp.state_as(p_uid uuid, p_aal text, p_sql text)
returns text language plpgsql as $$
declare
  v text;
begin
  begin
    if p_uid is null then perform pg_temp.as_anon(); else perform pg_temp.as_user(p_uid, p_aal); end if;
    execute p_sql;
    raise exception 'rollback' using errcode = 'EST00';
  exception when others then
    v := case when sqlstate = 'EST00' then 'ok' else sqlstate end;
  end;
  reset role;
  return v;
end;
$$;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('91000000-0000-0000-0000-00000000000a', 'p10t-admin-a@test.local', '{}', '{}'),
  ('91000000-0000-0000-0000-00000000000b', 'p10t-admin-b@test.local', '{}', '{}'),
  ('91000000-0000-0000-0000-00000000000c', 'p10t-admin-c@test.local', '{}', '{}'),
  ('91000000-0000-0000-0000-000000000001', 'p10t-editor-a@test.local', '{}', '{}'),
  ('91000000-0000-0000-0000-000000000002', 'p10t-editor-b@test.local', '{}', '{}'),
  ('91000000-0000-0000-0000-000000000003', 'p10t-applicant@test.local', '{}', '{}');
select private.grant_admin_by_email('p10t-admin-a@test.local', 'test');
select private.grant_admin_by_email('p10t-admin-b@test.local', 'test');
select private.grant_admin_by_email('p10t-admin-c@test.local', 'test');
update public.admin_users set revoked_at = now() where user_id = '91000000-0000-0000-0000-00000000000c';
update public.editor_profiles set access_status = 'active'
where user_id in ('91000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000002');
-- Count only this file's recipients (admins from seed data also receive admin notifications).
create temp view mine as select * from public.notifications where recipient_id::text like '91000000-%';
create temp view admins_mine as select * from mine
  where recipient_id in ('91000000-0000-0000-0000-00000000000a', '91000000-0000-0000-0000-00000000000b');

insert into public.projects (id, title, brief_type, status, first_opened_at) values
  ('91000000-0000-0000-0000-0000000000f1', 'Notify Project', 'fully_instructed', 'open', now());
insert into public.assignments (id, project_id, editor_id, status, proposed_amount) values
  ('91000000-0000-0000-0000-0000000000b1', '91000000-0000-0000-0000-0000000000f1',
   '91000000-0000-0000-0000-000000000001', 'offered', 5000);

-- To admins: new inquiry (real insert through the audit trigger)
insert into public.client_inquiries (id, contact_name, email, service_type_code, service_type_label,
  description, budget_label, privacy_notice_version)
values ('91000000-0000-0000-0000-0000000000e1', 'Secret Client', 'secret@client.example', 'long_form',
  'Long-form video', 'Confidential brief.', 'Prefer to discuss', 'v');
select is((select count(*)::int from admins_mine where kind = 'inquiry_new'
    and entity_type = 'client_inquiry' and entity_id = '91000000-0000-0000-0000-0000000000e1'), 2,
  'a new inquiry notifies both active admins');
select is((select count(*)::int from mine where recipient_id = '91000000-0000-0000-0000-00000000000c'), 0,
  'a revoked admin is not notified');
select is((select count(*)::int from public.notifications where title || body ~* 'secret|confidential'), 0,
  'inquiry notifications carry no client data');

-- To admins: new application; to applicant: test request; to admins: applicant response
insert into public.editor_applications (id, editor_id, status, submitted_at) values
  ('91000000-0000-0000-0000-0000000000a1', '91000000-0000-0000-0000-000000000003', 'submitted', now());
select is((select count(*)::int from admins_mine where kind = 'application_new'
    and entity_id = '91000000-0000-0000-0000-0000000000a1'), 2, 'a submitted application notifies admins');
insert into public.application_requests (id, application_id, kind, message) values
  ('91000000-0000-0000-0000-0000000000c1', '91000000-0000-0000-0000-0000000000a1', 'test', 'Do a test edit.');
select is((select title from mine where kind = 'application_request'
    and recipient_id = '91000000-0000-0000-0000-000000000003'), 'Practical test requested',
  'a test request notifies the applicant');
update public.application_requests set response = 'Done', responded_at = now()
where id = '91000000-0000-0000-0000-0000000000c1';
select is((select count(*)::int from admins_mine where kind = 'applicant_response'
    and entity_id = '91000000-0000-0000-0000-0000000000a1'), 2, 'an applicant response notifies admins');

-- To applicant: decisions
insert into public.activity_logs (action, entity_type, entity_id, details) values
  ('application.rejected', 'editor_application', '91000000-0000-0000-0000-0000000000a1',
   '{"editor_id": "91000000-0000-0000-0000-000000000003"}');
select is((select count(*)::int from mine where kind = 'application_decision'
    and recipient_id = '91000000-0000-0000-0000-000000000003'), 1, 'a decision notifies the applicant');
insert into public.activity_logs (action, entity_type, entity_id, details) values
  ('application.approved', 'editor_application', '91000000-0000-0000-0000-0000000000a1',
   '{"editor_id": "91000000-0000-0000-0000-000000000003"}');
select ok((select bool_or(title ilike '%approved%') from mine where kind = 'application_decision'),
  'an approval says approved');

-- To editor: invitation (invited only)
insert into public.activity_logs (action, entity_type, entity_id, details) values
  ('project_access.granted', 'project_access', gen_random_uuid()::text, jsonb_build_object(
    'project_id', '91000000-0000-0000-0000-0000000000f1', 'editor_id', '91000000-0000-0000-0000-000000000001', 'reason', 'invited'));
select ok((select count(*) = 1 and bool_and(entity_type = 'project' and entity_id = '91000000-0000-0000-0000-0000000000f1'
    and body like '%Notify Project%') from mine where kind = 'invitation'),
  'an invitation notifies the editor, naming the project');
insert into public.activity_logs (action, entity_type, entity_id, details) values
  ('project_access.granted', 'project_access', gen_random_uuid()::text, jsonb_build_object(
    'project_id', '91000000-0000-0000-0000-0000000000f1', 'editor_id', '91000000-0000-0000-0000-000000000002', 'reason', 'available'));
select is((select count(*)::int from mine where kind = 'invitation'), 1, 'marking available is not an invitation');

-- Assignment, submission, revision and payment events
insert into public.activity_logs (action, entity_type, entity_id, details) values
  ('assignment.counteroffer_pending', 'assignment', '91000000-0000-0000-0000-0000000000b1', jsonb_build_object(
    'project_id', '91000000-0000-0000-0000-0000000000f1', 'editor_id', '91000000-0000-0000-0000-000000000001'));
select is((select count(*)::int from admins_mine where kind = 'counteroffer'
    and entity_id = '91000000-0000-0000-0000-0000000000f1'), 2, 'a counteroffer notifies admins');
insert into public.activity_logs (action, entity_type, entity_id, details) values
  ('assignment.confirmed', 'assignment', '91000000-0000-0000-0000-0000000000b1', jsonb_build_object(
    'project_id', '91000000-0000-0000-0000-0000000000f1', 'editor_id', '91000000-0000-0000-0000-000000000001'));
select is((select recipient_id from mine where kind = 'assignment_confirmed'), '91000000-0000-0000-0000-000000000001'::uuid,
  'a confirmation notifies the editor');
insert into public.activity_logs (action, entity_type, entity_id, details) values
  ('submission.submitted', 'submission', gen_random_uuid()::text, jsonb_build_object(
    'assignment_id', '91000000-0000-0000-0000-0000000000b1', 'project_id', '91000000-0000-0000-0000-0000000000f1', 'version', 1));
select is((select count(*)::int from admins_mine where kind = 'submission'
    and entity_id = '91000000-0000-0000-0000-0000000000f1'), 2, 'a submission notifies admins');
insert into public.activity_logs (action, entity_type, entity_id, details) values
  ('revision_request.created', 'revision_request', gen_random_uuid()::text, jsonb_build_object(
    'assignment_id', '91000000-0000-0000-0000-0000000000b1', 'project_id', '91000000-0000-0000-0000-0000000000f1'));
select is((select recipient_id from mine where kind = 'revision_requested'), '91000000-0000-0000-0000-000000000001'::uuid,
  'a revision request notifies the assignment''s editor');
insert into public.activity_logs (action, entity_type, entity_id, details) values
  ('payment.paid', 'payment', '91000000-0000-0000-0000-0000000000d1', jsonb_build_object(
    'payment_id', '91000000-0000-0000-0000-0000000000d1', 'assignment_id', '91000000-0000-0000-0000-0000000000b1'));
select ok((select count(*) = 1 and bool_and(recipient_id = '91000000-0000-0000-0000-000000000001'
    and entity_type = 'payment' and entity_id = '91000000-0000-0000-0000-0000000000d1')
  from mine where kind = 'payment_paid'), 'marking paid notifies the editor');

-- Other actions notify nobody
select is((select count(*)::int from mine), 17, 'running total before unrelated actions');
insert into public.activity_logs (action, entity_type, entity_id, details) values
  ('project.created', 'project', '91000000-0000-0000-0000-0000000000f1', '{}'),
  ('payment.approved', 'payment', gen_random_uuid()::text, '{"assignment_id": "91000000-0000-0000-0000-0000000000b1"}'),
  ('assignment.offered', 'assignment', '91000000-0000-0000-0000-0000000000b1', '{}');
select is((select count(*)::int from mine), 17, 'unrelated actions create no notifications');

-- Malformed details never block the audited action
select lives_ok($$insert into public.activity_logs (action, entity_type, entity_id, details) values
  ('submission.submitted', 'submission', 'not-a-uuid', '{"project_id": "garbage"}')$$,
  'malformed details do not roll back the logged action');
select is((select count(*)::int from mine), 17, 'malformed details create no notification');

-- Recipients and outbox
select is((select count(*)::int from mine where recipient_id = '91000000-0000-0000-0000-000000000002'), 0,
  'editor B receives none of editor A''s notifications');
select is((select count(*)::int from mine where recipient_id = '91000000-0000-0000-0000-000000000001'), 4,
  'editor A has invitation, confirmation, revision and payment');
select ok((select count(*) = (select count(*) from mine) and bool_and(o.status = 'queued')
  from private.notification_outbox o join mine n on n.id = o.notification_id), 'every notification queues one email');
select pg_temp.as_user('91000000-0000-0000-0000-000000000001');
select is((select count(*)::int from public.notifications), 4, 'editor A reads own four through RLS');
select pg_temp.as_user('91000000-0000-0000-0000-000000000003');
select is((select count(*)::int from public.notifications), 3, 'the applicant reads own three through RLS');
reset role;

select * from finish();
rollback;
