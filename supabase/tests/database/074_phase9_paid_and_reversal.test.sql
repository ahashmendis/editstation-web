-- Phase 9: admin_mark_payment_paid, admin_reverse_payment, admin_add_payment_note. Review Focus 6, 7.
begin;

create extension if not exists pgtap with schema extensions;

select plan(42);

create function pg_temp.as_user(p_uid uuid, p_aal text default 'aal1')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;
grant execute on function pg_temp.as_user(uuid, text) to authenticated;

-- Confirmed assignment whose payment is moved (as the admin) to p_status. Returns the payment id.
create function pg_temp.payment(p_title text, p_status text)
returns uuid language plpgsql as $$
declare
  v_project uuid;
  v_id uuid;
  v_pay uuid;
begin
  perform pg_temp.as_user('74000000-0000-0000-0000-00000000000a', 'aal2');
  v_project := public.admin_create_project(jsonb_build_object('title', p_title, 'brief_type', 'fully_instructed',
    'deadline', '2026-12-31', 'brief', jsonb_build_object('instructions', 'Cut it'),
    'deliverables', jsonb_build_array(jsonb_build_object('name', 'Main'))));
  perform public.admin_set_project_status(v_project, 'open');
  -- Phase 12D: one editor milestone (100%) keeps one payment per assignment in these tests.
  perform public.admin_save_terms_draft(v_project, '{"editor_milestone_shares": [100]}');
  perform public.admin_agree_terms(v_project, 1);
  v_id := public.admin_make_offer(v_project, '74000000-0000-0000-0000-000000000001', 10000, 'LKR');
  perform pg_temp.as_user('74000000-0000-0000-0000-000000000001');
  perform public.editor_respond_offer(v_id, 'accept');
  perform pg_temp.as_user('74000000-0000-0000-0000-00000000000a', 'aal2');
  perform public.admin_confirm_assignment(v_id);
  select id into v_pay from public.payments where assignment_id = v_id;
  if p_status in ('pending_approval', 'approved', 'processing', 'paid') then
    -- Phase 12D: made payable as by the milestone rules (seeded as the table owner).
    reset role;
    update public.payments set status = 'pending_approval', payable_reason = 'client_deposit_verified',
      payable_at = now() where id = v_pay;
    perform pg_temp.as_user('74000000-0000-0000-0000-00000000000a', 'aal2');
  end if;
  if p_status in ('approved', 'processing', 'paid') then
    perform public.admin_set_payment_status(v_pay, 'approved');
  end if;
  if p_status = 'processing' then
    perform public.admin_set_payment_status(v_pay, 'processing');
  end if;
  if p_status = 'on_hold' then
    perform public.admin_set_payment_status(v_pay, 'on_hold', 'Waiting');
  end if;
  if p_status = 'paid' then
    perform public.admin_mark_payment_paid(v_pay, 'SEED', (now() at time zone 'Asia/Colombo')::date);
  end if;
  reset role;
  return v_pay;
end;
$$;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('74000000-0000-0000-0000-00000000000a', 'p9p-admin@test.local', '{}', '{}'),
  ('74000000-0000-0000-0000-000000000001', 'p9p-editor-a@test.local', '{}', '{}');
