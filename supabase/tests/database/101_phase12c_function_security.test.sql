-- Phase 12C: function security and role refusals for the client billing functions (anon, admin
-- without MFA, editor A on the project, editor B, suspended editor, pending applicant). The 046
-- catalogue rules also run over the new functions.
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
  ('a1000000-0000-0000-0000-00000000000a', 'p12cx-admin@test.local', '{}', '{}'),
  ('a1000000-0000-0000-0000-000000000001', 'p12cx-editor-a@test.local', '{}', '{}'),
  ('a1000000-0000-0000-0000-000000000002', 'p12cx-editor-b@test.local', '{}', '{}'),
  ('a1000000-0000-0000-0000-000000000003', 'p12cx-applicant@test.local', '{}', '{}'),
  ('a1000000-0000-0000-0000-000000000004', 'p12cx-suspended@test.local', '{}', '{}');
select private.grant_admin_by_email('p12cx-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002');
update public.editor_profiles set access_status = 'suspended' where user_id = 'a1000000-0000-0000-0000-000000000004';

-- Editor A is confirmed on the project and holds a milestone id (they could only guess it).
insert into public.projects (id, title, brief_type, status, first_opened_at) values
  ('a1000000-0000-0000-0000-0000000000f1', 'Sec billing', 'fully_instructed', 'assigned', now());
update public.project_terms set status = 'agreed', agreed_at = now()
where project_id = 'a1000000-0000-0000-0000-0000000000f1';
insert into public.assignments (id, project_id, editor_id, status, proposed_amount, agreed_amount, agreed_currency,
  confirmed_at) values
  ('a1000000-0000-0000-0000-0000000000b1', 'a1000000-0000-0000-0000-0000000000f1', 'a1000000-0000-0000-0000-000000000001', 'confirmed', 1000, 1000, 'LKR', now());
insert into public.client_milestones (id, project_id, terms_id, seq, kind, share_percent, amount, currency)
select 'a1000000-0000-0000-0000-0000000000d1', 'a1000000-0000-0000-0000-0000000000f1', t.id, 1, 'deposit', 100, 900, 'LKR'
from public.project_terms t where t.project_id = 'a1000000-0000-0000-0000-0000000000f1';

create temp table pub (sig text primary key, call text not null);
insert into pub values
  ('public.admin_create_client_milestones(uuid, integer[])',
   $$ select public.admin_create_client_milestones('a1000000-0000-0000-0000-0000000000f1') $$),
  ('public.admin_issue_client_invoice(uuid)', $$ select public.admin_issue_client_invoice('a1000000-0000-0000-0000-0000000000d1') $$),
  ('public.admin_record_client_payment(uuid, text, date)',
   $$ select public.admin_record_client_payment('a1000000-0000-0000-0000-0000000000d1', 'R') $$),
  ('public.admin_verify_client_payment(uuid)', $$ select public.admin_verify_client_payment('a1000000-0000-0000-0000-0000000000d1') $$),
  ('public.admin_correct_client_payment(uuid, text)',
   $$ select public.admin_correct_client_payment('a1000000-0000-0000-0000-0000000000d1', 'x') $$),
  ('public.admin_extend_deposit_due(uuid, date, text)',
   $$ select public.admin_extend_deposit_due('a1000000-0000-0000-0000-0000000000d1', '2099-01-01', 'x') $$),
  ('public.admin_set_business_timezone(text)', $$ select public.admin_set_business_timezone('UTC') $$),
  ('public.admin_run_timed_rules()', $$ select public.admin_run_timed_rules() $$);
grant select on pub to authenticated, anon;

create temp table priv (sig text primary key);
insert into priv values
  ('private.business_timezone()'), ('private.business_date(timestamp with time zone)'),
  ('private.guard_client_milestones()'), ('private.lock_client_milestone(uuid, boolean)'),
  ('private.project_past_start(uuid)'), ('private.client_deposit_verified(uuid)'),
  ('private.assignment_gate(uuid)'), ('private.apply_timed_rules(timestamp with time zone)');

