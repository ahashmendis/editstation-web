-- Phase 12D part 1: payments milestone columns, enums, constraints, the per-milestone open key,
-- the split invariant trigger, the waiting flag and the triggers that keep editor pay in step with
-- client payments and approval. RLS on payments is unchanged (admin select only).
begin;

create extension if not exists pgtap with schema extensions;

select plan(22);

create function pg_temp.as_user(p_uid uuid, p_aal text default 'aal1')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('d2000000-0000-0000-0000-00000000000a', 'p12ds-admin@test.local', '{}', '{}'),
  ('d2000000-0000-0000-0000-000000000001', 'p12ds-editor-a@test.local', '{}', '{}'),
  ('d2000000-0000-0000-0000-000000000002', 'p12ds-editor-b@test.local', '{}', '{}'),
  ('d2000000-0000-0000-0000-000000000003', 'p12ds-applicant@test.local', '{}', '{}');
select private.grant_admin_by_email('p12ds-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('d2000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000002');

-- A seeded confirmed assignment (trigger-free insert) with two milestone rows.
insert into public.projects (id, title, brief_type, status, first_opened_at) values
  ('d2000000-0000-0000-0000-0000000000f1', 'Schema pay', 'fully_instructed', 'assigned', now());
update public.project_terms set status = 'agreed', agreed_at = now()
where project_id = 'd2000000-0000-0000-0000-0000000000f1';
insert into public.assignments (id, project_id, editor_id, status, proposed_amount, agreed_amount, agreed_currency,
  confirmed_at) values
  ('d2000000-0000-0000-0000-0000000000b1', 'd2000000-0000-0000-0000-0000000000f1',
   'd2000000-0000-0000-0000-000000000001', 'confirmed', 1000, 1000, 'LKR', now());
insert into public.payments (id, assignment_id, project_id, editor_id, milestone_seq, amount, currency) values
  ('d2000000-0000-0000-0000-0000000000c1', 'd2000000-0000-0000-0000-0000000000b1',
   'd2000000-0000-0000-0000-0000000000f1', 'd2000000-0000-0000-0000-000000000001', 1, 500, 'LKR'),
  ('d2000000-0000-0000-0000-0000000000c2', 'd2000000-0000-0000-0000-0000000000b1',
   'd2000000-0000-0000-0000-0000000000f1', 'd2000000-0000-0000-0000-000000000001', 2, 500, 'LKR');

select has_column('public', 'payments', 'milestone_seq', 'payments.milestone_seq exists');
select col_is_null('public', 'payments', 'milestone_seq',
  'milestone_seq is nullable (12D part 2: extra pay and settlement lines have none; payments_line_chk)');
select col_type_is('public', 'payments', 'payable_reason', 'payment_payable_reason', 'payable_reason is an enum');
select col_not_null('public', 'payments', 'waiting_on_client', 'waiting_on_client is a required boolean');
select enum_has_labels('public', 'payment_payable_reason', array['client_deposit_verified', 'client_balance_verified',
  'late_balance_protection', 'adjustment_accepted', 'cancellation_settlement'], 'payable reasons');
select enum_has_labels('public', 'payment_hold_label',
  array['under_review', 'assignment_ended', 'waiting_for_client_payment'], 'editor hold labels');
select ok('late_balance_payable' = any (enum_range(null::public.notification_kind)::text[]),
  'notification kind late_balance_payable exists');
select set_has($$ select conname::text from pg_constraint where conrelid = 'public.payments'::regclass $$,
  $$ values ('payments_payable_chk'), ('payments_waiting_chk'), ('payments_split_chk') $$, 'new constraints by name');
select ok((select indexdef ~ '\(assignment_id, milestone_seq\)' and indexdef ~ 'split_from_payment_id IS NULL'
  from pg_indexes where indexname = 'payments_open_key'), 'the open key is per (assignment, milestone)');

-- Open key: one unpaid row per milestone (the sum guard is bypassed to reach the index).
set local session_replication_role = replica;
select throws_ok($$ insert into public.payments (assignment_id, project_id, editor_id, milestone_seq, amount, currency)
  values ('d2000000-0000-0000-0000-0000000000b1', 'd2000000-0000-0000-0000-0000000000f1',
          'd2000000-0000-0000-0000-000000000001', 2, 10, 'LKR') $$, '23505', null,
  'a second open row for the same milestone is refused');
select throws_ok($$ insert into public.payments (assignment_id, project_id, editor_id, milestone_seq, amount, currency,
  status, waiting_on_client) values ('d2000000-0000-0000-0000-0000000000b1', 'd2000000-0000-0000-0000-0000000000f1',
          'd2000000-0000-0000-0000-000000000001', 3, 10, 'LKR', 'pending_approval', true) $$, '23514', null,
  'only a not_due row can wait for the client');
set local session_replication_role = origin;

select throws_ok($$ insert into public.payments (assignment_id, project_id, editor_id, milestone_seq, amount, currency)
  values ('d2000000-0000-0000-0000-0000000000b1', 'd2000000-0000-0000-0000-0000000000f1',
          'd2000000-0000-0000-0000-000000000001', 3, 0.01, 'LKR') $$, 'ES409', null,
  'milestones cannot add up to more than the agreed amount');
select throws_ok($$ insert into public.payments (assignment_id, project_id, editor_id, milestone_seq, amount, currency,
  status, split_from_payment_id) values ('d2000000-0000-0000-0000-0000000000b1', 'd2000000-0000-0000-0000-0000000000f1',
          'd2000000-0000-0000-0000-000000000001', 1, 100, 'LKR', 'not_due', 'd2000000-0000-0000-0000-0000000000c1') $$,
  'ES409', null, 'a split child must start on hold (and fit the agreed amount)');
select throws_ok($$ update public.payments set milestone_seq = 3 where id = 'd2000000-0000-0000-0000-0000000000c1' $$,
  'ES409', null, 'the milestone of a row cannot change');

-- Waiting flag cleared by any move out of not_due.
update public.payments set waiting_on_client = true where id = 'd2000000-0000-0000-0000-0000000000c1';
update public.payments set status = 'on_hold', held_from_status = 'not_due', on_hold_reason = 'x'
where id = 'd2000000-0000-0000-0000-0000000000c1';
select ok((select not waiting_on_client from public.payments where id = 'd2000000-0000-0000-0000-0000000000c1'),
  'a hold clears waiting_on_client');

-- payable_at / payable_reason are set together and fixed once set.
select throws_ok($$ update public.payments set payable_reason = 'client_deposit_verified'
  where id = 'd2000000-0000-0000-0000-0000000000c2' $$, '23514', null, 'a payable reason needs a payable time');
update public.payments set status = 'pending_approval', payable_reason = 'client_deposit_verified', payable_at = now()
where id = 'd2000000-0000-0000-0000-0000000000c2';
select throws_ok($$ update public.payments set payable_reason = 'late_balance_protection'
  where id = 'd2000000-0000-0000-0000-0000000000c2' $$, 'ES409', null, 'the payable reason is fixed once set');

-- Triggers by name.
select set_has($$ select c.relname::text || '.' || t.tgname::text from pg_trigger t join pg_class c on c.oid = t.tgrelid
  where not t.tgisinternal $$,
  $$ values ('payments.payments_clear_waiting'), ('payments.payments_split_sum'),
            ('client_milestones.client_milestones_sync_editor_pay'),
            ('client_milestones.client_milestones_sync_editor_pay_refund'), ('projects.projects_sync_editor_pay'),
            ('assignments.assignments_create_payment'), ('assignments.assignments_hold_payments') $$,
  'editor pay triggers present by name');
select ok((select tgdeferrable and not tginitdeferred from pg_trigger where tgname = 'payments_split_sum'),
  'the split invariant is checked per statement unless the split function defers it');

-- RLS unchanged: editors, applicants and anon read no payment rows.
select pg_temp.as_user('d2000000-0000-0000-0000-000000000001');
select is((select count(*)::int from public.payments), 0, 'editor A reads no payment rows directly');
select pg_temp.as_user('d2000000-0000-0000-0000-000000000003');
select is((select count(*)::int from public.payments), 0, 'a pending applicant reads no payment rows');
reset role;
select pg_temp.as_user('d2000000-0000-0000-0000-00000000000a', 'aal2');
select is((select count(*)::int from public.payments where assignment_id = 'd2000000-0000-0000-0000-0000000000b1'), 2,
  'the admin reads the milestone rows');
reset role;

select * from finish();
rollback;