select private.grant_admin_by_email('p9p-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active' where user_id = '74000000-0000-0000-0000-000000000001';

create temp table ids (kind text primary key, id uuid not null);
grant select, insert on ids to authenticated;
insert into ids select 'm1', pg_temp.payment('M1', 'approved');
insert into ids select 'm2', pg_temp.payment('M2', 'processing');
insert into ids select 'm3', pg_temp.payment('M3', 'not_due');
insert into ids select 'm4', pg_temp.payment('M4', 'pending_approval');
insert into ids select 'm5', pg_temp.payment('M5', 'on_hold');
insert into ids select 'm6', pg_temp.payment('M6', 'approved');
insert into ids select 'm7', pg_temp.payment('M7', 'paid');
insert into ids select 'm8', pg_temp.payment('M8', 'paid');
create function pg_temp.p(p_kind text) returns uuid language sql as $$ select id from ids where kind = p_kind $$;
grant execute on function pg_temp.p(text) to authenticated;
create function pg_temp.row(p_kind text) returns public.payments language sql as $$
  select * from public.payments where id = (select id from ids where kind = p_kind) $$;
grant execute on function pg_temp.row(text) to authenticated;
create function pg_temp.today() returns date language sql as $$ select (now() at time zone 'Asia/Colombo')::date $$;
grant execute on function pg_temp.today() to authenticated;

select pg_temp.as_user('74000000-0000-0000-0000-00000000000a', 'aal2');

-- Mark paid
select lives_ok($$ select public.admin_mark_payment_paid(pg_temp.p('m1'), '  REF-001  ', pg_temp.today()) $$,
  'mark paid from approved');
select ok((select status = 'paid' and transaction_reference = 'REF-001' and transfer_date = pg_temp.today()
    and marked_paid_by = '74000000-0000-0000-0000-00000000000a' and marked_paid_at is not null from pg_temp.row('m1')),
  'paid row stores the trimmed reference, transfer date and who marked it');
select lives_ok($$ select public.admin_mark_payment_paid(pg_temp.p('m2'), 'REF-002', pg_temp.today()) $$,
  'mark paid from processing');
select throws_ok($$ select public.admin_mark_payment_paid(pg_temp.p('m3'), 'R', pg_temp.today()) $$, 'ES409',
  'This payment cannot move from not due to paid.', 'mark paid from not_due');
select throws_ok($$ select public.admin_mark_payment_paid(pg_temp.p('m4'), 'R', pg_temp.today()) $$, 'ES409', null,
  'mark paid from pending approval');
select throws_ok($$ select public.admin_mark_payment_paid(pg_temp.p('m5'), 'R', pg_temp.today()) $$, 'ES409', null,
  'mark paid from on hold');
select throws_ok($$ select public.admin_mark_payment_paid(pg_temp.p('m1'), 'R', pg_temp.today()) $$, 'ES409',
  'This payment has been paid and cannot be changed.', 'mark paid twice');
select throws_ok($$ select public.admin_mark_payment_paid(pg_temp.p('m6'), null, pg_temp.today()) $$, 'ES422', null,
  'reference missing');
select throws_ok($$ select public.admin_mark_payment_paid(pg_temp.p('m6'), '   ', pg_temp.today()) $$, 'ES422', null,
  'reference blank');
select throws_ok($$ select public.admin_mark_payment_paid(pg_temp.p('m6'), repeat('r', 121), pg_temp.today()) $$,
  'ES422', null, 'reference of 121 characters');
select throws_ok($$ select public.admin_mark_payment_paid(pg_temp.p('m6'), 'R', null) $$, 'ES422', null,
  'transfer date missing');
select throws_ok($$ select public.admin_mark_payment_paid(pg_temp.p('m6'), 'R', pg_temp.today() + 1) $$, 'ES422', null,
  'transfer date tomorrow in Colombo');
select throws_ok($$ select public.admin_mark_payment_paid(pg_temp.p('m6'), 'R', pg_temp.today() - 1) $$, 'ES422', null,
  'transfer date before confirmation');
select is((pg_temp.row('m6')).status::text, 'approved', 'refusals leave the payment approved');

-- Reverse
select throws_ok($$ select public.admin_reverse_payment(pg_temp.p('m6'), 'Why', false) $$, 'ES409', null,
  'reversing an unpaid payment');
select throws_ok($$ select public.admin_reverse_payment(pg_temp.p('m1'), '  ', false) $$, 'ES422', null,
  'reversal needs a reason');
select throws_ok($$ select public.admin_reverse_payment(pg_temp.p('m1'), repeat('x', 501), false) $$, 'ES422', null,
  'reversal reason of 501 characters');
select throws_ok($$ select public.admin_reverse_payment(pg_temp.p('m1'), 'Why', null) $$, 'ES422', null,
  're-open must be chosen');
insert into ids select 'r1', public.admin_reverse_payment(pg_temp.p('m1'), '  Money returned  ', false);
select ok((select kind = 'reversal' and amount = -10000 and currency = 'LKR' and status = 'paid'
    and reverses_payment_id = pg_temp.p('m1') and reversal_reason = 'Money returned'
    and marked_paid_by = '74000000-0000-0000-0000-00000000000a' and marked_paid_at is not null
    and transaction_reference is null and transfer_date is null and approved_at is null
  from pg_temp.row('r1')), 'the reversal row is negative, paid, linked and carries the reason');
select is((select sum(amount) from public.payments
  where assignment_id = (pg_temp.row('m1')).assignment_id and status = 'paid'), 0.00, 'paid total nets to zero');
select is((select count(*)::int from public.payments where assignment_id = (pg_temp.row('m1')).assignment_id), 2,
  'without re-open no new liability is added');
select throws_ok($$ select public.admin_reverse_payment(pg_temp.p('m1'), 'Again', false) $$, 'ES409', null,
  'an already reversed payment');
select throws_ok($$ select public.admin_reverse_payment(pg_temp.p('r1'), 'Again', false) $$, 'ES409', null,
  'a reversal row cannot be reversed');
select is((pg_temp.row('m1')).status::text, 'paid', 'the original stays paid');

insert into ids select 'r2', public.admin_reverse_payment(pg_temp.p('m2'), 'Marked by mistake', true);
select ok((select count(*) = 1 and bool_and(status = 'pending_approval' and amount = 10000 and currency = 'LKR'
    and created_by = '74000000-0000-0000-0000-00000000000a')
  from public.payments where assignment_id = (pg_temp.row('m2')).assignment_id and kind = 'assignment' and status <> 'paid'),
  're-open adds one pending approval payment for the agreed amount');

-- Re-open refused while an unpaid payment exists (seeded as the table owner)
-- (12D: the sum guard would refuse this impossible row, so it is paused for the seed only.)
reset role;
set local session_replication_role = replica;
insert into public.payments (assignment_id, project_id, editor_id, amount, currency)
select assignment_id, project_id, editor_id, amount, currency from public.payments where id = (select id from ids where kind = 'm7');
set local session_replication_role = origin;
select pg_temp.as_user('74000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_reverse_payment(pg_temp.p('m7'), 'Why', true) $$, 'ES409', null,
  're-open while an unpaid payment exists is refused');
select is((select count(*)::int from public.payments where reverses_payment_id = pg_temp.p('m7')), 0,
  'nothing is inserted when re-open is refused');

-- Re-open refused once the assignment has ended (reassigned)
select public.admin_reassign((select assignment_id from public.payments where id = pg_temp.p('m8')));
select is((select a.status::text from public.assignments a join public.payments p on p.assignment_id = a.id
  where p.id = pg_temp.p('m8')), 'reassigned', 'the paid assignment is reassigned');
select throws_ok($$ select public.admin_reverse_payment(pg_temp.p('m8'), 'Why', true) $$, 'ES409', null,
  're-open on a reassigned assignment is refused');
select is((select count(*)::int from public.payments where reverses_payment_id = pg_temp.p('m8')), 0,
  'nothing is inserted when re-open on an ended assignment is refused');

-- Notes
select ok(public.admin_add_payment_note(pg_temp.p('m1'), '  Called the bank  ') is not null, 'note added');
select ok((select count(*) = 1 and bool_and(note = 'Called the bank' and author_id = '74000000-0000-0000-0000-00000000000a')
  from public.payment_notes where payment_id = pg_temp.p('m1')), 'note stored trimmed with its author');
select public.admin_add_payment_note(pg_temp.p('m1'), 'Second');
select is((select count(*)::int from public.payment_notes where payment_id = pg_temp.p('m1')), 2, 'notes append');
select throws_ok($$ select public.admin_add_payment_note(pg_temp.p('m1'), '  ') $$, 'ES422', null, 'blank note');
select throws_ok($$ select public.admin_add_payment_note(pg_temp.p('m1'), repeat('n', 4001)) $$, 'ES422', null,
  'note of 4001 characters');
select throws_ok($$ select public.admin_add_payment_note(gen_random_uuid(), 'x') $$, 'ES422', 'Payment not found.',
  'note on an unknown payment');
select is((select count(*)::int from public.activity_logs where action = 'payment_note.added'), 2,
  'one payment_note.added audit row per note');
select is((select count(*)::int from public.activity_logs where action = 'payment.reversed'), 2,
  'one payment.reversed audit row per reversal');
select is((select count(*)::int from public.activity_logs where action = 'payment.paid'), 4,
  'one payment.paid audit row per payment marked paid');
select pg_temp.as_user('74000000-0000-0000-0000-000000000001');
select is((select count(*)::int from public.payment_notes), 0, 'the editor cannot read notes');
select is((select count(*)::int from public.payments), 0, 'the editor cannot read payment rows (actor ids)');
select ok((select count(*) > 0 from public.editor_list_payments()), 'the editor lists own payments');

reset role;
select * from finish();
rollback;
