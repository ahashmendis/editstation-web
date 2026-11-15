-- Phases 5-6: function-security and data-hygiene guardrails (spec §10). The 046 catalogue rules
-- already run over every function; this file pins the new objects by name so a missing or
-- mis-granted one fails loudly.
begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

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
  ('public.admin_save_assets(uuid, jsonb)'), ('public.admin_set_reference_early_access(uuid, boolean)'),
  ('public.admin_set_asset_early_access(uuid, boolean)'),
  ('public.admin_record_asset_grant(uuid, uuid, text, public.asset_provider, text)'),
  ('public.admin_revoke_asset_grant(uuid, text)'), ('public.admin_pending_revocations()'),
  ('public.admin_grant_project_access(uuid, uuid[], public.project_access_reason)'),
  ('public.admin_revoke_project_access(uuid, uuid)'), ('public.admin_make_offer(uuid, uuid, numeric, text, text)'),
  ('public.admin_respond_counter(uuid, text, numeric, text, text)'), ('public.admin_withdraw_offer(uuid, text)'),
  ('public.admin_confirm_assignment(uuid)'), ('public.admin_reassign(uuid, text)'),
  ('public.admin_add_project_note(uuid, text)'), ('public.editor_respond_offer(uuid, text, numeric, text, text)'),
  ('public.admin_set_project_status(uuid, public.project_status, text)');

create temp table priv (sig text primary key);
insert into priv values
  ('private.lock_writable_project(uuid)'), ('private.clean_text(text, integer, text)'),
  ('private.normalise_email(text)'), ('private.parse_assets(jsonb)'), ('private.sync_asset_rows(uuid, jsonb)'),
  ('private.assignment_transition_allowed(public.assignment_status, public.assignment_status)'),
  ('private.guard_assignments()'), ('private.guard_append_only()'), ('private.audit_assignments()'),
  ('private.require_active_editor()'), ('private.check_amount(numeric, text)'),
  ('private.check_currency(text, character)'), ('private.lock_assignment(uuid)'),
  ('private.add_negotiation(uuid, public.negotiation_role, public.negotiation_action, numeric, character, text, uuid)'),
  ('private.close_live_assignments(uuid, public.assignment_status, uuid, uuid, uuid)'),
  ('private.revoke_live_access(uuid, uuid, uuid, uuid)'),
  ('private.ensure_access(uuid, uuid, public.project_access_reason, uuid)'),
  ('private.require_negotiable_project(uuid)'),
  ('private.admin_counter(public.assignments, numeric, text, text, uuid)'),
  ('private.project_transition_allowed(public.project_status, public.project_status, public.project_status)');

-- ---------------------------------------------------------------------------
-- Function catalogue
-- ---------------------------------------------------------------------------
select ok((select bool_and(has_function_privilege('anon', sig::regprocedure, 'execute')
                           and has_function_privilege('authenticated', sig::regprocedure, 'execute')) from pub)
  and (select count(*) = 16 from pub),
  'all 16 new or replaced public functions exist and are executable by anon and authenticated');
select is_empty($$ select sig from pub p join pg_proc f on f.oid = p.sig::regprocedure
  where not f.prosecdef or not ('search_path=""' = any (coalesce(f.proconfig, '{}'))) $$,
  'every new public function is security definer with an empty search_path');
select is_empty($$ select sig from pub p join pg_proc f on f.oid = p.sig::regprocedure
  where sig like 'public.admin\_%' and f.prosrc not like '%private.require_admin()%' $$,
  'every new admin function calls private.require_admin()');
select ok((select prosrc like '%private.require_active_editor()%' from pg_proc
  where oid = 'public.editor_respond_offer(uuid, text, numeric, text, text)'::regprocedure),
  'editor_respond_offer calls private.require_active_editor()');
select is_empty($$ select sig from priv p join pg_proc f on f.oid = p.sig::regprocedure
  where not f.prosecdef or not ('search_path=""' = any (coalesce(f.proconfig, '{}'))) $$,
  'every new private helper and trigger function is security definer with an empty search_path');
select is_empty($$ select sig from priv
  where has_function_privilege('anon', sig::regprocedure, 'execute')
     or has_function_privilege('authenticated', sig::regprocedure, 'execute') $$,
  'no new private helper is executable by an API role');
select ok(has_function_privilege('authenticated', 'private.editor_project_stage(uuid)', 'execute')
      and not has_function_privilege('anon', 'private.editor_project_stage(uuid)', 'execute')
      and (select prosecdef and 'search_path=""' = any (proconfig) from pg_proc
           where oid = 'private.editor_project_stage(uuid)'::regprocedure),
  'editor_project_stage is security definer and executable by authenticated only');

-- ---------------------------------------------------------------------------
-- Data hygiene
-- ---------------------------------------------------------------------------
select is_empty($$ select table_name || '.' || column_name from information_schema.columns
  where table_schema = 'public'
    and table_name in ('project_assets', 'assignments', 'negotiation_offers', 'project_access')
    and column_name ~ '(client|email|phone|company|contact)' $$,
  'editor-readable Phase 5-6 tables hold no client identity columns');
select set_eq($$ select distinct table_name::text from information_schema.columns
  where table_schema = 'public' and column_name like 'client_price%' $$,
  array['project_internal'], 'client price still exists only in project_internal');
