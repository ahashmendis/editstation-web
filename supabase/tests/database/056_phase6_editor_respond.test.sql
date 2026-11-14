-- Phase 6: editor_respond_offer (accept / decline / counter, own offers only, from offered only).
-- Review Focus 3, 6 (no existence leak), 7 (suspended editor), 9, 11.
begin;

create extension if not exists pgtap with schema extensions;

select plan(40);

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

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('56000000-0000-0000-0000-00000000000a', 'p6e-admin@test.local', '{}', '{}'),
  ('56000000-0000-0000-0000-000000000001', 'p6e-editor-a@test.local', '{}', '{}'),
  ('56000000-0000-0000-0000-000000000002', 'p6e-editor-b@test.local', '{}', '{}'),
  ('56000000-0000-0000-0000-000000000003', 'p6e-applicant@test.local', '{}', '{}');
select private.grant_admin_by_email('p6e-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('56000000-0000-0000-0000-000000000001', '56000000-0000-0000-0000-000000000002');
insert into public.projects (id, title, brief_type, status, first_opened_at) values
  ('56000000-0000-0000-0000-0000000000f1', 'Main', 'fully_instructed', 'open', now());

create temp table ids (kind text primary key, id uuid not null);
grant select, insert on ids to authenticated, anon;
create function pg_temp.a(p_kind text) returns uuid language sql as $$ select id from ids where kind = p_kind $$;
grant execute on function pg_temp.a(text) to authenticated, anon;

-- A fresh offer to A (as admin), stored under p_kind.
create function pg_temp.offer(p_kind text) returns void language plpgsql as $$
begin
  perform pg_temp.as_user('56000000-0000-0000-0000-00000000000a', 'aal2');
  insert into ids select p_kind, public.admin_make_offer('56000000-0000-0000-0000-0000000000f1',
    '56000000-0000-0000-0000-000000000001', 12000, 'LKR');
  reset role;
end;
$$;
create function pg_temp.withdraw(p_kind text) returns void language plpgsql as $$
begin
  perform pg_temp.as_user('56000000-0000-0000-0000-00000000000a', 'aal2');
  perform public.admin_withdraw_offer(pg_temp.a(p_kind));
  reset role;
end;
$$;

-- ---------------------------------------------------------------------------
-- Accept
-- ---------------------------------------------------------------------------
select pg_temp.offer('o1');
select pg_temp.as_user('56000000-0000-0000-0000-000000000001');
select lives_ok($$ select public.editor_respond_offer(pg_temp.a('o1'), 'accept', 1, 'USD', 'Happy to') $$,
  'editor A accepts their offer (amount and currency ignored)');
select ok((select status = 'accepted' and agreed_amount = 12000 and agreed_currency = 'LKR'
  from public.assignments where id = pg_temp.a('o1')), 'accepting sets the agreed amount to the offer');
select ok((select count(*) = 1 and bool_and(amount = 12000 and currency = 'LKR' and message = 'Happy to'
    and created_by = '56000000-0000-0000-0000-000000000001')
  from public.negotiation_offers where assignment_id = pg_temp.a('o1') and from_role = 'editor' and action = 'accept'),
  'one editor accept row with the agreed amount');
select throws_ok($$ select public.editor_respond_offer(pg_temp.a('o1'), 'decline') $$, 'ES409', null,
  'an accepted offer cannot be answered again');
reset role;
select ok((select count(*) = 1 and bool_and(actor_id = '56000000-0000-0000-0000-000000000001'
    and not (details::text like '%12000%'))
  from public.activity_logs where action = 'assignment.accepted' and entity_id = pg_temp.a('o1')::text),
  'the acceptance is audited with the editor as actor and no amount');
select pg_temp.withdraw('o1');

-- ---------------------------------------------------------------------------
-- Decline
-- ---------------------------------------------------------------------------
select pg_temp.offer('o2');
select pg_temp.as_user('56000000-0000-0000-0000-000000000001');
select lives_ok($$ select public.editor_respond_offer(pg_temp.a('o2'), 'decline', null, null, 'Busy that week') $$,
  'editor A declines an offer');
select ok((select status = 'declined' and closed_at is not null and agreed_amount is null
  from public.assignments where id = pg_temp.a('o2')), 'declining closes the offer');
select ok(exists (select 1 from public.negotiation_offers where assignment_id = pg_temp.a('o2')
  and from_role = 'editor' and action = 'decline' and amount is null and message = 'Busy that week'),
  'an editor decline row without an amount');
reset role;

-- ---------------------------------------------------------------------------
-- Counter, then the admin accepts (full round trip)
-- ---------------------------------------------------------------------------
select pg_temp.offer('o3');
select pg_temp.as_user('56000000-0000-0000-0000-000000000001');
select lives_ok($$ select public.editor_respond_offer(pg_temp.a('o3'), 'counter', 15000, null, 'Two cameras') $$,
  'editor A counters');
select ok((select status = 'counteroffer_pending' and proposed_amount = 15000 and agreed_amount is null
  from public.assignments where id = pg_temp.a('o3')), 'a counter sets counteroffer_pending with the new amount');
select ok(exists (select 1 from public.negotiation_offers where assignment_id = pg_temp.a('o3')
  and from_role = 'editor' and action = 'counter' and amount = 15000 and currency = 'LKR'),
  'an editor counter row with the amount');
select throws_ok($$ select public.editor_respond_offer(pg_temp.a('o3'), 'accept') $$, 'ES409', null,
  'an editor cannot answer their own counteroffer');
reset role;
select pg_temp.as_user('56000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_respond_counter(pg_temp.a('o3'), 'accept');
reset role;
select ok((select status = 'accepted' and agreed_amount = 15000 from public.assignments where id = pg_temp.a('o3')),
  'the admin accepts the counter: agreed at 15000');
select pg_temp.withdraw('o3');

-- ---------------------------------------------------------------------------
-- Invalid input on a live offer (Review Focus 3, 9)
-- ---------------------------------------------------------------------------
select pg_temp.offer('o4');
select pg_temp.as_user('56000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_respond_offer(pg_temp.a('o4'), 'counter', 12000) $$, 'ES422', null,
  'a counter equal to the offer is refused (accept instead)');
select throws_ok($$ select public.editor_respond_offer(pg_temp.a('o4'), 'counter', 15000, 'USD') $$, 'ES422', null,
  'a counter in another currency is refused');
select throws_ok($$ select public.editor_respond_offer(pg_temp.a('o4'), 'counter', 0) $$, 'ES422', null,
  'a zero counter is refused');
select throws_ok($$ select public.editor_respond_offer(pg_temp.a('o4'), 'counter', -1) $$, 'ES422', null,
  'a negative counter is refused');
select throws_ok($$ select public.editor_respond_offer(pg_temp.a('o4'), 'counter', 1.234) $$, 'ES422', null,
  'a counter with three decimals is refused');
select throws_ok($$ select public.editor_respond_offer(pg_temp.a('o4'), 'counter', 10000000000) $$, 'ES422', null,
  'a counter too large is refused');
select throws_ok($$ select public.editor_respond_offer(pg_temp.a('o4'), 'counter', null) $$, 'ES422', null,
  'a counter without an amount is refused');
select throws_ok($$ select public.editor_respond_offer(pg_temp.a('o4'), null) $$, 'ES422', null,
  'a missing action is refused');
select throws_ok($$ select public.editor_respond_offer(pg_temp.a('o4'), 'Accept') $$, 'ES422', null,
  'actions are case-sensitive');
select throws_ok($$ select public.editor_respond_offer(pg_temp.a('o4'), 'confirm') $$, 'ES422', null,
  'an editor cannot confirm');
select throws_ok($$ select public.editor_respond_offer(pg_temp.a('o4'), 'counter', 13000, null, repeat('m', 2001)) $$,
  'ES422', null, 'a message over 2000 characters is refused');
reset role;

-- Review Focus 6: another editor's offer and an unknown id look the same.
select pg_temp.as_user('56000000-0000-0000-0000-000000000002');
select throws_ok($$ select public.editor_respond_offer(pg_temp.a('o4'), 'accept') $$, 'ES422', 'Offer not found.',
  'editor B cannot answer A''s offer (not found)');
select throws_ok($$ select public.editor_respond_offer('56000000-0000-0000-0000-0000000000ff', 'accept') $$, 'ES422',
  'Offer not found.', 'an unknown offer gives the same message');
reset role;
select ok((select status = 'offered' and proposed_amount = 12000 from public.assignments where id = pg_temp.a('o4')),
  'A''s offer is unchanged');
select ok(pg_get_functiondef('public.editor_respond_offer(uuid, text, numeric, text, text)'::regprocedure)
      ~* 'editor_id\s*=\s*v_editor.*Offer not found\..*lock_assignment',
  'ownership is checked before any project row is locked');

-- Review Focus 7: suspended between offer and response.
update public.editor_profiles set access_status = 'suspended' where user_id = '56000000-0000-0000-0000-000000000001';
select pg_temp.as_user('56000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_respond_offer(pg_temp.a('o4'), 'accept') $$, 'ES403', null,
  'a suspended editor cannot respond');
reset role;
update public.editor_profiles set access_status = 'active' where user_id = '56000000-0000-0000-0000-000000000001';
select ok((select status = 'offered' from public.assignments where id = pg_temp.a('o4')), 'the offer is unchanged');

-- Review Focus 11: project on hold.
update public.projects set status = 'on_hold', status_before_hold = 'open' where id = '56000000-0000-0000-0000-0000000000f1';
select pg_temp.as_user('56000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_respond_offer(pg_temp.a('o4'), 'accept') $$, 'ES409', null,
  'no responses while the project is on hold');
reset role;
update public.projects set status = 'open', status_before_hold = null where id = '56000000-0000-0000-0000-0000000000f1';

-- From counteroffer_pending and withdrawn.
select pg_temp.as_user('56000000-0000-0000-0000-000000000001');
select public.editor_respond_offer(pg_temp.a('o4'), 'counter', 13000);
select throws_ok($$ select public.editor_respond_offer(pg_temp.a('o4'), 'counter', 14000) $$, 'ES409', null,
  'no response while a counteroffer is pending');
reset role;
select pg_temp.withdraw('o4');
select pg_temp.as_user('56000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_respond_offer(pg_temp.a('o4'), 'accept') $$, 'ES409', null,
  'no response to a withdrawn offer');

-- ---------------------------------------------------------------------------
-- Cross-role refusals
-- ---------------------------------------------------------------------------
select throws_ok($$ select public.admin_make_offer('56000000-0000-0000-0000-0000000000f1',
  '56000000-0000-0000-0000-000000000001', 100) $$, 'ES403', null, 'an editor cannot make offers');
select throws_ok($$ select public.admin_confirm_assignment(pg_temp.a('o4')) $$, 'ES403', null,
  'an editor cannot confirm assignments');
select throws_ok($$ select public.admin_withdraw_offer(pg_temp.a('o4')) $$, 'ES403', null,
  'an editor cannot withdraw offers');
select throws_ok($$ update public.assignments set status = 'confirmed' $$, '42501', null,
  'an editor cannot update assignments directly');
reset role;

select pg_temp.as_anon();
select throws_ok($$ select public.editor_respond_offer('56000000-0000-0000-0000-0000000000ff', 'accept') $$, 'ES401',
  null, 'anon is refused (ES401)');
reset role;
select pg_temp.as_user('56000000-0000-0000-0000-000000000003');
select throws_ok($$ select public.editor_respond_offer('56000000-0000-0000-0000-0000000000ff', 'accept') $$, 'ES403',
  null, 'an applicant is refused (ES403)');
reset role;
select pg_temp.as_user('56000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.editor_respond_offer('56000000-0000-0000-0000-0000000000ff', 'accept') $$, 'ES403',
  null, 'an admin is refused (ES403)');
reset role;

select * from finish();

rollback;
