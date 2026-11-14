-- Function-security catalogue and data-hygiene guardrails (spec §7 "Function security", §11).
-- Covers every function in `public` and `private` that is not extension-owned. Functions that
-- predate Phase 4 and deviate from a rule are listed explicitly below, so a new function can
-- never slip through silently. Do not add Phase 4 or later functions to these lists.
begin;

create extension if not exists pgtap with schema extensions;

select plan(17);

create function pg_temp.as_user(p_uid uuid, p_aal text default 'aal1')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

-- All non-extension functions in public and private.
create temp view fns as
select p.oid, n.nspname as schema, p.proname as name, p.oid::regprocedure::text as sig, p.proowner,
       p.prosecdef, p.proconfig, coalesce(p.proacl, acldefault('f', p.proowner)) as acl
from pg_catalog.pg_proc p
join pg_catalog.pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('public', 'private')
  and not exists (select 1 from pg_catalog.pg_depend d where d.objid = p.oid and d.deptype = 'e');

-- Pre-Phase-4 invoker functions (Phases 1-2): trigger functions and require_user, which only
-- reads auth.uid(). They touch no table the caller cannot already reach.
create temp table exc_invoker (name text primary key);
insert into exc_invoker values
  ('private.limit_portfolio_links'), ('private.prevent_activity_log_changes'),
  ('private.require_user'), ('private.set_updated_at');

-- Pre-Phase-4 functions whose ACL includes PUBLIC (Phases 1-3). The Phase 1 access helpers are
-- needed by RLS policies; the Phase 2-3 public functions are executable by anon and
-- authenticated anyway; the two trigger functions have the default ACL and cannot be called
-- outside a trigger. A follow-up migration may revoke PUBLIC from them (owner decision).
create temp table exc_public_acl (name text primary key);
insert into exc_public_acl values
  ('private.is_admin'), ('private.is_admin_account'), ('private.is_active_editor'),
  ('private.prevent_activity_log_changes'), ('private.set_updated_at'),
  ('public.admin_approve_application'), ('public.admin_create_application_request'),
  ('public.admin_record_assessment_result'), ('public.admin_reject_application'),
  ('public.admin_reopen_application'), ('public.admin_set_editor_access'),
  ('public.admin_set_inquiry_status'), ('public.admin_start_application_review'),
  ('public.respond_to_application_request'), ('public.save_editor_profile'),
  ('public.submit_client_inquiry'), ('public.submit_editor_application'),
  ('public.withdraw_editor_application');

-- private helpers RLS policies call as the API role.
create temp table allow_private_exec (name text primary key);
insert into allow_private_exec values
  ('private.is_admin'), ('private.is_admin_account'), ('private.is_active_editor');

-- ---------------------------------------------------------------------------
-- Catalogue rules
-- ---------------------------------------------------------------------------
select is_empty($$ select sig from fns where pg_get_userbyid(proowner) <> 'postgres' $$,
  'every public/private function is owned by postgres');

select is_empty($$ select sig from fns where not prosecdef
  and schema || '.' || name not in (select name from exc_invoker) $$,
  'every function is security definer (except the listed pre-Phase-4 invoker functions)');

select is_empty($$ select sig from fns where not ('search_path=""' = any (coalesce(proconfig, '{}'))) $$,
  'every function pins search_path to empty');

select is_empty($$ select sig from fns
  where exists (select 1 from aclexplode(acl) a where a.grantee = 0)
    and schema || '.' || name not in (select name from exc_public_acl) $$,
  'no function grants EXECUTE to PUBLIC (except the listed pre-Phase-4 functions)');

select is_empty($$ select sig from fns where schema = 'public'
  and not (has_function_privilege('anon', oid, 'execute') and has_function_privilege('authenticated', oid, 'execute')) $$,
  'every public function is executable by anon and authenticated');

select is_empty($$ select sig || ' -> ' || pg_get_userbyid(a.grantee) from fns, aclexplode(acl) a
  where schema = 'public' and a.grantee <> 0
    and pg_get_userbyid(a.grantee) not in ('postgres', 'anon', 'authenticated', 'service_role') $$,
  'public functions are executable only by anon, authenticated, the owner and the platform service_role');

select is_empty($$ select sig from fns where schema = 'private'
  and (has_function_privilege('anon', oid, 'execute') or has_function_privilege('authenticated', oid, 'execute'))
  and schema || '.' || name not in (select name from allow_private_exec)
  and schema || '.' || name not in (select name from exc_public_acl) $$,
  'private functions are executable by no API role (except the RLS helpers)');

select is_empty($$ select sig from fns where schema = 'private' and name not in ('is_admin', 'is_admin_account', 'is_active_editor')
  and exists (select 1 from aclexplode(acl) a where pg_get_userbyid(a.grantee) in ('anon', 'authenticated', 'service_role')) $$,
  'no private function has an explicit grant to an API role (except the RLS helpers)');

