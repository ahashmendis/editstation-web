-- Phase 9: RLS on payments and payment_notes per identity (spec §6); no direct writes (Review Focus 10).
begin;

create extension if not exists pgtap with schema extensions;

select plan(30);

create function pg_temp.as_user(p_uid uuid, p_aal text default 'aal1')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create function pg_temp.as_anon()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('role', 'anon', true);
end;
$$;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('71000000-0000-0000-0000-00000000000a', 'p9v-admin@test.local', '{}', '{}'),
  ('71000000-0000-0000-0000-000000000001', 'p9v-editor-a@test.local', '{}', '{}'),
  ('71000000-0000-0000-0000-000000000002', 'p9v-editor-b@test.local', '{}', '{}'),
  ('71000000-0000-0000-0000-000000000003', 'p9v-applicant@test.local', '{}', '{}'),
  ('71000000-0000-0000-0000-000000000004', 'p9v-suspended@test.local', '{}', '{}');
select private.grant_admin_by_email('p9v-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('71000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000002',
                  '71000000-0000-0000-0000-000000000004');

insert into public.projects (id, title, brief_type, status, first_opened_at, proposed_currency)
select ('71000000-0000-0000-0000-0000000000f' || n)::uuid, 'P' || n, 'fully_instructed', 'assigned', now(), 'LKR'
from generate_series(1, 4) n;
insert into public.assignments (id, project_id, editor_id, status, proposed_amount, agreed_amount, agreed_currency,
  confirmed_at) values
  ('71000000-0000-0000-0000-0000000000a1', '71000000-0000-0000-0000-0000000000f1',
   '71000000-0000-0000-0000-000000000001', 'confirmed', 10000, 10000, 'LKR', now()),
  ('71000000-0000-0000-0000-0000000000a2', '71000000-0000-0000-0000-0000000000f2',
   '71000000-0000-0000-0000-000000000001', 'confirmed', 8000, 8000, 'LKR', now()),
  ('71000000-0000-0000-0000-0000000000a3', '71000000-0000-0000-0000-0000000000f3',
   '71000000-0000-0000-0000-000000000002', 'confirmed', 7000, 7000, 'LKR', now()),
  ('71000000-0000-0000-0000-0000000000a4', '71000000-0000-0000-0000-0000000000f4',
   '71000000-0000-0000-0000-000000000004', 'confirmed', 6000, 6000, 'LKR', now());
insert into public.payments (id, assignment_id, project_id, editor_id, amount, currency, status, approved_at,
  marked_paid_at, transaction_reference, transfer_date)
select ('71000000-0000-0000-0000-0000000000c' || right(a.id::text, 1))::uuid, a.id, a.project_id, a.editor_id,
  a.agreed_amount, 'LKR', case when a.id = '71000000-0000-0000-0000-0000000000a2' then 'paid' else 'not_due' end::public.payment_status,
  now(), now(), 'REF', current_date
from public.assignments a where a.id::text like '71000000-%';
insert into public.payment_notes (payment_id, author_id, note) values
  ('71000000-0000-0000-0000-0000000000c1', '71000000-0000-0000-0000-00000000000a', 'Internal only');
update public.editor_profiles set access_status = 'suspended' where user_id = '71000000-0000-0000-0000-000000000004';

create function pg_temp.counts() returns text language sql as $$
  select (select count(*) from public.payments)::text || '/' || (select count(*) from public.payment_notes)::text $$;
grant execute on function pg_temp.counts() to authenticated;

-- Row counts per identity
select pg_temp.as_user('71000000-0000-0000-0000-00000000000a', 'aal2');
select is(pg_temp.counts(), '4/1', 'admin aal2 sees every payment and note');
select pg_temp.as_user('71000000-0000-0000-0000-00000000000a', 'aal1');
select is(pg_temp.counts(), '0/0', 'admin aal1 sees nothing');
select pg_temp.as_user('71000000-0000-0000-0000-000000000001');
select is(pg_temp.counts(), '0/0', 'editor A reads no payment rows directly (actor ids stay admin-only)');
select is((select count(*)::int from public.editor_list_payments()), 2,
  'editor A lists own two payments through editor_list_payments');
