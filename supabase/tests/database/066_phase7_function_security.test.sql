-- Phase 7: function-security and data-hygiene guardrails (spec §10). The 046 catalogue rules run
-- over every function; this file pins the Phase 7 objects by name.
begin;

create extension if not exists pgtap with schema extensions;

select plan(15);

create function pg_temp.as_user(p_uid uuid, p_aal text default 'aal1')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create temp table pub (sig text primary key);
insert into pub values
  ('public.editor_submit_interpretation(uuid, integer, text, text, text)'),
  ('public.admin_review_interpretation(uuid, text, text)'),
  ('public.editor_confirm_brief(uuid, integer, date, numeric, text)'), ('public.editor_start_work(uuid)'),
  ('public.admin_start_work(uuid)'), ('public.get_assignment_gate(uuid)'),
  ('public.admin_revoke_project_access(uuid, uuid)'), ('public.admin_make_offer(uuid, uuid, numeric, text, text)'),
  ('public.admin_withdraw_offer(uuid, text)'), ('public.admin_reassign(uuid, text)'),
  ('public.admin_pending_revocations()'), ('public.admin_set_project_status(uuid, public.project_status, text)');

create temp table priv (sig text primary key);
insert into priv values
  ('private.check_phase7_row()'), ('private.guard_interpretations()'),
  ('private.assignment_transition_allowed(public.assignment_status, public.assignment_status)'),
  ('private.material_brief_version(uuid)'), ('private.latest_confirmation(uuid)'),
  ('private.assignment_gate(uuid)'), ('private.gate_refusal(uuid, boolean)'),
  ('private.guard_assignment_start()'), ('private.guard_project_in_progress()'),
  ('private.carry_forward_confirmations()'), ('private.require_working_assignment(public.assignments)'),
  ('private.start_work(public.assignments, uuid, boolean)'),
  ('private.close_live_assignments(uuid, public.assignment_status, uuid, uuid, uuid)'),
  ('private.project_transition_allowed(public.project_status, public.project_status, public.project_status)');

-- ---------------------------------------------------------------------------
-- Function catalogue
-- ---------------------------------------------------------------------------
select ok((select bool_and(has_function_privilege('anon', sig::regprocedure, 'execute')
                           and has_function_privilege('authenticated', sig::regprocedure, 'execute')) from pub)
  and (select count(*) = 12 from pub),
  'all 12 new or replaced public functions exist and are executable by anon and authenticated');
select is_empty($$ select sig from pub p join pg_proc f on f.oid = p.sig::regprocedure
  where not f.prosecdef or not ('search_path=""' = any (coalesce(f.proconfig, '{}'))) $$,
  'every Phase 7 public function is security definer with an empty search_path');
select is_empty($$ select sig from pub p join pg_proc f on f.oid = p.sig::regprocedure
  where sig like 'public.admin\_%' and f.prosrc not like '%private.require_admin()%' $$,
  'every admin function calls private.require_admin()');
select is_empty($$ select sig from pub p join pg_proc f on f.oid = p.sig::regprocedure
  where sig like 'public.editor\_%' and f.prosrc not like '%private.require_active_editor()%' $$,
  'every editor function calls private.require_active_editor()');
select ok((select prosrc like '%private.require_user()%' from pg_proc
  where oid = 'public.get_assignment_gate(uuid)'::regprocedure), 'get_assignment_gate calls private.require_user()');
select is_empty($$ select sig from priv p join pg_proc f on f.oid = p.sig::regprocedure
  where not f.prosecdef or not ('search_path=""' = any (coalesce(f.proconfig, '{}'))) $$,
  'every Phase 7 private helper and trigger function is security definer with an empty search_path');
select is_empty($$ select sig from priv
  where has_function_privilege('anon', sig::regprocedure, 'execute')
     or has_function_privilege('authenticated', sig::regprocedure, 'execute') $$,
  'no Phase 7 private helper is executable by an API role');

-- ---------------------------------------------------------------------------
-- Data hygiene and triggers
-- ---------------------------------------------------------------------------
select is_empty($$ select table_name || '.' || column_name from information_schema.columns
  where table_schema = 'public' and table_name in ('editor_interpretations', 'brief_confirmations')
    and column_name ~ '(client|email|phone|company|contact|price)' $$,
  'interpretations and confirmations hold no client identity or price columns');
select set_eq($$ select tablename::text || '.' || cmd from pg_policies
  where schemaname = 'public' and tablename in ('editor_interpretations', 'brief_confirmations') $$,
  array['editor_interpretations.SELECT', 'brief_confirmations.SELECT'],
  'each new table has exactly one policy, and it is select-only');
select set_eq($$ select c.relname::text || '.' || t.tgname::text from pg_trigger t join pg_class c on c.oid = t.tgrelid
  where not t.tgisinternal and t.tgname in ('guard_assignment_start', 'guard_project_in_progress',
    'carry_forward_confirmations', 'editor_interpretations_guard', 'brief_confirmations_append_only',
    'editor_interpretations_check', 'brief_confirmations_check') $$,
  array['assignments.guard_assignment_start', 'projects.guard_project_in_progress',
        'brief_versions.carry_forward_confirmations', 'editor_interpretations.editor_interpretations_guard',
        'brief_confirmations.brief_confirmations_append_only', 'editor_interpretations.editor_interpretations_check',
        'brief_confirmations.brief_confirmations_check'],
  'the Phase 7 triggers exist on the right tables');

