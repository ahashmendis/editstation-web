-- Phase 9: payment created at confirmation; unpaid payments held when the assignment ends.
-- Review Focus 1, 2.
begin;

create extension if not exists pgtap with schema extensions;

select plan(23);

create function pg_temp.as_user(p_uid uuid, p_aal text default 'aal1')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;
grant execute on function pg_temp.as_user(uuid, text) to authenticated;

-- Accepted (and optionally confirmed, brief-confirmed and started) assignment for 10000 LKR.
create function pg_temp.assignment(p_title text, p_editor uuid, p_confirm boolean default true,
  p_start boolean default false)
returns uuid language plpgsql as $$
declare
  v_project uuid;
  v_id uuid;
begin
  perform pg_temp.as_user('72000000-0000-0000-0000-00000000000a', 'aal2');
  v_project := public.admin_create_project(jsonb_build_object('title', p_title, 'brief_type', 'fully_instructed',
    'deadline', '2026-12-31', 'requires_interpretation', false, 'brief', jsonb_build_object('instructions', 'Cut it'),
    'deliverables', jsonb_build_array(jsonb_build_object('name', 'Main'))));
  perform public.admin_set_project_status(v_project, 'open');
  v_id := public.admin_make_offer(v_project, p_editor, 10000, 'LKR');
  perform pg_temp.as_user(p_editor);
  perform public.editor_respond_offer(v_id, 'accept');
  if p_confirm then
    perform pg_temp.as_user('72000000-0000-0000-0000-00000000000a', 'aal2');
    perform public.admin_confirm_assignment(v_id);
  end if;
  if p_start then
    perform pg_temp.as_user(p_editor);
    perform public.editor_confirm_brief(v_id, 1, '2026-12-31', 10000, 'LKR');
    perform public.editor_start_work(v_id);
  end if;
  reset role;
  return v_id;
end;
$$;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('72000000-0000-0000-0000-00000000000a', 'p9t-admin@test.local', '{}', '{}'),
  ('72000000-0000-0000-0000-000000000001', 'p9t-editor-a@test.local', '{}', '{}'),
  ('72000000-0000-0000-0000-000000000002', 'p9t-editor-b@test.local', '{}', '{}');
