-- Phase 12D part 2: function security for the extra pay, scope quote and settlement functions
-- (anon, admin without MFA, editor A, editor B, suspended editor, pending applicant), the
-- catalogue rules (security definer, empty search_path, anon + authenticated, no PUBLIC) and the
-- private helpers (no API role may execute them).
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
  ('d8000000-0000-0000-0000-00000000000a', 'p12d2x-admin@test.local', '{}', '{}'),
  ('d8000000-0000-0000-0000-000000000001', 'p12d2x-editor-a@test.local', '{}', '{}'),
  ('d8000000-0000-0000-0000-000000000002', 'p12d2x-editor-b@test.local', '{}', '{}'),
  ('d8000000-0000-0000-0000-000000000003', 'p12d2x-applicant@test.local', '{}', '{}'),
  ('d8000000-0000-0000-0000-000000000004', 'p12d2x-suspended@test.local', '{}', '{}');
select private.grant_admin_by_email('p12d2x-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('d8000000-0000-0000-0000-000000000001', 'd8000000-0000-0000-0000-000000000002');
update public.editor_profiles set access_status = 'suspended' where user_id = 'd8000000-0000-0000-0000-000000000004';

create temp table pub (sig text primary key);
insert into pub values
  ('public.admin_set_revision_adjustment_required(uuid, boolean)'),
  ('public.admin_offer_adjustment(uuid, text, numeric, uuid, uuid, text)'),
  ('public.admin_withdraw_adjustment(uuid)'), ('public.editor_respond_adjustment(uuid, text)'),
  ('public.editor_list_adjustments(uuid)'), ('public.editor_revision_gate(uuid)'),
  ('public.admin_create_scope_quote(uuid, text, numeric, text)'), ('public.admin_send_scope_quote(uuid)'),
  ('public.admin_record_scope_quote_answer(uuid, boolean, date)'), ('public.admin_charge_extra_round(uuid, date)'),
  ('public.editor_list_payments()'), ('public.admin_reverse_payment(uuid, text, boolean)'),
  ('public.admin_preview_cancellation_settlement(uuid)'), ('public.admin_settle_cancellation(uuid, numeric, text)'),
  ('public.admin_set_project_status(uuid, project_status, text)');
create temp table priv (sig text primary key);
insert into priv values
  ('private.revision_gate(uuid)'), ('private.lock_revision_request(uuid)'), ('private.require_money(numeric, text)'),
  ('private.require_client_due_date(date)'),
  ('private.add_extra_work_milestone(uuid, numeric, character, date, uuid, uuid, uuid)'),
  ('private.lock_scope_quote(uuid)'), ('private.cancellation_stage(uuid)'), ('private.live_assignment_id(uuid)'),
  ('private.cancellation_settlement_required(uuid)'), ('private.settlement_figures(uuid, numeric, text)'),
  ('private.guard_scope_change_quotes()'), ('private.guard_compensation_adjustments()'),
  ('private.guard_client_milestone_links()'), ('private.check_payment_row()'), ('private.guard_payments()'),
  ('private.audit_payments()'), ('private.require_unpaid(payments)'), ('private.guard_revision_requests()');
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
  'no Phase 12D part 2 private helper is executable by an API role');
select is((select count(*)::int from pg_proc where proname in ('editor_list_payments', 'admin_reverse_payment',
  'admin_set_project_status')), 3, 'replaced functions were not overloaded');

create temp table who (name text, uid uuid, aal text);
insert into who values
  ('anon', null, 'aal1'), ('admin_aal1', 'd8000000-0000-0000-0000-00000000000a', 'aal1'),
  ('editor_a', 'd8000000-0000-0000-0000-000000000001', 'aal1'),
  ('editor_b', 'd8000000-0000-0000-0000-000000000002', 'aal1'),
  ('suspended', 'd8000000-0000-0000-0000-000000000004', 'aal1'),
  ('applicant', 'd8000000-0000-0000-0000-000000000003', 'aal1');
create temp table admin_calls (sql text);
insert into admin_calls values
  ('select public.admin_set_revision_adjustment_required(gen_random_uuid(), true)'),
  ('select public.admin_offer_adjustment(gen_random_uuid(), ''extra_round'', 10, gen_random_uuid())'),
  ('select public.admin_withdraw_adjustment(gen_random_uuid())'),
  ('select public.admin_create_scope_quote(gen_random_uuid(), ''x'', 10, ''LKR'')'),
  ('select public.admin_send_scope_quote(gen_random_uuid())'),
  ('select public.admin_record_scope_quote_answer(gen_random_uuid(), true, ''2099-01-01'')'),
  ('select public.admin_charge_extra_round(gen_random_uuid(), ''2099-01-01'')'),
  ('select public.admin_preview_cancellation_settlement(gen_random_uuid())'),
  ('select public.admin_settle_cancellation(gen_random_uuid())');

select is_empty($$ select w.name || ' ' || c.sql || ' ' || pg_temp.state_as(w.uid, w.aal, c.sql)
  from who w cross join admin_calls c
  where pg_temp.state_as(w.uid, w.aal, c.sql) <> case when w.uid is null then 'ES401' else 'ES403' end $$,
  'every admin function: anon ES401, everyone without an MFA admin session ES403');
select is_empty($$ select c.sql || ' ' || pg_temp.state_as('d8000000-0000-0000-0000-00000000000a', 'aal2', c.sql)
  from admin_calls c
  where pg_temp.state_as('d8000000-0000-0000-0000-00000000000a', 'aal2', c.sql) not in ('ES409', 'ES422') $$,
  'an MFA admin passes the check and gets a clean ES409/ES422 for a missing row');

select set_eq($$
  select w.name || ' ' || pg_temp.state_as(w.uid, w.aal, 'select * from public.editor_list_adjustments()')
    || ' ' || pg_temp.state_as(w.uid, w.aal, 'select public.editor_respond_adjustment(gen_random_uuid(), ''accept'')')
    || ' ' || pg_temp.state_as(w.uid, w.aal, 'select public.editor_revision_gate(gen_random_uuid())')
  from (select * from who union all
        select 'admin', 'd8000000-0000-0000-0000-00000000000a'::uuid, 'aal2') w $$,
  $$ values ('anon ES401 ES401 ES401'), ('admin_aal1 ES403 ES403 ES403'), ('admin ES403 ES403 ES403'),
            ('editor_a ok ES422 ES422'), ('editor_b ok ES422 ES422'), ('suspended ES403 ES403 ES403'),
            ('applicant ES403 ES403 ES403') $$,
  'editor functions: active editors only; an unknown offer or request is not found');
select is((select count(*)::int from public.activity_logs where action like 'adjustment.%' or action like 'scope_quote.%'
  or action = 'project.cancellation_settled'), 0, 'no refused call wrote an audit row');

select * from finish();
rollback;
