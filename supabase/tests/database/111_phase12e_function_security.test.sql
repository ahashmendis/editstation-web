-- Phase 12E: function security for the payout functions (anon, admin without MFA, editor A,
-- editor B, suspended editor, pending applicant), the catalogue rules (security definer, empty
-- search_path, anon + authenticated, no PUBLIC) and the private helpers (no API role).
begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

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
  ('eb000000-0000-0000-0000-00000000000a', 'p12e-x-admin@test.local', '{}', '{}'),
  ('eb000000-0000-0000-0000-000000000001', 'p12e-x-editor-a@test.local', '{}', '{}'),
  ('eb000000-0000-0000-0000-000000000002', 'p12e-x-editor-b@test.local', '{}', '{}'),
  ('eb000000-0000-0000-0000-000000000003', 'p12e-x-applicant@test.local', '{}', '{}'),
  ('eb000000-0000-0000-0000-000000000004', 'p12e-x-suspended@test.local', '{}', '{}');
select private.grant_admin_by_email('p12e-x-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('eb000000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000002');
update public.editor_profiles set access_status = 'suspended' where user_id = 'eb000000-0000-0000-0000-000000000004';

create temp table pub (sig text primary key);
insert into pub values
  ('public.editor_save_payout_details(text, text, text, text)'), ('public.editor_get_payout_details()'),
  ('public.admin_get_payout_details_masked(uuid)'), ('public.admin_reveal_payout_details(uuid, text)'),
  ('public.admin_verify_payout_details(uuid, integer, text, text)'), ('public.admin_set_payout_enabled(boolean)'),
  ('public.admin_attest_payout_outside_app(uuid, text)'), ('public.admin_mark_payment_paid(uuid, text, date)');
create temp table priv (sig text primary key);
insert into priv values
  ('private.payout_details_enabled()'), ('private.lock_payout_flag()'), ('private.guard_editor_payout_details()'),
  ('private.guard_payout_append_only()'), ('private.require_payout_enabled()'),
  ('private.mask_account_number(text)'), ('private.payout_attestation_current(uuid)'),
  ('private.payout_block_reason(uuid)'), ('private.require_editor_exists(uuid)'),
  ('private.admin_display_name(uuid)');
grant select on pub, priv to authenticated, anon;

select ok((select bool_and(has_function_privilege('anon', sig::regprocedure, 'execute')
                           and has_function_privilege('authenticated', sig::regprocedure, 'execute')) from pub),
  'the new and replaced public functions are executable by anon and authenticated');
select is_empty($$ select sig from pub p join pg_proc f on f.oid = p.sig::regprocedure
  where not f.prosecdef or not ('search_path=""' = any (coalesce(f.proconfig, '{}')))
     or exists (select 1 from aclexplode(f.proacl) a where a.grantee = 0) $$,
  'they are security definer with an empty search_path and no PUBLIC grant');
select is_empty($$ select sig from priv p join pg_proc f on f.oid = p.sig::regprocedure
  where not f.prosecdef or not ('search_path=""' = any (coalesce(f.proconfig, '{}'))) $$,
  'the private helpers are security definer with an empty search_path');
select is_empty($$ select sig from priv
  where has_function_privilege('anon', sig::regprocedure, 'execute')
     or has_function_privilege('authenticated', sig::regprocedure, 'execute') $$,
  'no Phase 12E private helper is executable by an API role');
select is((select count(*)::int from pg_proc where proname = 'admin_mark_payment_paid'), 1,
  'admin_mark_payment_paid was replaced, not overloaded');

create temp table who (name text, uid uuid, aal text);
insert into who values
  ('anon', null, 'aal1'), ('admin_aal1', 'eb000000-0000-0000-0000-00000000000a', 'aal1'),
  ('editor_a', 'eb000000-0000-0000-0000-000000000001', 'aal1'),
  ('editor_b', 'eb000000-0000-0000-0000-000000000002', 'aal1'),
  ('suspended', 'eb000000-0000-0000-0000-000000000004', 'aal1'),
  ('applicant', 'eb000000-0000-0000-0000-000000000003', 'aal1');
create temp table admin_calls (sql text);
insert into admin_calls values
  ('select public.admin_get_payout_details_masked(gen_random_uuid())'),
  ('select public.admin_reveal_payout_details(gen_random_uuid(), ''TEST'')'),
  ('select public.admin_verify_payout_details(gen_random_uuid(), 1, ''phone'', ''TEST'')'),
  ('select public.admin_set_payout_enabled(null)'),
  ('select public.admin_attest_payout_outside_app(gen_random_uuid(), ''TEST'')'),
  ('select public.admin_mark_payment_paid(gen_random_uuid(), ''TEST'', current_date)');

select is_empty($$ select w.name || ' ' || c.sql || ' ' || pg_temp.state_as(w.uid, w.aal, c.sql)
  from who w cross join admin_calls c
  where pg_temp.state_as(w.uid, w.aal, c.sql) <> case when w.uid is null then 'ES401' else 'ES403' end $$,
  'every admin function: anon ES401, everyone without an MFA admin session ES403');
select is_empty($$ select c.sql || ' ' || pg_temp.state_as('eb000000-0000-0000-0000-00000000000a', 'aal2', c.sql)
  from admin_calls c
  where pg_temp.state_as('eb000000-0000-0000-0000-00000000000a', 'aal2', c.sql) not in ('ES409', 'ES422') $$,
  'an MFA admin passes the check and gets a clean ES409/ES422 for a missing row or bad input');

select set_eq($$
  select w.name || ' ' || pg_temp.state_as(w.uid, w.aal, 'select public.editor_get_payout_details()')
    || ' ' || pg_temp.state_as(w.uid, w.aal,
         'select public.editor_save_payout_details(''TEST ACCOUNT'', ''TEST BANK'', ''TEST BRANCH'', ''TEST-0000-1234'')')
  from (select * from who union all
        select 'admin', 'eb000000-0000-0000-0000-00000000000a'::uuid, 'aal2') w $$,
  $$ values ('anon ES401 ES401'), ('admin_aal1 ES403 ES403'), ('admin ES403 ES403'),
            ('editor_a ok ES409'), ('editor_b ok ES409'), ('suspended ES403 ES403'),
            ('applicant ES403 ES403') $$,
  'editor functions: active editors only; saving is refused while payout details are locked');
select is((select count(*)::int from public.activity_logs where action like 'payout_%'), 0,
  'no refused call wrote an audit row');

select * from finish();
rollback;
