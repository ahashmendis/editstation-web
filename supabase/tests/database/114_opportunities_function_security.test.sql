-- Open opportunities: function security (anon, admin without MFA, editor A, editor B, suspended
-- editor, pending applicant), the catalogue rules (security definer, empty search_path, anon +
-- authenticated, no PUBLIC) and the private helpers (no API role, except the RLS helper).
begin;

create extension if not exists pgtap with schema extensions;

select plan(10);

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
  ('c3000000-0000-0000-0000-00000000000a', 'opp-x-admin@test.local', '{}', '{}'),
  ('c3000000-0000-0000-0000-000000000001', 'opp-x-editor-a@test.local', '{}', '{}'),
  ('c3000000-0000-0000-0000-000000000002', 'opp-x-editor-b@test.local', '{}', '{}'),
  ('c3000000-0000-0000-0000-000000000003', 'opp-x-applicant@test.local', '{}', '{}'),
  ('c3000000-0000-0000-0000-000000000004', 'opp-x-suspended@test.local', '{}', '{}');
select private.grant_admin_by_email('opp-x-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('c3000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000002');
update public.editor_profiles set access_status = 'suspended' where user_id = 'c3000000-0000-0000-0000-000000000004';

create temp table pub (sig text primary key);
insert into pub values
  ('public.admin_publish_opportunity(uuid, text, text, text, date, text, numeric, text, timestamp with time zone)'),
  ('public.admin_update_opportunity(uuid, text, text, text, date, text, numeric, text, timestamp with time zone)'),
  ('public.admin_close_opportunity(uuid)'), ('public.editor_list_opportunities()'),
  ('public.editor_register_interest(uuid, numeric, text, text)'), ('public.editor_withdraw_interest(uuid)'),
  ('public.admin_list_interests(uuid)'), ('public.admin_get_opportunity(uuid)'), ('public.admin_select_editor(uuid, numeric, text, text)');
create temp table priv (sig text primary key);
insert into priv values
  ('private.guard_project_opportunities()'), ('private.guard_opportunity_interests()'),
  ('private.lock_opportunity(uuid)'), ('private.opportunity_accepting(public.project_opportunities)'),
  ('private.clean_opportunity(text, text, text, date, text, numeric, text, timestamp with time zone)'),
  ('private.close_opportunity(uuid, public.opportunity_status, text, uuid, uuid, text[])'),
  ('private.close_opportunity_on_project_change()');
grant select on pub, priv to authenticated, anon;

select ok((select bool_and(has_function_privilege('anon', sig::regprocedure, 'execute')
                           and has_function_privilege('authenticated', sig::regprocedure, 'execute')) from pub),
  'the new public functions are executable by anon and authenticated');
select is_empty($$ select sig from pub p join pg_proc f on f.oid = p.sig::regprocedure
  where not f.prosecdef or not ('search_path=""' = any (coalesce(f.proconfig, '{}')))
     or exists (select 1 from aclexplode(f.proacl) a where a.grantee = 0) $$,
  'they are security definer with an empty search_path and no PUBLIC grant');
select is_empty($$ select sig from (select sig from priv union all select 'private.editor_can_see_opportunity(uuid)') p
  join pg_proc f on f.oid = p.sig::regprocedure
  where not f.prosecdef or not ('search_path=""' = any (coalesce(f.proconfig, '{}'))) $$,
  'the private helpers are security definer with an empty search_path');
select is_empty($$ select sig from priv
  where has_function_privilege('anon', sig::regprocedure, 'execute')
     or has_function_privilege('authenticated', sig::regprocedure, 'execute') $$,
  'no opportunity private helper is executable by an API role');
select ok(has_function_privilege('authenticated', 'private.editor_can_see_opportunity(uuid)', 'execute')
          and not has_function_privilege('anon', 'private.editor_can_see_opportunity(uuid)', 'execute'),
  'the RLS helper is executable by authenticated only (the policy runs as the caller)');
select is((select count(*)::int from pg_proc where proname = 'admin_make_offer'), 1,
  'admin_make_offer is unchanged (one definition, reused by admin_select_editor)');

create temp table who (name text, uid uuid, aal text);
insert into who values
  ('anon', null, 'aal1'), ('admin_aal1', 'c3000000-0000-0000-0000-00000000000a', 'aal1'),
  ('editor_a', 'c3000000-0000-0000-0000-000000000001', 'aal1'),
  ('editor_b', 'c3000000-0000-0000-0000-000000000002', 'aal1'),
  ('suspended', 'c3000000-0000-0000-0000-000000000004', 'aal1'),
  ('applicant', 'c3000000-0000-0000-0000-000000000003', 'aal1');
create temp table admin_calls (sql text);
insert into admin_calls values
  ('select public.admin_publish_opportunity(gen_random_uuid(), ''T'', ''D'')'),
  ('select public.admin_update_opportunity(gen_random_uuid(), ''T'', ''D'')'),
  ('select public.admin_close_opportunity(gen_random_uuid())'),
  ('select public.admin_list_interests(gen_random_uuid())'),
  ('select public.admin_get_opportunity(gen_random_uuid())'),
  ('select public.admin_select_editor(gen_random_uuid(), 1000)');

select is_empty($$ select w.name || ' ' || c.sql || ' ' || pg_temp.state_as(w.uid, w.aal, c.sql)
  from who w cross join admin_calls c
  where pg_temp.state_as(w.uid, w.aal, c.sql) <> case when w.uid is null then 'ES401' else 'ES403' end $$,
  'every admin function: anon ES401, everyone without an MFA admin session ES403');
select is_empty($$ select c.sql || ' ' || pg_temp.state_as('c3000000-0000-0000-0000-00000000000a', 'aal2', c.sql)
  from admin_calls c
  where pg_temp.state_as('c3000000-0000-0000-0000-00000000000a', 'aal2', c.sql) not in ('ES409', 'ES422') $$,
  'an MFA admin passes the check and gets a clean ES409/ES422 for a missing row');

select set_eq($$
  select w.name || ' ' || pg_temp.state_as(w.uid, w.aal, 'select * from public.editor_list_opportunities()')
    || ' ' || pg_temp.state_as(w.uid, w.aal, 'select public.editor_register_interest(gen_random_uuid())')
    || ' ' || pg_temp.state_as(w.uid, w.aal, 'select public.editor_withdraw_interest(gen_random_uuid())')
  from (select * from who union all
        select 'admin', 'c3000000-0000-0000-0000-00000000000a'::uuid, 'aal2') w $$,
  $$ values ('anon ES401 ES401 ES401'), ('admin_aal1 ES403 ES403 ES403'), ('admin ES403 ES403 ES403'),
            ('editor_a ok ES422 ES422'), ('editor_b ok ES422 ES422'), ('suspended ES403 ES403 ES403'),
            ('applicant ES403 ES403 ES403') $$,
  'editor functions: active editors only');
select is((select count(*)::int from public.activity_logs where action like 'opportunit%'), 0,
  'no refused call wrote an audit row');

select * from finish();
rollback;