select set_eq($$ select tablename::text || '.' || policyname::text from pg_policies
  where schemaname = 'public' and tablename in ('asset_access_grants', 'project_notes') $$,
  array['asset_access_grants.asset_access_grants_select_admin', 'project_notes.project_notes_select_admin'],
  'folder shares and notes have only their admin policy');
select is_empty($$ select tablename || '.' || policyname from pg_policies
  where schemaname = 'public'
    and tablename in ('projects', 'project_deliverables', 'project_references', 'project_assets', 'brief_versions',
                      'assignments', 'negotiation_offers', 'project_access')
    and cmd <> 'SELECT' $$,
  'every policy on the editor-readable tables is select-only');

-- ---------------------------------------------------------------------------
-- Audit hygiene over one full flow
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('58000000-0000-0000-0000-00000000000a', 'p56-admin@test.local', '{}', '{}'),
  ('58000000-0000-0000-0000-000000000001', 'p56-editor-a@test.local', '{}', '{}'),
  ('58000000-0000-0000-0000-000000000002', 'p56-editor-b@test.local', '{}', '{}');
select private.grant_admin_by_email('p56-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('58000000-0000-0000-0000-000000000001', '58000000-0000-0000-0000-000000000002');
insert into public.projects (id, title, brief_type, status, first_opened_at) values
  ('58000000-0000-0000-0000-0000000000f1', 'Secret Title Flow', 'fully_instructed', 'open', now());
-- Phase 12A: an editor is confirmed only after the project terms are agreed.
update public.project_terms set status = 'agreed', agreed_at = now() where status = 'draft';
insert into public.project_references (id, project_id, url, title)
values ('58000000-0000-0000-0000-0000000000b1', '58000000-0000-0000-0000-0000000000f1',
        'https://ref.example.com/flow', 'Ref Label Flow');

create temp table ids (kind text primary key, id uuid not null);
grant select, insert on ids to authenticated;
create function pg_temp.a(p_kind text) returns uuid language sql as $$ select id from ids where kind = p_kind $$;
grant execute on function pg_temp.a(text) to authenticated;

select pg_temp.as_user('58000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_save_assets('58000000-0000-0000-0000-0000000000f1',
  '[{"label": "Asset Label Flow", "url": "https://drive.example.com/flow", "notes": "Asset note flow"}]');
select public.admin_set_asset_early_access((select id from public.project_assets where label = 'Asset Label Flow'), true);
select public.admin_set_reference_early_access('58000000-0000-0000-0000-0000000000b1', true);
insert into ids select 'g', public.admin_record_asset_grant('58000000-0000-0000-0000-0000000000f1',
  '58000000-0000-0000-0000-000000000001', 'flow-share@drive.example.com', 'google_drive', 'https://drive.example.com/folder');
select public.admin_revoke_asset_grant(pg_temp.a('g'), 'Revoke reason flow');
select public.admin_grant_project_access('58000000-0000-0000-0000-0000000000f1',
  array['58000000-0000-0000-0000-000000000001', '58000000-0000-0000-0000-000000000002']::uuid[], 'invited');
insert into ids select 'a', public.admin_make_offer('58000000-0000-0000-0000-0000000000f1',
  '58000000-0000-0000-0000-000000000001', 31337, 'LKR', 'Offer message flow');
reset role;
select pg_temp.as_user('58000000-0000-0000-0000-000000000001');
select public.editor_respond_offer(pg_temp.a('a'), 'counter', 42424, null, 'Counter message flow');
reset role;
select pg_temp.as_user('58000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_respond_counter(pg_temp.a('a'), 'accept', null, null, 'Accept message flow');
select public.admin_confirm_assignment(pg_temp.a('a'));
select public.admin_reassign(pg_temp.a('a'), 'Reassign message flow');
select public.admin_add_project_note('58000000-0000-0000-0000-0000000000f1', 'Note text flow');
select public.admin_set_project_status('58000000-0000-0000-0000-0000000000f1', 'cancelled');
reset role;

select ok((select count(distinct action) = 11 from public.activity_logs
  where action in ('assignment.offered', 'assignment.counteroffer_pending', 'assignment.accepted',
    'assignment.confirmed', 'assignment.reassigned', 'project_access.granted', 'project_access.revoked',
    'asset_grant.recorded', 'asset_grant.revoked', 'project.assets_changed', 'project.early_access_changed')
  ) and exists (select 1 from public.activity_logs where action = 'project.note_added'),
  'the flow wrote every Phase 5-6 audit action');
select is_empty($$ select action from public.activity_logs
  where (action like 'assignment.%' or action like 'project_access.%' or action like 'asset_grant.%'
         or action in ('project.assets_changed', 'project.early_access_changed', 'project.note_added'))
    and details ?| array['amount', 'proposed_amount', 'agreed_amount', 'message', 'note', 'email', 'url', 'label',
                         'title'] $$,
  'Phase 5-6 audit details have no amount, message, note, email, url, label or title keys');
select is_empty($$ select action from public.activity_logs
  where details::text like '%@%' or details::text like '%https://%' or details::text like '%31337%'
     or details::text like '%42424%' or details::text like '%flow%' or details::text like '%Flow%' $$,
  'no audit row contains an email, a link, an amount or any free text from the flow');

select * from finish();

rollback;