-- ---------------------------------------------------------------------------
-- Audit hygiene over one full flow
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('66000000-0000-0000-0000-00000000000a', 'p7f-admin@test.local', '{}', '{}'),
  ('66000000-0000-0000-0000-000000000001', 'p7f-editor-a@test.local', '{}', '{}');
select private.grant_admin_by_email('p7f-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active' where user_id = '66000000-0000-0000-0000-000000000001';

create temp table ids (kind text primary key, id uuid not null);
grant select, insert on ids to authenticated;
create function pg_temp.a(p_kind text) returns uuid language sql as $$ select id from ids where kind = p_kind $$;
grant execute on function pg_temp.a(text) to authenticated;

select pg_temp.as_user('66000000-0000-0000-0000-00000000000a', 'aal2');
insert into ids select 'p', public.admin_create_project('{"title": "Flow project", "brief_type": "fully_instructed",
  "deadline": "2026-12-28", "requires_interpretation": true, "brief": {"instructions": "Cut it"},
  "deliverables": [{"name": "Deliverable Flowname"}]}');
select public.admin_set_project_status(pg_temp.a('p'), 'open');
select public.admin_agree_terms(pg_temp.a('p'), 1);
insert into ids select 'a', public.admin_make_offer(pg_temp.a('p'), '66000000-0000-0000-0000-000000000001', 31337);
reset role;
select pg_temp.as_user('66000000-0000-0000-0000-000000000001');
select public.editor_respond_offer(pg_temp.a('a'), 'accept');
reset role;
select pg_temp.as_user('66000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_confirm_assignment(pg_temp.a('a'));
reset role;
select pg_temp.as_user('66000000-0000-0000-0000-000000000001');
insert into ids select 'i1', public.editor_submit_interpretation(pg_temp.a('a'), 1, 'Reproduce flowtext', 'Adapt flowtext',
  'Question flowtext');
reset role;
select pg_temp.as_user('66000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_review_interpretation(pg_temp.a('i1'), 'request_changes', 'Feedback flowtext');
reset role;
select pg_temp.as_user('66000000-0000-0000-0000-000000000001');
insert into ids select 'i2', public.editor_submit_interpretation(pg_temp.a('a'), 1, 'Reproduce flowtext two', null);
reset role;
select pg_temp.as_user('66000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_review_interpretation(pg_temp.a('i2'), 'accept', 'Accepted flowtext');
reset role;
select pg_temp.as_user('66000000-0000-0000-0000-000000000001');
select public.editor_confirm_brief(pg_temp.a('a'), 1, '2026-12-28', 31337, 'LKR');
reset role;
select pg_temp.as_user('66000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_save_brief(pg_temp.a('p'), '{"brief": {"instructions": "Cut it well"}, "change_summary": "Wording",
  "requires_reacknowledgement": false}');
reset role;
select pg_temp.as_user('66000000-0000-0000-0000-000000000001');
select public.editor_start_work(pg_temp.a('a'));
reset role;
select pg_temp.as_user('66000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_save_brief(pg_temp.a('p'), '{"brief": {"instructions": "Cut it again"}, "change_summary": "Material",
  "requires_reacknowledgement": true}');
reset role;
-- A material version also needs a fresh interpretation (call 7) before re-confirming.
select pg_temp.as_user('66000000-0000-0000-0000-000000000001');
insert into ids select 'i3', public.editor_submit_interpretation(pg_temp.a('a'), 3, 'Reproduce flowtext three', null);
reset role;
select pg_temp.as_user('66000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_review_interpretation(pg_temp.a('i3'), 'accept');
reset role;
select pg_temp.as_user('66000000-0000-0000-0000-000000000001');
select public.editor_confirm_brief(pg_temp.a('a'), 3, '2026-12-28', 31337, 'LKR');
reset role;
select pg_temp.as_user('66000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_reassign(pg_temp.a('a'), 'Reassign flowtext');
reset role;

select ok((select count(distinct action) = 7 from public.activity_logs
  where action in ('interpretation.submitted', 'interpretation.changes_requested', 'interpretation.accepted',
    'brief_confirmation.confirmed', 'brief_confirmation.carried_forward', 'assignment.in_progress',
    'project.in_progress')), 'the flow wrote every Phase 7 audit action');
select is((select count(*)::int from public.brief_confirmations where assignment_id = pg_temp.a('a')), 3,
  'the flow left three confirmation rows (v1, carried v2, v3)');
select is_empty($$ select action from public.activity_logs
  where (action like 'interpretation.%' or action like 'brief_confirmation.%')
    and details ?| array['amount', 'confirmed_amount', 'deadline', 'confirmed_deadline', 'feedback', 'admin_feedback',
                         'will_reproduce', 'will_adapt', 'questions_limitations', 'deliverables'] $$,
  'Phase 7 audit details have no amount, deadline, feedback, text or deliverable keys');
select is_empty($$ select action from public.activity_logs
  where details::text like '%31337%' or details::text like '%2026-12-28%' or details::text like '%flowtext%'
     or details::text like '%Flowname%' $$,
  'no audit row contains the amount, the deadline, any interpretation text or a deliverable');
select ok((select status = 'reassigned' from public.assignments where id = pg_temp.a('a')),
  'the flow ended with the assignment reassigned');

select * from finish();

rollback;