select ok((select bool_and(has_function_privilege('anon', f::regprocedure, 'execute')
                           and has_function_privilege('authenticated', f::regprocedure, 'execute'))
  from unnest(array['public.admin_create_project(jsonb)', 'public.admin_save_brief(uuid, jsonb)',
    'public.admin_update_project(uuid, jsonb)', 'public.admin_set_project_status(uuid, public.project_status, text)',
    'public.admin_archive_project(uuid, boolean)', 'public.admin_create_client(jsonb)',
    'public.admin_update_client(uuid, jsonb)', 'public.admin_merge_clients(uuid, uuid)',
    'public.admin_convert_inquiry(uuid, jsonb)']) f),
  'all nine Phase 4 admin functions exist and are executable by the API roles');

-- ---------------------------------------------------------------------------
-- Data hygiene: no client identity or client price on editor-visible-later tables
-- ---------------------------------------------------------------------------
select is_empty($$ select table_name || '.' || column_name from information_schema.columns
  where table_schema = 'public'
    and table_name in ('projects', 'brief_versions', 'project_deliverables', 'project_references')
    and column_name ~ '(client|email|phone|company|contact)' $$,
  'projects, brief_versions, project_deliverables and project_references hold no client identity columns');

select set_eq($$ select distinct table_name::text from information_schema.columns
  where table_schema = 'public' and column_name like 'client_price%' $$,
  array['project_internal'], 'client price exists only in project_internal');

select ok(not exists (select 1 from information_schema.columns where table_schema = 'public'
  and table_name = 'projects' and column_name like 'client%'), 'projects has no client_* column');

-- ---------------------------------------------------------------------------
-- Audit details for Phase 4 actions carry no personal data
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('46000000-0000-0000-0000-00000000000a', 'p4f-admin@test.local', '{}', '{}');
select private.grant_admin_by_email('p4f-admin@test.local', 'test');
insert into public.client_inquiries (id, contact_name, company, email, service_type_code, service_type_label,
  description, budget_label, privacy_notice_version, status)
values ('46000000-0000-0000-0000-0000000000e1', 'Nimal Fernando', 'Hygiene Ltd', 'nimal@example.com', 'long_form',
  'Long-form video', 'Documentary edit.', 'Prefer to discuss', 'v', 'reviewing');

create temp table ids (kind text primary key, id uuid not null);
grant select, insert on ids to authenticated;

select pg_temp.as_user('46000000-0000-0000-0000-00000000000a', 'aal2');
insert into ids select 'conv', public.admin_convert_inquiry('46000000-0000-0000-0000-0000000000e1', '{
  "brief_type": "fully_instructed", "deadline": "2026-12-31", "brief": {"instructions": "Cut"},
  "deliverables": [{"name": "Main"}]}');
select public.admin_set_project_status((select id from ids where kind = 'conv'), 'open', 'Opening now');
select public.admin_save_brief((select id from ids where kind = 'conv'),
  '{"brief": {"instructions": "Cut again"}, "change_summary": "Edited"}');
select public.admin_archive_project((select id from ids where kind = 'conv'), true);
insert into ids select 'other', public.admin_create_client('{"name": "Other Person", "email": "other-person@example.com"}');
select public.admin_merge_clients((select id from ids where kind = 'other'),
  (select client_id from public.project_internal where project_id = (select id from ids where kind = 'conv')));
reset role;

select ok((select count(*) >= 6 from public.activity_logs
  where action like 'project.%' or action like 'client.%' or action = 'inquiry.converted'),
  'the Phase 4 actions above wrote audit rows');
select is_empty($$ select action from public.activity_logs
  where (action like 'project.%' or action like 'client.%' or action = 'inquiry.converted')
    and details ?| array['title', 'email', 'name', 'company', 'phone'] $$,
  'Phase 4 audit details have no title, email, name, company or phone keys');
select is_empty($$ select action from public.activity_logs
  where (action like 'project.%' or action like 'client.%' or action = 'inquiry.converted')
    and (details::text like '%@%' or details::text like '%Nimal%' or details::text like '%Hygiene%'
         or details::text like '%Long-form%') $$,
  'Phase 4 audit details contain no personal data or titles');
select ok(exists (select 1 from public.activity_logs where action = 'project.brief_version'
  and details ? 'project_id' and details ? 'version'), 'the brief version audit row holds ids and the version number');
select ok(pg_get_functiondef('private.check_linkable_client(uuid)'::regprocedure) ~* 'for\s+share',
  'check_linkable_client locks the client row (for share) during the check');

select * from finish();

rollback;