select ok((select bool_and(has_function_privilege('anon', sig::regprocedure, 'execute')
                           and has_function_privilege('authenticated', sig::regprocedure, 'execute')) from pub)
  and has_function_privilege('anon', 'public.get_assignment_gate(uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.get_assignment_gate(uuid)', 'execute'),
  'the new public functions and the recreated get_assignment_gate are executable by anon and authenticated');
select is_empty($$ select sig from (select sig from pub union all select 'public.get_assignment_gate(uuid)') p
  join pg_proc f on f.oid = p.sig::regprocedure
  where not f.prosecdef or not ('search_path=""' = any (coalesce(f.proconfig, '{}')))
     or exists (select 1 from aclexplode(f.proacl) a where a.grantee = 0) $$,
  'every Phase 12C public function is security definer, has an empty search_path and no PUBLIC grant');
select is_empty($$ select sig from pub p join pg_proc f on f.oid = p.sig::regprocedure
  where f.prosrc not like '%private.require_admin()%' $$, 'every Phase 12C admin function calls require_admin');
select is_empty($$ select sig from priv p join pg_proc f on f.oid = p.sig::regprocedure
  where not f.prosecdef or not ('search_path=""' = any (coalesce(f.proconfig, '{}'))) $$,
  'Phase 12C private functions are security definer with an empty search_path');
select is_empty($$ select sig from priv
  where has_function_privilege('anon', sig::regprocedure, 'execute')
     or has_function_privilege('authenticated', sig::regprocedure, 'execute') $$,
  'no Phase 12C private function is executable by an API role');
select is((select count(*)::int from pg_proc where proname in ('get_assignment_gate', 'assignment_gate')), 2,
  'the gate functions were recreated, not overloaded');

-- Admin functions: anon ES401, everyone else without an MFA admin session ES403.
select set_eq($$
  select p.sig || ' ' || who.name || ' ' || pg_temp.state_as(who.uid, who.aal, p.call)
  from pub p cross join (values
    ('anon', null::uuid, 'aal1'), ('admin_aal1', 'a1000000-0000-0000-0000-00000000000a'::uuid, 'aal1'),
    ('editor_a', 'a1000000-0000-0000-0000-000000000001'::uuid, 'aal1'),
    ('editor_b', 'a1000000-0000-0000-0000-000000000002'::uuid, 'aal1'),
    ('suspended', 'a1000000-0000-0000-0000-000000000004'::uuid, 'aal1'),
    ('applicant', 'a1000000-0000-0000-0000-000000000003'::uuid, 'aal1')) who(name, uid, aal) $$,
  $$ select p.sig || ' ' || who.name || ' ' || case when who.name = 'anon' then 'ES401' else 'ES403' end
  from pub p cross join (values ('anon'), ('admin_aal1'), ('editor_a'), ('editor_b'), ('suspended'), ('applicant')) who(name) $$,
  'anon gets ES401 and every other wrong identity ES403');
select is((select verification_status::text || coalesce(transfer_reference, '-')
  from public.client_milestones where id = 'a1000000-0000-0000-0000-0000000000d1'), 'expected-',
  'no refused call changed the milestone');

-- get_assignment_gate: editor B, the suspended editor, the applicant and anon cannot read editor A's gate.
select set_eq($$
  select who.name || ' ' || pg_temp.state_as(who.uid, 'aal1',
    'select * from public.get_assignment_gate(''a1000000-0000-0000-0000-0000000000b1'')')
  from (values ('anon', null::uuid), ('editor_b', 'a1000000-0000-0000-0000-000000000002'::uuid),
    ('suspended', 'a1000000-0000-0000-0000-000000000004'::uuid),
    ('applicant', 'a1000000-0000-0000-0000-000000000003'::uuid)) who(name, uid) $$,
  $$ values ('anon ES401'), ('editor_b ES422'), ('suspended ES422'), ('applicant ES422') $$,
  'only the admin and the owning active editor read the gate');

select * from finish();
rollback;
