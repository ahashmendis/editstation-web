-- Phase 9: admin_set_payment_status, admin_release_payment_hold, admin_set_payment_due_date.
-- Review Focus 5, 8. Role refusals for every function are in 076.
begin;

create extension if not exists pgtap with schema extensions;

select plan(38);

create function pg_temp.as_user(p_uid uuid, p_aal text default 'aal1')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;
grant execute on function pg_temp.as_user(uuid, text) to authenticated;

create function pg_temp.assignment(p_title text, p_editor uuid)
returns uuid language plpgsql as $$
declare
  v_project uuid;
  v_id uuid;
begin
  perform pg_temp.as_user('73000000-0000-0000-0000-00000000000a', 'aal2');
  v_project := public.admin_create_project(jsonb_build_object('title', p_title, 'brief_type', 'fully_instructed',
    'deadline', '2026-12-31', 'brief', jsonb_build_object('instructions', 'Cut it'),
    'deliverables', jsonb_build_array(jsonb_build_object('name', 'Main'))));
  perform public.admin_set_project_status(v_project, 'open');
  perform public.admin_agree_terms(v_project, 1);
  v_id := public.admin_make_offer(v_project, p_editor, 10000, 'LKR');
  perform pg_temp.as_user(p_editor);
  perform public.editor_respond_offer(v_id, 'accept');
  perform pg_temp.as_user('73000000-0000-0000-0000-00000000000a', 'aal2');
  perform public.admin_confirm_assignment(v_id);
  reset role;
  return v_id;
end;
$$;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('73000000-0000-0000-0000-00000000000a', 'p9a-admin@test.local', '{}', '{}'),
  ('73000000-0000-0000-0000-000000000001', 'p9a-editor-a@test.local', '{}', '{}');