select pg_temp.as_user('71000000-0000-0000-0000-000000000002');
select is(pg_temp.counts(), '0/0', 'editor B reads no payment rows directly');
select is((select count(*)::int from public.payments where editor_id = '71000000-0000-0000-0000-000000000001'), 0,
  'editor B sees none of A''s');
select pg_temp.as_user('71000000-0000-0000-0000-000000000004');
select is(pg_temp.counts(), '0/0', 'a suspended editor sees nothing, own payment included');
select pg_temp.as_user('71000000-0000-0000-0000-000000000003');
select is(pg_temp.counts(), '0/0', 'an applicant sees nothing');
reset role;
select pg_temp.as_anon();
select throws_ok($$ select count(*) from public.payments $$, '42501', null, 'anon cannot read payments');
select throws_ok($$ select count(*) from public.payment_notes $$, '42501', null, 'anon cannot read payment notes');
reset role;

-- No direct writes for anyone (Review Focus 10)
select pg_temp.as_user('71000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ insert into public.payments (assignment_id, project_id, editor_id, amount, currency)
  values ('71000000-0000-0000-0000-0000000000a3', '71000000-0000-0000-0000-0000000000f3',
          '71000000-0000-0000-0000-000000000002', 7000, 'LKR') $$, '42501', null, 'admin cannot insert payments');
select throws_ok($$ update public.payments set due_date = current_date $$, '42501', null, 'admin cannot update payments');
select throws_ok($$ delete from public.payments $$, '42501', null, 'admin cannot delete payments');
select throws_ok($$ insert into public.payment_notes (payment_id, note) values ('71000000-0000-0000-0000-0000000000c1', 'x') $$,
  '42501', null, 'admin cannot insert payment notes');
select throws_ok($$ update public.payment_notes set note = 'x' $$, '42501', null, 'admin cannot update payment notes');
select throws_ok($$ delete from public.payment_notes $$, '42501', null, 'admin cannot delete payment notes');
select pg_temp.as_user('71000000-0000-0000-0000-000000000001');
select throws_ok($$ insert into public.payments (assignment_id, project_id, editor_id, amount, currency)
  values ('71000000-0000-0000-0000-0000000000a1', '71000000-0000-0000-0000-0000000000f1',
          '71000000-0000-0000-0000-000000000001', 10000, 'LKR') $$, '42501', null, 'editor cannot insert payments');
select throws_ok($$ update public.payments set status = 'paid' $$, '42501', null, 'editor cannot update payments');
select throws_ok($$ delete from public.payments $$, '42501', null, 'editor cannot delete payments');
select throws_ok($$ insert into public.payment_notes (payment_id, note) values ('71000000-0000-0000-0000-0000000000c1', 'x') $$,
  '42501', null, 'editor cannot insert payment notes');
select throws_ok($$ update public.payment_notes set note = 'x' $$, '42501', null, 'editor cannot update payment notes');
select throws_ok($$ delete from public.payment_notes $$, '42501', null, 'editor cannot delete payment notes');
reset role;
select pg_temp.as_anon();
select throws_ok($$ update public.payments set due_date = current_date $$, '42501', null, 'anon cannot update payments');
reset role;

-- Grants and policies
select ok(not has_table_privilege('authenticated', 'public.payments', 'insert, update, delete'),
  'authenticated has no write privilege on payments');
select ok(not has_table_privilege('authenticated', 'public.payment_notes', 'insert, update, delete'),
  'authenticated has no write privilege on payment_notes');
select ok(not has_table_privilege('anon', 'public.payments', 'select'), 'anon has no select on payments');
select ok(not has_table_privilege('anon', 'public.payment_notes', 'select'), 'anon has no select on payment_notes');
select policies_are('public', 'payments', array['payments_select'], 'payments has one select policy');
select policies_are('public', 'payment_notes', array['payment_notes_select'], 'payment_notes has one select policy');
select ok((select relrowsecurity from pg_class where oid = 'public.payments'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.payment_notes'::regclass), 'RLS is on for both tables');

select * from finish();
rollback;
