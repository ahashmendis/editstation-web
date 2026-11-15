-- Phase 12D part 1: function security and role refusals (anon, admin without MFA, editor A on the
-- project, editor B, suspended editor, pending applicant) for the dispute split and the replaced
-- editor list, plus the catalogue rules for the new private helpers.
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
  ('d4000000-0000-0000-0000-00000000000a', 'p12dx-admin@test.local', '{}', '{}'),
  ('d4000000-0000-0000-0000-000000000001', 'p12dx-editor-a@test.local', '{}', '{}'),
  ('d4000000-0000-0000-0000-000000000002', 'p12dx-editor-b@test.local', '{}', '{}'),
  ('d4000000-0000-0000-0000-000000000003', 'p12dx-applicant@test.local', '{}', '{}'),
  ('d4000000-0000-0000-0000-000000000004', 'p12dx-suspended@test.local', '{}', '{}');
select private.grant_admin_by_email('p12dx-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('d4000000-0000-0000-0000-000000000001', 'd4000000-0000-0000-0000-000000000002');
update public.editor_profiles set access_status = 'suspended' where user_id = 'd4000000-0000-0000-0000-000000000004';

insert into public.projects (id, title, brief_type, status, first_opened_at) values
  ('d4000000-0000-0000-0000-0000000000f1', 'Sec pay', 'fully_instructed', 'assigned', now());
update public.project_terms set status = 'agreed', agreed_at = now()
where project_id = 'd4000000-0000-0000-0000-0000000000f1';
insert into public.assignments (id, project_id, editor_id, status, proposed_amount, agreed_amount, agreed_currency,
  confirmed_at) values
  ('d4000000-0000-0000-0000-0000000000b1', 'd4000000-0000-0000-0000-0000000000f1',
   'd4000000-0000-0000-0000-000000000001', 'confirmed', 1000, 1000, 'LKR', now());
insert into public.payments (id, assignment_id, project_id, editor_id, milestone_seq, amount, currency) values
  ('d4000000-0000-0000-0000-0000000000c1', 'd4000000-0000-0000-0000-0000000000b1',
   'd4000000-0000-0000-0000-0000000000f1', 'd4000000-0000-0000-0000-000000000001', 1, 500, 'LKR');

create temp table priv (sig text primary key);
insert into priv values
  ('private.client_balance_verified(uuid)'), ('private.editor_pay_days(uuid)'),
  ('private.sync_editor_milestones(uuid, timestamp with time zone)'), ('private.sync_milestones_on_client_payment()'),
  ('private.sync_milestones_on_approval()'), ('private.late_balance_due(uuid, date)'),
  ('private.clear_payment_waiting()'), ('private.check_payment_split()'), ('private.client_deposit_verified(uuid)'),
  ('private.create_assignment_payment()'), ('private.apply_timed_rules(timestamp with time zone)');
create temp table pub (sig text primary key);
insert into pub values ('public.admin_split_payment_for_dispute(uuid, numeric, text)'), ('public.editor_list_payments()'),
  ('public.admin_release_payment_hold(uuid)'), ('public.admin_reverse_payment(uuid, text, boolean)');
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
  'no Phase 12D private helper is executable by an API role');
select is((select count(*)::int from pg_proc where proname = 'editor_list_payments'), 1,
  'editor_list_payments was recreated, not overloaded');

-- The split: anon ES401, everyone else without an MFA admin session ES403.
select set_eq($$
  select who.name || ' ' || pg_temp.state_as(who.uid, who.aal,
    'select public.admin_split_payment_for_dispute(''d4000000-0000-0000-0000-0000000000c1'', 100, ''x'')')
  from (values
    ('anon', null::uuid, 'aal1'), ('admin_aal1', 'd4000000-0000-0000-0000-00000000000a'::uuid, 'aal1'),
    ('editor_a', 'd4000000-0000-0000-0000-000000000001'::uuid, 'aal1'),
    ('editor_b', 'd4000000-0000-0000-0000-000000000002'::uuid, 'aal1'),
    ('suspended', 'd4000000-0000-0000-0000-000000000004'::uuid, 'aal1'),
    ('applicant', 'd4000000-0000-0000-0000-000000000003'::uuid, 'aal1')) who(name, uid, aal) $$,
  $$ values ('anon ES401'), ('admin_aal1 ES403'), ('editor_a ES403'), ('editor_b ES403'), ('suspended ES403'),
            ('applicant ES403') $$,
  'only an MFA admin can split a payment');
select is((select amount::text || ':' || status::text from public.payments where id = 'd4000000-0000-0000-0000-0000000000c1'),
  '500.00:not_due', 'no refused call changed the payment');

-- The editor list: active editors only.
select set_eq($$
  select who.name || ' ' || pg_temp.state_as(who.uid, who.aal, 'select * from public.editor_list_payments()')
  from (values
    ('anon', null::uuid, 'aal1'), ('admin', 'd4000000-0000-0000-0000-00000000000a'::uuid, 'aal2'),
    ('editor_a', 'd4000000-0000-0000-0000-000000000001'::uuid, 'aal1'),
    ('editor_b', 'd4000000-0000-0000-0000-000000000002'::uuid, 'aal1'),
    ('suspended', 'd4000000-0000-0000-0000-000000000004'::uuid, 'aal1'),
    ('applicant', 'd4000000-0000-0000-0000-000000000003'::uuid, 'aal1')) who(name, uid, aal) $$,
  $$ values ('anon ES401'), ('admin ES403'), ('editor_a ok'), ('editor_b ok'), ('suspended ES403'),
            ('applicant ES403') $$,
  'only active editors call the editor list');
select pg_temp.as_user('d4000000-0000-0000-0000-000000000002');
select is((select count(*)::int from public.editor_list_payments()), 0, 'editor B sees none of editor A''s rows');
select pg_temp.as_user('d4000000-0000-0000-0000-000000000001');
select is((select count(*)::int from public.editor_list_payments()), 1, 'editor A sees their own milestone');
reset role;

select * from finish();
rollback;
