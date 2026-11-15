-- Phase 12B: function security and role refusals (anon, admin without MFA, active editor not on
-- the project, suspended editor, applicant). The 046 catalogue rules also run over the new functions.
begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

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
  ('98000000-0000-0000-0000-00000000000a', 'p12bx-admin@test.local', '{}', '{}'),
  ('98000000-0000-0000-0000-000000000001', 'p12bx-editor-a@test.local', '{}', '{}'),
  ('98000000-0000-0000-0000-000000000003', 'p12bx-applicant@test.local', '{}', '{}'),
  ('98000000-0000-0000-0000-000000000004', 'p12bx-suspended@test.local', '{}', '{}');
select private.grant_admin_by_email('p12bx-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active' where user_id = '98000000-0000-0000-0000-000000000001';
update public.editor_profiles set access_status = 'suspended' where user_id = '98000000-0000-0000-0000-000000000004';

-- The suspended editor was confirmed on the project before suspension.
insert into public.projects (id, title, brief_type, status, first_opened_at) values
  ('98000000-0000-0000-0000-0000000000f1', 'Sec P1', 'fully_instructed', 'assigned', now());
insert into public.assignments (project_id, editor_id, status, proposed_amount, agreed_amount, agreed_currency,
  confirmed_at) values
  ('98000000-0000-0000-0000-0000000000f1', '98000000-0000-0000-0000-000000000004', 'confirmed', 1000, 1000, 'LKR', now());
insert into public.project_assets (id, project_id, label, url) values
  ('98000000-0000-0000-0000-0000000000a1', '98000000-0000-0000-0000-0000000000f1', 'S1', 'https://drive.example.com/s1');

create temp table pub (sig text primary key, call text not null, editor boolean not null);
insert into pub values
  ('public.editor_report_asset_inaccessible(uuid, text)',
   $$ select public.editor_report_asset_inaccessible('98000000-0000-0000-0000-0000000000a1', 'x') $$, true),
  ('public.editor_confirm_asset_access(uuid)',
   $$ select public.editor_confirm_asset_access('98000000-0000-0000-0000-0000000000a1') $$, true),
  ('public.admin_verify_asset(uuid)', $$ select public.admin_verify_asset('98000000-0000-0000-0000-0000000000a1') $$, false),
  ('public.admin_resolve_asset_report(uuid)', $$ select public.admin_resolve_asset_report(gen_random_uuid()) $$, false),
  ('public.admin_record_asset_grant(uuid, uuid, text, public.asset_provider, text, public.asset_access_type)',
   $$ select public.admin_record_asset_grant('98000000-0000-0000-0000-0000000000f1',
        '98000000-0000-0000-0000-000000000001', 'a@x.example.com', 'other', null, 'anyone_with_link') $$, false),
  ('public.admin_request_access_removal(uuid)', $$ select public.admin_request_access_removal(gen_random_uuid()) $$, false),
  ('public.admin_confirm_access_removal(uuid)', $$ select public.admin_confirm_access_removal(gen_random_uuid()) $$, false),
  ('public.admin_pending_revocations()', $$ select * from public.admin_pending_revocations() $$, false);
grant select on pub to authenticated, anon;

create temp table priv (sig text primary key);
insert into priv values
  ('private.guard_asset_access_reports()'), ('private.lock_asset_for_editor(uuid)'),
  ('private.parse_assets(jsonb)'), ('private.sync_asset_rows(uuid, jsonb)');

select ok((select bool_and(has_function_privilege('anon', sig::regprocedure, 'execute')
                           and has_function_privilege('authenticated', sig::regprocedure, 'execute')) from pub)
  and (select count(*) = 8 from pub), 'the eight new or replaced public functions are executable by anon and authenticated');
select is_empty($$ select sig from pub p join pg_proc f on f.oid = p.sig::regprocedure
  where not f.prosecdef or not ('search_path=""' = any (coalesce(f.proconfig, '{}')))
     or exists (select 1 from aclexplode(f.proacl) a where a.grantee = 0) $$,
  'every Phase 12B public function is security definer, has an empty search_path and no PUBLIC grant');
select is_empty($$ select sig from pub p join pg_proc f on f.oid = p.sig::regprocedure
  where (sig like 'public.admin\_%' and f.prosrc not like '%private.require_admin()%')
     or (sig like 'public.editor\_%' and f.prosrc not like '%private.require_active_editor()%') $$,
  'admin functions call require_admin and editor functions require_active_editor');
select is_empty($$ select sig from priv p join pg_proc f on f.oid = p.sig::regprocedure
  where not f.prosecdef or not ('search_path=""' = any (coalesce(f.proconfig, '{}'))) $$,
  'Phase 12B private functions are security definer with an empty search_path');
select is_empty($$ select sig from priv
  where has_function_privilege('anon', sig::regprocedure, 'execute')
     or has_function_privilege('authenticated', sig::regprocedure, 'execute') $$,
  'no Phase 12B private function is executable by an API role');
select is((select count(*)::int from pg_proc where proname = 'admin_record_asset_grant'), 1,
  'the old five-argument admin_record_asset_grant was replaced, not overloaded');

-- Admin functions: anon ES401, everyone else without an MFA admin session ES403. Editor functions:
-- anon ES401; admin, applicant and suspended ES403; an active editor not on the project ES403.
select set_eq($$
  select p.sig || ' ' || who.name || ' ' || pg_temp.state_as(who.uid, who.aal, p.call)
  from pub p cross join (values
    ('anon', null::uuid, 'aal1'), ('admin_aal1', '98000000-0000-0000-0000-00000000000a'::uuid, 'aal1'),
    ('editor_a', '98000000-0000-0000-0000-000000000001'::uuid, 'aal1'),
    ('suspended', '98000000-0000-0000-0000-000000000004'::uuid, 'aal1'),
    ('applicant', '98000000-0000-0000-0000-000000000003'::uuid, 'aal1')) who(name, uid, aal) $$,
  $$ select p.sig || ' ' || who.name || ' ' || case when who.name = 'anon' then 'ES401' else 'ES403' end
  from pub p cross join (values ('anon'), ('admin_aal1'), ('editor_a'), ('suspended'), ('applicant')) who(name) $$,
  'anon gets ES401 and every other wrong identity ES403');
select is(pg_temp.state_as('98000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.editor_report_asset_inaccessible('98000000-0000-0000-0000-0000000000a1', 'x') $$), 'ES403',
  'an admin cannot file an editor report');

select * from finish();
rollback;
