-- Phase 8: function security, role refusals and audit hygiene. The 046 catalogue rules also run
-- over the new functions.
begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

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
  ('82000000-0000-0000-0000-00000000000a', 'p8f-admin@test.local', '{}', '{}'),
  ('82000000-0000-0000-0000-000000000001', 'p8f-editor-a@test.local', '{}', '{}'),
  ('82000000-0000-0000-0000-000000000002', 'p8f-editor-b@test.local', '{}', '{}'),
  ('82000000-0000-0000-0000-000000000003', 'p8f-applicant@test.local', '{}', '{}'),
  ('82000000-0000-0000-0000-000000000004', 'p8f-suspended@test.local', '{}', '{}');
select private.grant_admin_by_email('p8f-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('82000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000002');
update public.editor_profiles set access_status = 'suspended' where user_id = '82000000-0000-0000-0000-000000000004';

create temp table pub (sig text primary key, call text not null, editor boolean not null);
insert into pub values
  ('public.editor_submit_work(uuid, text, text, text)',
   $$ select public.editor_submit_work(gen_random_uuid(), 'https://x.example') $$, true),
  ('public.editor_acknowledge_revision(uuid, boolean)',
   $$ select public.editor_acknowledge_revision(gen_random_uuid()) $$, true),
  ('public.admin_review_submission(uuid, text, text, text, text)',
   $$ select public.admin_review_submission(gen_random_uuid(), 'approved') $$, false),
  ('public.admin_approve_project(uuid, text)', $$ select public.admin_approve_project(gen_random_uuid()) $$, false),
  ('public.admin_classify_revision(uuid, text, text)',
   $$ select public.admin_classify_revision(gen_random_uuid(), 'client_revision', 'x') $$, false),
  ('public.admin_complete_project(uuid)', $$ select public.admin_complete_project(gen_random_uuid()) $$, false);
grant select on pub to authenticated, anon;

create temp table priv (sig text primary key);
insert into priv values
  ('private.check_submission_row()'), ('private.guard_submissions()'), ('private.check_revision_row()'),
  ('private.guard_revision_requests()'), ('private.revision_transition_allowed(public.revision_status, public.revision_status)'),
  ('private.guard_project_review_status()'), ('private.audit_phase8()'), ('private.renumber_client_rounds(uuid)'),
  ('private.review_submission(uuid, uuid, text, text, text, text)');

select ok((select bool_and(has_function_privilege('anon', sig::regprocedure, 'execute')
                           and has_function_privilege('authenticated', sig::regprocedure, 'execute')) from pub)
  and (select count(*) = 6 from pub), 'the six public functions exist and are executable by anon and authenticated');
select is_empty($$ select sig from pub p join pg_proc f on f.oid = p.sig::regprocedure
  where not f.prosecdef or not ('search_path=""' = any (coalesce(f.proconfig, '{}'))) $$,
  'every Phase 8 public function is security definer with an empty search_path');
select is_empty($$ select sig from pub p join pg_proc f on f.oid = p.sig::regprocedure
  where (sig like 'public.admin\_%' and f.prosrc not like '%private.require_admin()%')
     or (sig like 'public.editor\_%' and f.prosrc not like '%private.require_active_editor()%') $$,
  'admin functions call require_admin and editor functions require_active_editor');
select is_empty($$ select sig from priv p join pg_proc f on f.oid = p.sig::regprocedure
  where not ('search_path=""' = any (coalesce(f.proconfig, '{}'))) $$,
  'Phase 8 private functions have an empty search_path');
select is_empty($$ select sig from priv
  where has_function_privilege('anon', sig::regprocedure, 'execute')
     or has_function_privilege('authenticated', sig::regprocedure, 'execute') $$,
  'no Phase 8 private function is executable by an API role');

select set_eq($$
  select p.sig || ' ' || who.name || ' ' || pg_temp.state_as(who.uid, who.aal, p.call)
  from pub p cross join (values
    ('anon', null::uuid, 'aal1'), ('admin_aal1', '82000000-0000-0000-0000-00000000000a'::uuid, 'aal1'),
    ('editor_a', '82000000-0000-0000-0000-000000000001'::uuid, 'aal1'),
    ('suspended', '82000000-0000-0000-0000-000000000004'::uuid, 'aal1'),
    ('applicant', '82000000-0000-0000-0000-000000000003'::uuid, 'aal1')) who(name, uid, aal)
  where not (p.editor and who.name = 'editor_a') $$,
  $$ select p.sig || ' ' || who.name || ' ' || case when who.name = 'anon' then 'ES401' else 'ES403' end
  from pub p cross join (values ('anon'), ('admin_aal1'), ('editor_a'), ('suspended'), ('applicant')) who(name)
  where not (p.editor and who.name = 'editor_a') $$,
  'anon gets ES401 and every other wrong identity ES403');
select is(pg_temp.state_as('82000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.editor_submit_work(gen_random_uuid(), 'https://x.example') $$), 'ES403', 'an admin cannot submit work');
select is(pg_temp.state_as('82000000-0000-0000-0000-000000000001', 'aal1',
  $$ select public.editor_submit_work(gen_random_uuid(), 'https://x.example') $$), 'ES422',
  'an unknown assignment is not found for an editor');

-- ---------------------------------------------------------------------------
-- Audit over one flow
-- ---------------------------------------------------------------------------
create temp table flow (kind text primary key, id uuid);
grant select, insert on flow to authenticated;
select pg_temp.as_user('82000000-0000-0000-0000-00000000000a', 'aal2');
insert into flow select 'project', public.admin_create_project(jsonb_build_object('title', 'Flow', 'brief_type',
  'fully_instructed', 'deadline', '2099-12-31', 'brief', jsonb_build_object('instructions', 'Cut it'),
  'deliverables', jsonb_build_array(jsonb_build_object('name', 'Main'))));
select public.admin_set_project_status((select id from flow where kind = 'project'), 'open');
select public.admin_agree_terms((select id from flow where kind = 'project'), 1);
insert into flow select 'asg', public.admin_make_offer((select id from flow where kind = 'project'),
  '82000000-0000-0000-0000-000000000001', 10000, 'LKR');
select pg_temp.as_user('82000000-0000-0000-0000-000000000001');
select public.editor_respond_offer((select id from flow where kind = 'asg'), 'accept');
select pg_temp.as_user('82000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_confirm_assignment((select id from flow where kind = 'asg'));
select pg_temp.verify_deposit((select id from flow where kind = 'project'));
select pg_temp.as_user('82000000-0000-0000-0000-000000000001');
select public.editor_confirm_brief((select id from flow where kind = 'asg'), 1, '2099-12-31', 10000, 'LKR');
select public.editor_start_work((select id from flow where kind = 'asg'));
insert into flow select 's1', public.editor_submit_work((select id from flow where kind = 'asg'),
  'https://secret-link.example/zz', 'Note qq', 'Export yy');
select pg_temp.as_user('82000000-0000-0000-0000-00000000000a', 'aal2');
insert into flow select 'r1', public.admin_review_submission((select id from flow where kind = 's1'),
  'rejected_needs_discussion', 'Feedback ww', 'client_revision', 'Reason vv');
select public.admin_classify_revision((select id from flow where kind = 'r1'), 'client_revision', 'Reason uu');
select pg_temp.as_user('82000000-0000-0000-0000-000000000001');
select public.editor_acknowledge_revision((select id from flow where kind = 'r1'));
select public.editor_acknowledge_revision((select id from flow where kind = 'r1'), true);
insert into flow select 's2', public.editor_submit_work((select id from flow where kind = 'asg'), 'https://secret-link.example/tt');
select pg_temp.as_user('82000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_approve_project((select id from flow where kind = 'project'));
select public.admin_complete_project((select id from flow where kind = 'project'));
reset role;

select set_eq($$ select distinct action from public.activity_logs
  where action like 'submission.%' or action like 'revision_request.%' $$,
  array['submission.submitted', 'submission.reviewed', 'revision_request.created', 'revision_request.classified',
        'revision_request.acknowledged', 'revision_request.in_progress', 'revision_request.resubmitted',
        'revision_request.approved'], 'every Phase 8 action is audited');
select is_empty($$ select id from public.activity_logs
  where (action like 'submission.%' or action like 'revision_request.%')
    and details::text ~ '(secret-link|Note qq|Export yy|Feedback ww|Reason vv|Reason uu|2099)' $$,
  'audit rows hold no links, notes, export details, feedback, reasons or dates');
select is_empty($$ select id from public.activity_logs
  where (action like 'submission.%' or action like 'revision_request.%')
    and exists (select 1 from jsonb_object_keys(details) k
                where k not in ('submission_id', 'revision_request_id', 'assignment_id', 'project_id', 'version',
                                'is_late', 'outcome', 'type', 'from', 'to', 'round_number')) $$,
  'audit rows carry only ids, version, flags and enum names');
select set_eq($$ select action from public.activity_logs where entity_type = 'project'
  and entity_id = (select id::text from flow where kind = 'project') and action in
  ('project.in_review', 'project.revision_requested', 'project.approved', 'project.completed') $$,
  array['project.in_review', 'project.revision_requested', 'project.approved', 'project.completed'],
  'project status changes are audited by the existing trigger');

select * from finish();
rollback;
