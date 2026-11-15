-- Phase 9: payments schema, constraints and guards (as the table owner). Review Focus 3, 4.
begin;

create extension if not exists pgtap with schema extensions;

select plan(52);

-- ---------------------------------------------------------------------------
-- Fixtures (as postgres)
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('70000000-0000-0000-0000-00000000000a', 'p9s-admin@test.local', '{}', '{}'),
  ('70000000-0000-0000-0000-000000000001', 'p9s-editor-a@test.local', '{}', '{}'),
  ('70000000-0000-0000-0000-000000000002', 'p9s-editor-b@test.local', '{}', '{}');
select private.grant_admin_by_email('p9s-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('70000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000002');

insert into public.projects (id, title, brief_type, status, first_opened_at, proposed_amount, proposed_currency) values
  ('70000000-0000-0000-0000-0000000000f1', 'P1', 'fully_instructed', 'assigned', now(), null, 'LKR'),
  ('70000000-0000-0000-0000-0000000000f2', 'P2', 'fully_instructed', 'assigned', now(), null, 'LKR'),
  ('70000000-0000-0000-0000-0000000000f3', 'P3', 'fully_instructed', 'open', now(), null, 'LKR'),
  ('70000000-0000-0000-0000-0000000000f4', 'P4', 'fully_instructed', 'assigned', now(), null, 'LKR');
insert into public.assignments (id, project_id, editor_id, status, proposed_amount, agreed_amount, agreed_currency,
  confirmed_by, confirmed_at) values
  ('70000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-0000000000f1',
   '70000000-0000-0000-0000-000000000001', 'confirmed', 10000, 10000, 'LKR', '70000000-0000-0000-0000-00000000000a', now()),
  ('70000000-0000-0000-0000-0000000000a2', '70000000-0000-0000-0000-0000000000f2',
   '70000000-0000-0000-0000-000000000002', 'confirmed', 5000, 5000, 'LKR', '70000000-0000-0000-0000-00000000000a', now()),
  ('70000000-0000-0000-0000-0000000000a3', '70000000-0000-0000-0000-0000000000f3',
   '70000000-0000-0000-0000-000000000001', 'accepted', 10000, 10000, 'LKR', null, null),
  ('70000000-0000-0000-0000-0000000000a4', '70000000-0000-0000-0000-0000000000f4',
   '70000000-0000-0000-0000-000000000001', 'confirmed', 10000, 10000, 'LKR', '70000000-0000-0000-0000-00000000000a', now());

-- ---------------------------------------------------------------------------
-- Catalogue
-- ---------------------------------------------------------------------------
select enum_has_labels('public', 'payment_status',
  array['not_due', 'pending_approval', 'approved', 'processing', 'paid', 'on_hold'], 'payment_status labels');
select enum_has_labels('public', 'payment_kind', array['assignment', 'reversal'], 'payment_kind labels');
select columns_are('public', 'payments', array['id', 'assignment_id', 'project_id', 'editor_id', 'kind', 'amount',
  'currency', 'status', 'held_from_status', 'on_hold_reason', 'due_date', 'transfer_date', 'transaction_reference',
  'reverses_payment_id', 'reversal_reason', 'approved_by', 'approved_at', 'marked_paid_by', 'marked_paid_at',
  'created_by', 'created_at', 'updated_at', 'milestone_seq', 'payable_reason', 'payable_at', 'split_from_payment_id',
  'amount_before_split', 'waiting_on_client'], 'payments columns (12D milestone columns included)');
select columns_are('public', 'payment_notes', array['id', 'payment_id', 'author_id', 'note', 'created_at'],
  'payment_notes columns');
select set_has($$ select conname::text from pg_constraint where conrelid = 'public.payments'::regclass $$,
  $$ values ('payments_amount_chk'), ('payments_hold_chk'), ('payments_approved_chk'), ('payments_paid_chk'),
            ('payments_reversal_chk') $$, 'payments constraints by name');
select set_has($$ select indexname::text from pg_indexes where schemaname = 'public'
                  and tablename in ('payments', 'payment_notes') $$,
  $$ values ('payments_open_key'), ('payments_reverses_key'), ('payments_editor_idx'), ('payments_project_idx'),
            ('payments_status_idx'), ('payments_approved_by_idx'), ('payments_marked_paid_by_idx'),
            ('payments_created_by_idx'), ('payment_notes_payment_idx'), ('payment_notes_author_idx') $$,
  'payments and payment_notes indexes by name');

-- ---------------------------------------------------------------------------
-- check_payment_row (insert guard)
-- ---------------------------------------------------------------------------
select throws_ok($$ insert into public.payments (assignment_id, project_id, editor_id, amount, currency)
  values ('70000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-0000000000f1',
          '70000000-0000-0000-0000-000000000001', 10000.01, 'LKR') $$, 'ES409', null, 'amount cannot exceed the agreed amount (12D)');
select throws_ok($$ insert into public.payments (assignment_id, project_id, editor_id, amount, currency)
  values ('70000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-0000000000f1',
          '70000000-0000-0000-0000-000000000001', 10000, 'USD') $$, 'ES409', null, 'currency must equal the agreed currency');
select throws_ok($$ insert into public.payments (assignment_id, project_id, editor_id, amount, currency)
  values ('70000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-0000000000f2',
          '70000000-0000-0000-0000-000000000001', 10000, 'LKR') $$, 'ES409', null, 'project must be the assignment''s');
select throws_ok($$ insert into public.payments (assignment_id, project_id, editor_id, amount, currency)
  values ('70000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-0000000000f1',
          '70000000-0000-0000-0000-000000000002', 10000, 'LKR') $$, 'ES409', null, 'editor must be the assignment''s');
select throws_ok($$ insert into public.payments (assignment_id, project_id, editor_id, amount, currency)
  values ('70000000-0000-0000-0000-0000000000a3', '70000000-0000-0000-0000-0000000000f3',
          '70000000-0000-0000-0000-000000000001', 10000, 'LKR') $$, 'ES409', null, 'an unconfirmed assignment is refused');
select lives_ok($$ insert into public.payments (id, assignment_id, project_id, editor_id, amount, currency)
  values ('70000000-0000-0000-0000-0000000000c1', '70000000-0000-0000-0000-0000000000a1',
          '70000000-0000-0000-0000-0000000000f1', '70000000-0000-0000-0000-000000000001', 10000, 'LKR') $$,
  'a valid assignment payment inserts');
select is((select status::text || '/' || kind::text from public.payments where id = '70000000-0000-0000-0000-0000000000c1'),
  'not_due/assignment', 'defaults are not_due and assignment');
select throws_ok($$ insert into public.payments (assignment_id, project_id, editor_id, amount, currency)
  values ('70000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-0000000000f1',
          '70000000-0000-0000-0000-000000000001', 10000, 'LKR') $$, 'ES409', null,
  'a second payment beyond the agreed amount is refused (12D sum guard)');

-- ---------------------------------------------------------------------------
-- CHECK constraints (insert guard off so only the constraints decide)
-- ---------------------------------------------------------------------------
alter table public.payments disable trigger payments_check_row;
create function pg_temp.ins(p_kind text, p_amount numeric, p_status text, p_extra jsonb default '{}')
returns void language plpgsql as $$
begin
  insert into public.payments (assignment_id, project_id, editor_id, kind, amount, currency, status, held_from_status,
    on_hold_reason, approved_at, marked_paid_at, transaction_reference, transfer_date, reverses_payment_id,
    reversal_reason)
  values ('70000000-0000-0000-0000-0000000000a2', '70000000-0000-0000-0000-0000000000f2',
    '70000000-0000-0000-0000-000000000002', p_kind::public.payment_kind, p_amount, 'LKR',
    p_status::public.payment_status, (p_extra ->> 'held')::public.payment_status, p_extra ->> 'reason',
    (p_extra ->> 'approved_at')::timestamptz, (p_extra ->> 'paid_at')::timestamptz, p_extra ->> 'ref',
    (p_extra ->> 'date')::date, (p_extra ->> 'reverses')::uuid, p_extra ->> 'rreason');
end;
$$;
select throws_ok($$ select pg_temp.ins('assignment', 0, 'not_due') $$, '23514', null, 'assignment amount must be > 0');
select throws_ok($$ select pg_temp.ins('reversal', 5, 'paid', '{"paid_at": "2026-11-14", "reverses":
  "70000000-0000-0000-0000-0000000000c1", "rreason": "x"}') $$, '23514', null, 'reversal amount must be < 0');
select throws_ok($$ select pg_temp.ins('assignment', 5000, 'on_hold', '{"held": "not_due"}') $$, '23514', null,
  'on_hold needs a reason');
select throws_ok($$ select pg_temp.ins('assignment', 5000, 'on_hold', '{"reason": "x"}') $$, '23514', null,
  'on_hold needs held_from_status');
select throws_ok($$ select pg_temp.ins('assignment', 5000, 'on_hold', '{"reason": "x", "held": "paid"}') $$, '23514',
  null, 'held_from_status cannot be paid');
select throws_ok($$ select pg_temp.ins('assignment', 5000, 'not_due', '{"reason": "x", "held": "not_due"}') $$, '23514',
  null, 'a reason without on_hold is refused');
select throws_ok($$ select pg_temp.ins('assignment', 5000, 'approved') $$, '23514', null, 'approved needs approved_at');
select throws_ok($$ select pg_temp.ins('assignment', 5000, 'paid', '{"approved_at": "2026-11-14", "paid_at":
  "2026-11-14", "date": "2026-11-14"}') $$, '23514', null, 'a paid assignment row needs a reference');
select throws_ok($$ select pg_temp.ins('assignment', 5000, 'paid', '{"approved_at": "2026-11-14", "paid_at":
  "2026-11-14", "ref": "R"}') $$, '23514', null, 'a paid assignment row needs a transfer date');
select throws_ok($$ select pg_temp.ins('reversal', -5000, 'not_due', '{"reverses":
  "70000000-0000-0000-0000-0000000000c1", "rreason": "x"}') $$, '23514', null, 'a reversal must be paid');
select throws_ok($$ select pg_temp.ins('reversal', -5000, 'paid', '{"paid_at": "2026-11-14"}') $$, '23514', null,
  'a reversal needs the reversed id and a reason');
alter table public.payments enable trigger payments_check_row;

-- ---------------------------------------------------------------------------
-- Reversal rows
-- ---------------------------------------------------------------------------
insert into public.payments (id, assignment_id, project_id, editor_id, amount, currency, status, approved_by, approved_at,
  marked_paid_by, marked_paid_at, transaction_reference, transfer_date, created_by)
values ('70000000-0000-0000-0000-0000000000c2', '70000000-0000-0000-0000-0000000000a2',
  '70000000-0000-0000-0000-0000000000f2', '70000000-0000-0000-0000-000000000002', 5000, 'LKR', 'paid',
  '70000000-0000-0000-0000-00000000000a', now(), '70000000-0000-0000-0000-00000000000a', now(), 'REF', current_date,
  '70000000-0000-0000-0000-00000000000a');
create function pg_temp.rev(p_of uuid, p_amount numeric, p_currency text) returns void language sql as $$
  insert into public.payments (assignment_id, project_id, editor_id, kind, amount, currency, status, marked_paid_at,
    reverses_payment_id, reversal_reason)
  select assignment_id, project_id, editor_id, 'reversal', p_amount, p_currency, 'paid', now(), id, 'Mistake'
  from public.payments where id = p_of $$;
select throws_ok($$ select pg_temp.rev('70000000-0000-0000-0000-0000000000c1', -10000, 'LKR') $$, 'ES409', null,
  'reversing an unpaid row is refused');
select throws_ok($$ select pg_temp.rev('70000000-0000-0000-0000-0000000000c2', -4000, 'LKR') $$, 'ES409', null,
  'a partial reversal is refused');
select throws_ok($$ select pg_temp.rev('70000000-0000-0000-0000-0000000000c2', -5000, 'USD') $$, 'ES409', null,
  'a reversal in another currency is refused');
select lives_ok($$ select pg_temp.rev('70000000-0000-0000-0000-0000000000c2', -5000, 'LKR') $$, 'a full reversal inserts');
select throws_ok($$ select pg_temp.rev('70000000-0000-0000-0000-0000000000c2', -5000, 'LKR') $$, '23505', null,
  'a second reversal of the same row is refused');
select throws_ok($$ select pg_temp.rev((select id from public.payments where kind = 'reversal'), 5000, 'LKR') $$,
  'ES409', null, 'reversing a reversal is refused');

-- ---------------------------------------------------------------------------
-- Status matrix as the table owner (Review Focus 3). Each try runs in a rolled-back subtransaction.
-- ---------------------------------------------------------------------------
create function pg_temp.try_status(p_from public.payment_status, p_to public.payment_status,
  p_held public.payment_status default null)
returns text language plpgsql as $$
declare
  v_id uuid := gen_random_uuid();
begin
  begin
    insert into public.payments (id, assignment_id, project_id, editor_id, amount, currency, status, held_from_status,
      on_hold_reason, approved_at, marked_paid_at, transaction_reference, transfer_date)
    values (v_id, '70000000-0000-0000-0000-0000000000a4', '70000000-0000-0000-0000-0000000000f4',
      '70000000-0000-0000-0000-000000000001', 10000, 'LKR', p_from,
      case when p_from = 'on_hold' then coalesce(p_held, 'not_due') end,
      case when p_from = 'on_hold' then 'Seed' end, now(),
      case when p_from = 'paid' then now() end, case when p_from = 'paid' then 'REF' end,
      case when p_from = 'paid' then current_date end);
    if p_from <> p_to then
      update public.payments set
        status = p_to,
        held_from_status = case when p_to = 'on_hold' then p_from end,
        on_hold_reason = case when p_to = 'on_hold' then 'Hold' end,
        marked_paid_at = case when p_to = 'paid' then coalesce(marked_paid_at, now()) else marked_paid_at end,
        transaction_reference = case when p_to = 'paid' then coalesce(transaction_reference, 'REF')
                                     else transaction_reference end,
        transfer_date = case when p_to = 'paid' then coalesce(transfer_date, current_date) else transfer_date end
      where id = v_id;
    end if;
    raise exception 'rollback' using errcode = 'EST00';
  exception when others then
    return case when sqlstate = 'EST00' then 'ok' else sqlstate end;
  end;
end;
$$;

create temp table matrix as
  select f::text as f, t::text as t,
    pg_temp.try_status(f, t, case when f = 'on_hold' and t not in ('on_hold', 'paid') then t end) as r
  from unnest(enum_range(null::public.payment_status)) f cross join unnest(enum_range(null::public.payment_status)) t;

select is((select count(*)::int from matrix), 36, 'all 36 pairs tried');
select set_eq($$ select f || '>' || t from matrix where r = 'ok' and f <> t $$,
  $$ values ('not_due>pending_approval'), ('not_due>on_hold'), ('pending_approval>approved'),
            ('pending_approval>on_hold'), ('approved>processing'), ('approved>paid'), ('approved>on_hold'),
            ('processing>paid'), ('processing>on_hold'), ('on_hold>not_due'), ('on_hold>pending_approval'),
            ('on_hold>approved'), ('on_hold>processing') $$,
  'only the spec §7 transitions succeed (on_hold returns to held_from_status)');
select is((select count(*)::int from matrix where r not in ('ok', 'ES409')), 0, 'every refusal is ES409');
select ok((select bool_and(pg_temp.try_status('on_hold', t, case when t = 'not_due' then 'approved' else 'not_due' end::public.payment_status)
    = 'ES409')
  from unnest(array['not_due', 'pending_approval', 'approved', 'processing']::public.payment_status[]) t),
  'on_hold cannot move to a status other than held_from_status');

-- ---------------------------------------------------------------------------
-- Paid rows, immutable columns, deletes (Review Focus 4)
-- ---------------------------------------------------------------------------
select throws_ok($$ update public.payments set transaction_reference = 'X' where id = '70000000-0000-0000-0000-0000000000c2' $$,
  'ES409', null, 'a paid row''s reference cannot change');
select throws_ok($$ update public.payments set transfer_date = current_date - 1
  where id = '70000000-0000-0000-0000-0000000000c2' $$, 'ES409', null, 'a paid row''s transfer date cannot change');
select throws_ok($$ update public.payments set due_date = current_date where id = '70000000-0000-0000-0000-0000000000c2' $$,
  'ES409', null, 'a paid row''s due date cannot change');
select throws_ok($$ update public.payments set marked_paid_by = null, due_date = current_date
  where id = '70000000-0000-0000-0000-0000000000c2' $$, 'ES409', null,
  'clearing an actor together with another column is refused');
select throws_ok($$ update public.payments set approved_by = '70000000-0000-0000-0000-000000000001'
  where id = '70000000-0000-0000-0000-0000000000c2' $$, 'ES409', null, 'changing an actor to another user is refused');
select lives_ok($$ update public.payments set approved_by = null where id = '70000000-0000-0000-0000-0000000000c2' $$,
  'clearing approved_by alone on a paid row succeeds');
select lives_ok($$ update public.payments set marked_paid_by = null, created_by = null
  where id = '70000000-0000-0000-0000-0000000000c2' $$, 'clearing marked_paid_by and created_by succeeds');

create function pg_temp.try_delete(p_status public.payment_status) returns text language plpgsql as $$
declare
  v_id uuid := gen_random_uuid();
begin
  begin
    insert into public.payments (id, assignment_id, project_id, editor_id, amount, currency, status, held_from_status,
      on_hold_reason, approved_at, marked_paid_at, transaction_reference, transfer_date)
    values (v_id, '70000000-0000-0000-0000-0000000000a4', '70000000-0000-0000-0000-0000000000f4',
      '70000000-0000-0000-0000-000000000001', 10000, 'LKR', p_status,
      case when p_status = 'on_hold' then 'not_due'::public.payment_status end,
      case when p_status = 'on_hold' then 'Seed' end, now(), now(), 'REF', current_date);
    delete from public.payments where id = v_id;
    raise exception 'rollback' using errcode = 'EST00';
  exception when others then
    return case when sqlstate = 'EST00' then 'ok' else sqlstate end;
  end;
end;
$$;
select ok((select bool_and(pg_temp.try_delete(s) = 'ES409') from unnest(enum_range(null::public.payment_status)) s),
  'delete is refused in every status');

select throws_ok($$ update public.payments set amount = 9000 where id = '70000000-0000-0000-0000-0000000000c1' $$,
  'ES409', null, 'amount cannot change');
select throws_ok($$ update public.payments set currency = 'USD' where id = '70000000-0000-0000-0000-0000000000c1' $$,
  'ES409', null, 'currency cannot change');
select throws_ok($$ update public.payments set assignment_id = '70000000-0000-0000-0000-0000000000a4'
  where id = '70000000-0000-0000-0000-0000000000c1' $$, 'ES409', null, 'assignment cannot change');
select throws_ok($$ update public.payments set kind = 'reversal' where id = '70000000-0000-0000-0000-0000000000c1' $$,
  'ES409', null, 'kind cannot change');
select lives_ok($$ update public.payments set due_date = current_date where id = '70000000-0000-0000-0000-0000000000c1' $$,
  'an unpaid row''s due date can change');

-- ---------------------------------------------------------------------------
-- payment_notes append-only; referenced assignment cannot be deleted
-- ---------------------------------------------------------------------------
insert into public.payment_notes (id, payment_id, author_id, note) values
  ('70000000-0000-0000-0000-0000000000e1', '70000000-0000-0000-0000-0000000000c1',
   '70000000-0000-0000-0000-00000000000a', 'Internal');
select throws_ok($$ update public.payment_notes set note = 'Edited' where id = '70000000-0000-0000-0000-0000000000e1' $$,
  'ES409', null, 'a payment note cannot be edited');
select throws_ok($$ delete from public.payment_notes where id = '70000000-0000-0000-0000-0000000000e1' $$,
  'ES409', null, 'a payment note cannot be deleted');
select lives_ok($$ update public.payment_notes set author_id = null where id = '70000000-0000-0000-0000-0000000000e1' $$,
  'clearing the note author succeeds');
select throws_ok($$ delete from public.assignments where id = '70000000-0000-0000-0000-0000000000a1' $$, '23503', null,
  'an assignment with payments cannot be deleted');

select * from finish();
rollback;
