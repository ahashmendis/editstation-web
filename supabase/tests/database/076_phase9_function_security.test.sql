-- Phase 9: function security, role refusals, data hygiene and audit details (spec §8, §10).
-- Review Focus 11. The 046 catalogue rules also run over the new functions.
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
grant execute on function pg_temp.as_user(uuid, text) to authenticated;

create function pg_temp.as_anon()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('role', 'anon', true);
end;
$$;

-- SQLSTATE of p_sql run as p_uid (null = anon); 'ok' when it succeeds (rolled back either way).
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
  ('76000000-0000-0000-0000-00000000000a', 'p9f-admin@test.local', '{}', '{}'),
  ('76000000-0000-0000-0000-000000000001', 'p9f-editor-a@test.local', '{}', '{}'),
  ('76000000-0000-0000-0000-000000000002', 'p9f-editor-b@test.local', '{}', '{}'),
  ('76000000-0000-0000-0000-000000000003', 'p9f-applicant@test.local', '{}', '{}'),
  ('76000000-0000-0000-0000-000000000004', 'p9f-suspended@test.local', '{}', '{}');
select private.grant_admin_by_email('p9f-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('76000000-0000-0000-0000-000000000001', '76000000-0000-0000-0000-000000000002');
update public.editor_profiles set access_status = 'suspended' where user_id = '76000000-0000-0000-0000-000000000004';

create temp table pub (sig text primary key, call text not null);
insert into pub values
  ('public.admin_set_payment_status(uuid, text, text)',
   $$ select public.admin_set_payment_status(gen_random_uuid(), 'approved') $$),
  ('public.admin_release_payment_hold(uuid)', $$ select public.admin_release_payment_hold(gen_random_uuid()) $$),
  ('public.admin_mark_payment_paid(uuid, text, date)',
   $$ select public.admin_mark_payment_paid(gen_random_uuid(), 'R', current_date) $$),
  ('public.admin_set_payment_due_date(uuid, date)', $$ select public.admin_set_payment_due_date(gen_random_uuid(), null) $$),
  ('public.admin_reverse_payment(uuid, text, boolean)',
   $$ select public.admin_reverse_payment(gen_random_uuid(), 'x', false) $$),
  ('public.admin_add_payment_note(uuid, text)', $$ select public.admin_add_payment_note(gen_random_uuid(), 'x') $$),
  ('public.editor_list_payments()', $$ select * from public.editor_list_payments() $$);
grant select on pub to authenticated, anon;

create temp table priv (sig text primary key);
insert into priv values
  ('private.payment_transition_allowed(public.payment_status, public.payment_status)'),
  ('private.check_payment_row()'), ('private.guard_payments()'), ('private.audit_payments()'),
  ('private.create_assignment_payment()'), ('private.hold_payments_on_close()');

-- ---------------------------------------------------------------------------
-- Catalogue
-- ---------------------------------------------------------------------------
select ok((select bool_and(has_function_privilege('anon', sig::regprocedure, 'execute')
                           and has_function_privilege('authenticated', sig::regprocedure, 'execute')) from pub)
  and (select count(*) = 7 from pub), 'the seven public functions exist and are executable by anon and authenticated');
select is_empty($$ select sig from pub p join pg_proc f on f.oid = p.sig::regprocedure
  where not f.prosecdef or not ('search_path=""' = any (coalesce(f.proconfig, '{}'))) $$,
  'every Phase 9 public function is security definer with an empty search_path');
select is_empty($$ select sig from pub p join pg_proc f on f.oid = p.sig::regprocedure
  where (sig like 'public.admin\_%' and f.prosrc not like '%private.require_admin()%')
     or (sig like 'public.editor\_%' and f.prosrc not like '%private.require_active_editor()%') $$,
  'admin functions call require_admin and the editor list calls require_active_editor');
select is_empty($$ select sig from priv p join pg_proc f on f.oid = p.sig::regprocedure
  where f.prosecdef = (p.sig like 'private.payment\_transition\_allowed%')
     or not ('search_path=""' = any (coalesce(f.proconfig, '{}'))) $$,
  'Phase 9 private functions are security definer (payment_transition_allowed invoker), empty search_path');
select is_empty($$ select sig from priv
  where has_function_privilege('anon', sig::regprocedure, 'execute')
     or has_function_privilege('authenticated', sig::regprocedure, 'execute') $$,
  'no Phase 9 private function is executable by an API role');

-- ---------------------------------------------------------------------------
-- Role refusals: every function for anon, admin aal1, editors, suspended and applicant
-- ---------------------------------------------------------------------------
select set_eq($$
  select p.sig || ' ' || who.name || ' ' || pg_temp.state_as(who.uid, who.aal, p.call)
  from pub p cross join (values
    ('anon', null::uuid, 'aal1'), ('admin_aal1', '76000000-0000-0000-0000-00000000000a'::uuid, 'aal1'),
    ('editor_a', '76000000-0000-0000-0000-000000000001'::uuid, 'aal1'),
    ('editor_b', '76000000-0000-0000-0000-000000000002'::uuid, 'aal1'),
    ('suspended', '76000000-0000-0000-0000-000000000004'::uuid, 'aal1'),
    ('applicant', '76000000-0000-0000-0000-000000000003'::uuid, 'aal1')) who(name, uid, aal)
  where not (p.sig = 'public.editor_list_payments()' and who.name in ('editor_a', 'editor_b')) $$,
  $$ select p.sig || ' ' || who.name || ' ' || case when who.name = 'anon' then 'ES401' else 'ES403' end
  from pub p cross join (values ('anon'), ('admin_aal1'), ('editor_a'), ('editor_b'), ('suspended'), ('applicant')) who(name)
  where not (p.sig = 'public.editor_list_payments()' and who.name in ('editor_a', 'editor_b')) $$,
  'anon gets ES401 and every non-admin identity ES403 from each function');
select is(pg_temp.state_as('76000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select * from public.editor_list_payments() $$), 'ES403', 'an admin cannot call the editor list');

-- ---------------------------------------------------------------------------
-- Data hygiene and triggers
-- ---------------------------------------------------------------------------
select is_empty($$ select column_name from information_schema.columns
  where table_schema = 'public' and table_name = 'payments'
    and column_name ~ '(client|email|phone|company|contact|price|margin|note)' $$,
  'payments holds no client, price, margin or note columns');
select ok(pg_get_function_result('public.editor_list_payments()'::regprocedure)
  !~ '(client|email|phone|company|contact|price|margin|note|_by )', 'the editor list returns no such fields or actor ids');
select set_eq($$ select tablename::text || '.' || cmd from pg_policies
  where schemaname = 'public' and tablename in ('payments', 'payment_notes') $$,
  array['payments.SELECT', 'payment_notes.SELECT'], 'both tables have exactly one select-only policy');
select set_eq($$ select c.relname::text || '.' || t.tgname::text from pg_trigger t join pg_class c on c.oid = t.tgrelid
  where not t.tgisinternal and (c.relname in ('payments', 'payment_notes')
    or t.tgname in ('assignments_create_payment', 'assignments_hold_payments')) $$,
  array['payments.payments_set_updated_at', 'payments.payments_check_row', 'payments.payments_guard',
        'payments.payments_audit', 'payment_notes.payment_notes_append_only',
        'assignments.assignments_create_payment', 'assignments.assignments_hold_payments'],
  'payment triggers present by name');

-- ---------------------------------------------------------------------------
-- Audit details over one full flow (Review Focus 11)
-- ---------------------------------------------------------------------------
create temp table flow (kind text primary key, id uuid);
grant select, insert on flow to authenticated;
select pg_temp.as_user('76000000-0000-0000-0000-00000000000a', 'aal2');
insert into flow select 'project', public.admin_create_project(jsonb_build_object('title', 'Flow', 'brief_type',
  'fully_instructed', 'deadline', '2026-12-31', 'brief', jsonb_build_object('instructions', 'Cut it'),
  'deliverables', jsonb_build_array(jsonb_build_object('name', 'Main'))));
select public.admin_set_project_status((select id from flow where kind = 'project'), 'open');
insert into flow select 'asg', public.admin_make_offer((select id from flow where kind = 'project'),
  '76000000-0000-0000-0000-000000000001', 10000, 'LKR');
select pg_temp.as_user('76000000-0000-0000-0000-000000000001');
select public.editor_respond_offer((select id from flow where kind = 'asg'), 'accept');
select pg_temp.as_user('76000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_confirm_assignment((select id from flow where kind = 'asg'));
insert into flow select 'pay', id from public.payments where assignment_id = (select id from flow where kind = 'asg');
select public.admin_set_payment_due_date((select id from flow where kind = 'pay'), '2027-01-15');
select public.admin_set_payment_status((select id from flow where kind = 'pay'), 'pending_approval');
select public.admin_set_payment_status((select id from flow where kind = 'pay'), 'approved');
select public.admin_set_payment_status((select id from flow where kind = 'pay'), 'processing');
select public.admin_set_payment_status((select id from flow where kind = 'pay'), 'on_hold', 'Hold reason zz');
select public.admin_release_payment_hold((select id from flow where kind = 'pay'));
select public.admin_mark_payment_paid((select id from flow where kind = 'pay'), 'TESTREF-77',
  (now() at time zone 'Asia/Colombo')::date);
select public.admin_reverse_payment((select id from flow where kind = 'pay'), 'Reverse reason yy', true);
select public.admin_add_payment_note((select id from flow where kind = 'pay'), 'Note text qq');
select public.admin_reassign((select id from flow where kind = 'asg'));
reset role;

select set_eq($$ select distinct action from public.activity_logs where action like 'payment%' $$,
  array['payment.created', 'payment.due_date_set', 'payment.pending_approval', 'payment.approved', 'payment.processing',
        'payment.on_hold', 'payment.hold_released', 'payment.paid', 'payment.reversed', 'payment_note.added'],
  'every payment action is audited');
select is_empty($$ select id from public.activity_logs where action like 'payment%'
  and (select array_agg(k order by k) from jsonb_object_keys(details) k)
      is distinct from array['assignment_id', 'from', 'payment_id', 'to'] $$,
  'payment audit rows carry exactly payment_id, assignment_id, from and to');
select is_empty(format($$ select id from public.activity_logs where action like 'payment%%'
  and (details::text ~ '(10000|TESTREF-77|Hold reason zz|Reverse reason yy|Note text qq|2027-01-15)'
       or details::text like '%%%s%%') $$, (now() at time zone 'Asia/Colombo')::date::text),
  'payment audit rows hold no amounts, references, reasons, notes or dates');

select * from finish();
rollback;