select private.grant_admin_by_email('p9a-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active' where user_id = '73000000-0000-0000-0000-000000000001';

create temp table ids (kind text primary key, id uuid not null);
grant select on ids to authenticated;
insert into ids select 'a1', pg_temp.assignment('One', '73000000-0000-0000-0000-000000000001');
insert into ids select 'a2', pg_temp.assignment('Two', '73000000-0000-0000-0000-000000000001');
insert into ids select 'p1', id from public.payments where assignment_id = (select id from ids where kind = 'a1');
insert into ids select 'p2', id from public.payments where assignment_id = (select id from ids where kind = 'a2');
create function pg_temp.p(p_kind text) returns uuid language sql as $$ select id from ids where kind = p_kind $$;
grant execute on function pg_temp.p(text) to authenticated;
create function pg_temp.row(p_kind text) returns public.payments language sql as $$
  select * from public.payments where id = (select id from ids where kind = p_kind) $$;
grant execute on function pg_temp.row(text) to authenticated;

select pg_temp.as_user('73000000-0000-0000-0000-00000000000a', 'aal2');

-- Happy path
select lives_ok($$ select public.admin_set_payment_status(pg_temp.p('p1'), 'pending_approval') $$, 'not_due -> pending');
select is((pg_temp.row('p1')).status::text, 'pending_approval', 'status is pending approval');
select lives_ok($$ select public.admin_set_payment_status(pg_temp.p('p1'), 'approved') $$, 'pending -> approved');
select ok((select status = 'approved' and approved_by = '73000000-0000-0000-0000-00000000000a' and approved_at is not null
  from pg_temp.row('p1')), 'approval records the approver and time');
select lives_ok($$ select public.admin_set_payment_status(pg_temp.p('p1'), 'processing') $$, 'approved -> processing');
select lives_ok($$ select public.admin_set_payment_status(pg_temp.p('p1'), 'on_hold', '  Bank details checked  ') $$,
  'processing -> on_hold with a reason');
select ok((select status = 'on_hold' and held_from_status = 'processing' and on_hold_reason = 'Bank details checked'
  from pg_temp.row('p1')), 'hold stores the trimmed reason and the status to return to');
select throws_ok($$ select public.admin_set_payment_status(pg_temp.p('p1'), 'processing') $$, 'ES409',
  'This payment cannot move from on hold to processing.', 'leaving a hold needs release');
select lives_ok($$ select public.admin_release_payment_hold(pg_temp.p('p1')) $$, 'release');
select ok((select status = 'processing' and held_from_status is null and on_hold_reason is null from pg_temp.row('p1')),
  'release returns to processing and clears the reason');

-- Hold and release from each other unpaid state
select public.admin_set_payment_status(pg_temp.p('p2'), 'on_hold', 'Waiting');
select public.admin_release_payment_hold(pg_temp.p('p2'));
select is((pg_temp.row('p2')).status::text, 'not_due', 'hold/release from not_due');
select public.admin_set_payment_status(pg_temp.p('p2'), 'pending_approval');
select public.admin_set_payment_status(pg_temp.p('p2'), 'on_hold', 'Waiting');
select public.admin_release_payment_hold(pg_temp.p('p2'));
select is((pg_temp.row('p2')).status::text, 'pending_approval', 'hold/release from pending approval');
select public.admin_set_payment_status(pg_temp.p('p2'), 'approved');
select public.admin_set_payment_status(pg_temp.p('p2'), 'on_hold', 'Waiting');
select public.admin_release_payment_hold(pg_temp.p('p2'));
select is((pg_temp.row('p2')).status::text, 'approved', 'hold/release from approved');
select throws_ok($$ select public.admin_release_payment_hold(pg_temp.p('p2')) $$, 'ES409', null,
  'release of a payment that is not on hold is refused');
select throws_ok($$ select public.admin_set_payment_status(pg_temp.p('p2'), 'pending_approval') $$, 'ES409',
  'This payment cannot move from approved to pending approval.', 'moving back is refused with a readable message');
select throws_ok($$ select public.admin_set_payment_status(pg_temp.p('p2'), 'approved') $$, 'ES409', null,
  'approving twice is refused');

-- Review Focus 5
select throws_ok($$ select public.admin_set_payment_status(pg_temp.p('p2'), null) $$, 'ES422', null, 'null status');
select throws_ok($$ select public.admin_set_payment_status(pg_temp.p('p2'), 'PAID') $$, 'ES422', null, 'PAID');
select throws_ok($$ select public.admin_set_payment_status(pg_temp.p('p2'), 'paid') $$, 'ES422', 'Use mark as paid.',
  'paid is refused with a pointer to mark as paid');
select throws_ok($$ select public.admin_set_payment_status(pg_temp.p('p2'), 'not_due') $$, 'ES422', null, 'not_due');
select throws_ok($$ select public.admin_set_payment_status(pg_temp.p('p2'), 'bogus') $$, 'ES422', null, 'bogus');
select throws_ok($$ select public.admin_set_payment_status(pg_temp.p('p2'), 'on_hold') $$, 'ES422',
  'Please give a reason for the hold.', 'hold without a reason');
select throws_ok($$ select public.admin_set_payment_status(pg_temp.p('p2'), 'on_hold', E'  \t ') $$, 'ES422',
  'Please give a reason for the hold.', 'hold with a blank reason');
select throws_ok($$ select public.admin_set_payment_status(pg_temp.p('p2'), 'on_hold', repeat('x', 501)) $$, 'ES422',
  null, 'hold with a 501-character reason');
select is((pg_temp.row('p2')).status::text, 'approved', 'refusals change nothing');

-- Due dates
select lives_ok($$ select public.admin_set_payment_due_date(pg_temp.p('p2'), '2026-12-01') $$, 'set a due date');
select is((pg_temp.row('p2')).due_date, '2026-12-01'::date, 'due date stored');
select public.admin_set_payment_due_date(pg_temp.p('p2'), '2026-10-01');
select is((pg_temp.row('p2')).due_date, '2026-10-01'::date, 'due date changed (back-dating allowed)');
select public.admin_set_payment_due_date(pg_temp.p('p2'), null);
select is((pg_temp.row('p2')).due_date, null::date, 'due date cleared');
select public.admin_set_payment_status(pg_temp.p('p2'), 'on_hold', 'Waiting');
select lives_ok($$ select public.admin_set_payment_due_date(pg_temp.p('p2'), '2026-12-02') $$, 'due date on hold');

-- Paid rows refuse every change
select public.admin_mark_payment_paid(pg_temp.p('p1'), 'R1', (now() at time zone 'Asia/Colombo')::date);
select throws_ok($$ select public.admin_set_payment_due_date(pg_temp.p('p1'), '2026-12-01') $$, 'ES409',
  'This payment has been paid and cannot be changed.', 'due date on a paid row');
select throws_ok($$ select public.admin_set_payment_status(pg_temp.p('p1'), 'on_hold', 'Late') $$, 'ES409',
  'This payment has been paid and cannot be changed.', 'hold on a paid row');

-- Review Focus 8: unknown payment id
select throws_ok($$ select public.admin_set_payment_status(gen_random_uuid(), 'approved') $$, 'ES422', 'Payment not found.',
  'set status: unknown id');
select throws_ok($$ select public.admin_release_payment_hold(gen_random_uuid()) $$, 'ES422', 'Payment not found.',
  'release: unknown id');
select throws_ok($$ select public.admin_mark_payment_paid(gen_random_uuid(), 'R', current_date) $$, 'ES422',
  'Payment not found.', 'mark paid: unknown id');
select throws_ok($$ select public.admin_set_payment_due_date(gen_random_uuid(), null) $$, 'ES422', 'Payment not found.',
  'due date: unknown id');
select throws_ok($$ select public.admin_reverse_payment(gen_random_uuid(), 'Why', false) $$, 'ES422', 'Payment not found.',
  'reverse: unknown id');
select throws_ok($$ select public.admin_add_payment_note(gen_random_uuid(), 'Note') $$, 'ES422', 'Payment not found.',
  'note: unknown id');

reset role;
select * from finish();
rollback;