select private.grant_admin_by_email('p9t-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('72000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000002');

create temp table ids (kind text primary key, id uuid not null);
grant select, insert on ids to authenticated;
create function pg_temp.a(p_kind text) returns uuid language sql as $$ select id from ids where kind = p_kind $$;
grant execute on function pg_temp.a(text) to authenticated;
create function pg_temp.pay(p_kind text) returns public.payments language sql as $$
  select * from public.payments where assignment_id = (select id from ids where kind = p_kind)
  order by created_at desc, id limit 1 $$;
create function pg_temp.project(p_kind text) returns uuid language sql as $$
  select project_id from public.assignments where id = (select id from ids where kind = p_kind) $$;

-- ---------------------------------------------------------------------------
-- Creation on confirmation (Review Focus 1): two editors accept, A is confirmed.
-- ---------------------------------------------------------------------------
insert into ids select 'c', pg_temp.assignment('Confirm', '72000000-0000-0000-0000-000000000001', false);
select pg_temp.as_user('72000000-0000-0000-0000-00000000000a', 'aal2');
insert into ids select 'nb', public.admin_make_offer(pg_temp.project('c'), '72000000-0000-0000-0000-000000000002', 10000, 'LKR');
select pg_temp.as_user('72000000-0000-0000-0000-000000000002');
select public.editor_respond_offer(pg_temp.a('nb'), 'accept');
reset role;
select is((select count(*)::int from public.payments), 0, 'accepting creates no payment');
select pg_temp.as_user('72000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_confirm_assignment(pg_temp.a('c'));
reset role;
select is((select count(*)::int from public.payments where assignment_id = pg_temp.a('c')), 1,
  'confirmation creates exactly one payment');
select ok((select kind = 'assignment' and status = 'not_due' and amount = 10000 and currency = 'LKR'
    and created_by = '72000000-0000-0000-0000-00000000000a' and editor_id = '72000000-0000-0000-0000-000000000001'
    and project_id = pg_temp.project('c') and held_from_status is null and on_hold_reason is null
  from pg_temp.pay('c')), 'the payment copies the agreed amount, currency and confirming admin');
select is((select status::text from public.assignments where id = pg_temp.a('nb')), 'not_selected',
  'the other editor is not selected');
select is((select count(*)::int from public.payments where assignment_id = pg_temp.a('nb')), 0,
  'a not-selected offer has no payment');
select ok((select count(*) = 1 and bool_and(actor_id = '72000000-0000-0000-0000-00000000000a')
  from public.activity_logs where action = 'payment.created' and details ->> 'assignment_id' = pg_temp.a('c')::text),
  'one payment.created audit row by the confirming admin');
select pg_temp.as_user('72000000-0000-0000-0000-000000000001');
select is((select count(*)::int from public.editor_list_payments()), 1, 'editor A lists the new payment');
reset role;

insert into public.projects (id, title, brief_type, status, first_opened_at, proposed_currency) values
  ('72000000-0000-0000-0000-0000000000f9', 'Seeded', 'fully_instructed', 'assigned', now(), 'LKR');
insert into public.assignments (id, project_id, editor_id, status, proposed_amount, agreed_amount, agreed_currency,
  confirmed_at) values
  ('72000000-0000-0000-0000-0000000000b9', '72000000-0000-0000-0000-0000000000f9',
   '72000000-0000-0000-0000-000000000002', 'confirmed', 5000, 5000, 'LKR', now());
select is((select count(*)::int from public.payments where assignment_id = '72000000-0000-0000-0000-0000000000b9'), 0,
  'a seeded confirmed insert creates no payment');

-- ---------------------------------------------------------------------------
-- Holds when the assignment ends (Review Focus 2)
-- ---------------------------------------------------------------------------
-- (a) reassign from confirmed with a not_due payment
select pg_temp.as_user('72000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_reassign(pg_temp.a('c'));
reset role;
select ok((select status = 'on_hold' and held_from_status = 'not_due'
    and on_hold_reason = 'The assignment ended before the work was finished. Lenscape will contact you about this payment.'
  from pg_temp.pay('c')), '(a) reassign from confirmed holds the not_due payment with the fixed reason');

-- (b) reassign from in_progress with an approved payment
insert into ids select 'i', pg_temp.assignment('Started', '72000000-0000-0000-0000-000000000001', true, true);
select is((select status::text from public.assignments where id = pg_temp.a('i')), 'in_progress', 'work started');
update public.payments set status = 'pending_approval' where assignment_id = pg_temp.a('i');
update public.payments set status = 'approved', approved_at = now() where assignment_id = pg_temp.a('i');
select pg_temp.as_user('72000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_reassign(pg_temp.a('i'));
reset role;
select ok((select status = 'on_hold' and held_from_status = 'approved' from pg_temp.pay('i')),
  '(b) reassign from in_progress holds the approved payment');

-- (c) project cancellation withdraws the confirmed assignment
insert into ids select 'x', pg_temp.assignment('Cancel', '72000000-0000-0000-0000-000000000001');
select pg_temp.as_user('72000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_set_project_status(pg_temp.project('x'), 'cancelled');
reset role;
select is((select status::text from public.assignments where id = pg_temp.a('x')), 'withdrawn', 'cancel withdraws');
select ok((select status = 'on_hold' and held_from_status = 'not_due'
    and on_hold_reason like 'The assignment ended before the work was finished.%' from pg_temp.pay('x')),
  '(c) cancellation holds the payment');

-- (c2) cancelling an in_progress project holds its pending-approval payment
insert into ids select 'x2', pg_temp.assignment('Cancel started', '72000000-0000-0000-0000-000000000001', true, true);
update public.payments set status = 'pending_approval' where assignment_id = pg_temp.a('x2');
select is((select status::text from public.projects where id = pg_temp.project('x2')), 'in_progress',
  '(c2) the project is in progress');
select pg_temp.as_user('72000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_set_project_status(pg_temp.project('x2'), 'cancelled');
reset role;
select ok((select status = 'on_hold' and held_from_status = 'pending_approval'
    and on_hold_reason like 'The assignment ended before the work was finished.%' from pg_temp.pay('x2')),
  '(c2) cancelling an in_progress project holds the unpaid payment');

-- (d) a payment already on hold keeps the admin's reason
insert into ids select 'd', pg_temp.assignment('Held', '72000000-0000-0000-0000-000000000001');
update public.payments set status = 'on_hold', held_from_status = 'not_due', on_hold_reason = 'Admin reason'
where assignment_id = pg_temp.a('d');
select pg_temp.as_user('72000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_reassign(pg_temp.a('d'));
reset role;
select ok((select status = 'on_hold' and held_from_status = 'not_due' and on_hold_reason = 'Admin reason'
  from pg_temp.pay('d')), '(d) an existing hold keeps its reason');

-- (e) paid row and its reversal untouched
insert into ids select 'e', pg_temp.assignment('Paid', '72000000-0000-0000-0000-000000000002');
update public.payments set status = 'pending_approval' where assignment_id = pg_temp.a('e');
update public.payments set status = 'approved', approved_at = now() where assignment_id = pg_temp.a('e');
update public.payments set status = 'paid', marked_paid_at = now(), transaction_reference = 'R', transfer_date = current_date
where assignment_id = pg_temp.a('e');
insert into public.payments (assignment_id, project_id, editor_id, kind, amount, currency, status, marked_paid_at,
  reverses_payment_id, reversal_reason)
select assignment_id, project_id, editor_id, 'reversal', -amount, currency, 'paid', now(), id, 'Returned'
from public.payments where assignment_id = pg_temp.a('e');
create temp table e_before as select id, updated_at from public.payments where assignment_id = pg_temp.a('e');
select pg_temp.as_user('72000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_reassign(pg_temp.a('e'));
reset role;
select ok((select count(*) = 2 and bool_and(p.status = 'paid' and p.updated_at = b.updated_at)
  from public.payments p join e_before b using (id)), '(e) paid row and reversal are untouched');

-- (f) withdrawing an accepted offer changes nothing
insert into ids select 'f', pg_temp.assignment('Withdraw', '72000000-0000-0000-0000-000000000001', false);
create temp table f_count as select count(*) n from public.payments;
select pg_temp.as_user('72000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_withdraw_offer(pg_temp.a('f'));
reset role;
select is((select count(*) from public.payments), (select n from f_count), '(f) withdrawing an accepted offer adds no payment');
select is((select count(*)::int from public.payments where assignment_id = pg_temp.a('f')), 0, '(f) no payment for it');

-- Audit
select is((select count(*)::int from public.activity_logs where action = 'payment.on_hold'
  and details ->> 'assignment_id' in (pg_temp.a('c')::text, pg_temp.a('i')::text, pg_temp.a('x')::text)), 3,
  'one payment.on_hold audit row per held payment');
select is((select count(*)::int from public.activity_logs where action = 'payment.on_hold'
  and details ->> 'assignment_id' = pg_temp.a('d')::text), 1, 'an existing hold is not logged again');
select is((select count(*)::int from public.activity_logs where action = 'payment.created'), 6,
  'one payment.created row per confirmation');
select ok((select bool_and(details ->> 'to' = 'on_hold' and details ->> 'from' is not null)
  from public.activity_logs where action = 'payment.on_hold'), 'hold audit rows carry from and to');

select * from finish();
rollback;
