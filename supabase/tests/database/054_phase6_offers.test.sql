-- Phase 6: admin access grants, offers, counteroffer responses, withdrawals and access revokes.
-- Review Focus 3 (amounts and currency), 4 (editor id lists), 8 (re-offers), 9 (actions),
-- 10 (messages), 11 (on-hold project).
begin;

create extension if not exists pgtap with schema extensions;

select plan(73);

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
-- Fixtures (as postgres)
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('54000000-0000-0000-0000-00000000000a', 'p6o-admin@test.local', '{}', '{}'),
  ('54000000-0000-0000-0000-000000000001', 'p6o-editor-a@test.local', '{}', '{}'),
  ('54000000-0000-0000-0000-000000000002', 'p6o-editor-b@test.local', '{}', '{}'),
  ('54000000-0000-0000-0000-000000000003', 'p6o-applicant@test.local', '{}', '{}'),
  ('54000000-0000-0000-0000-000000000004', 'p6o-suspended@test.local', '{}', '{}'),
  ('54000000-0000-0000-0000-000000000005', 'p6o-editor-c@test.local', '{}', '{}');
select private.grant_admin_by_email('p6o-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('54000000-0000-0000-0000-000000000001', '54000000-0000-0000-0000-000000000002',
                  '54000000-0000-0000-0000-000000000005');
update public.editor_profiles set access_status = 'suspended'
where user_id = '54000000-0000-0000-0000-000000000004';

-- P main (open), P2 open in USD, D never opened, D2 opened then back to draft, H on hold,
-- X cancelled, R archived, P3 assigned with a confirmed editor.
insert into public.projects (id, title, brief_type, status, status_before_hold, first_opened_at, archived_at,
  proposed_amount, proposed_currency) values
  ('54000000-0000-0000-0000-0000000000f1', 'Main', 'fully_instructed', 'open', null, now(), null, 20000, 'LKR'),
  ('54000000-0000-0000-0000-0000000000f2', 'Dollar', 'fully_instructed', 'open', null, now(), null, 300, 'USD'),
  ('54000000-0000-0000-0000-0000000000d1', 'Never opened', 'fully_instructed', 'draft', null, null, null, null, 'LKR'),
  ('54000000-0000-0000-0000-0000000000d2', 'Back to draft', 'fully_instructed', 'draft', null, now(), null, null, 'LKR'),
  ('54000000-0000-0000-0000-0000000000e1', 'On hold', 'fully_instructed', 'on_hold', 'open', now(), null, null, 'LKR'),
  ('54000000-0000-0000-0000-0000000000e2', 'Cancelled', 'fully_instructed', 'cancelled', null, now(), null, null, 'LKR'),
  ('54000000-0000-0000-0000-0000000000e3', 'Archived', 'fully_instructed', 'open', null, now(), now(), null, 'LKR'),
  ('54000000-0000-0000-0000-0000000000f3', 'Assigned', 'fully_instructed', 'assigned', null, now(), null, null, 'LKR');
-- Phase 12A: an editor is confirmed only after the project terms are agreed.
update public.project_terms set status = 'agreed', agreed_at = now() where status = 'draft';
insert into public.assignments (id, project_id, editor_id, status, proposed_amount, agreed_amount, agreed_currency,
  confirmed_at) values
  ('54000000-0000-0000-0000-0000000000b3', '54000000-0000-0000-0000-0000000000f3',
   '54000000-0000-0000-0000-000000000002', 'confirmed', 9000, 9000, 'LKR', now());
insert into public.project_access (project_id, editor_id, reason) values
  ('54000000-0000-0000-0000-0000000000f3', '54000000-0000-0000-0000-000000000002', 'invited');
-- On-hold project with live rows (Review Focus 11).
insert into public.assignments (id, project_id, editor_id, status, proposed_amount) values
  ('54000000-0000-0000-0000-0000000000b4', '54000000-0000-0000-0000-0000000000e1',
   '54000000-0000-0000-0000-000000000002', 'counteroffer_pending', 8000);

create temp table ids (kind text primary key, id uuid not null);
grant select, insert on ids to authenticated;

create function pg_temp.a(p_kind text) returns uuid language sql as $$ select id from ids where kind = p_kind $$;
grant execute on function pg_temp.a(text) to authenticated;

create function pg_temp.live_access(p_project uuid) returns int language sql as $$
  select count(*)::int from public.project_access where project_id = p_project and revoked_at is null $$;
grant execute on function pg_temp.live_access(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- admin_grant_project_access (Review Focus 4, plan call 17)
-- ---------------------------------------------------------------------------
select pg_temp.as_user('54000000-0000-0000-0000-00000000000a', 'aal2');
select is(public.admin_grant_project_access('54000000-0000-0000-0000-0000000000f1',
  array['54000000-0000-0000-0000-000000000001', '54000000-0000-0000-0000-000000000002']::uuid[], 'invited'), 2,
  'admin invites two active editors');
select is(public.admin_grant_project_access('54000000-0000-0000-0000-0000000000f1',
  array['54000000-0000-0000-0000-000000000001', '54000000-0000-0000-0000-000000000002']::uuid[], 'available'), 0,
  'granting again is idempotent');
select ok((select bool_and(reason = 'invited' and granted_by = '54000000-0000-0000-0000-00000000000a')
  from public.project_access where project_id = '54000000-0000-0000-0000-0000000000f1'),
  'existing live rows keep their reason');
select ok((select count(*) = 2 and bool_and((select array_agg(k order by k) from jsonb_object_keys(details) k)
    = array['editor_id', 'project_id', 'reason'])
  from public.activity_logs where action = 'project_access.granted'),
  'one project_access.granted audit row per new row, with ids and the reason');
select throws_ok($$ select public.admin_grant_project_access('54000000-0000-0000-0000-0000000000f1', null, 'invited') $$,
  'ES422', null, 'a missing editor list is refused');
select throws_ok($$ select public.admin_grant_project_access('54000000-0000-0000-0000-0000000000f1', '{}', 'invited') $$,
  'ES422', null, 'an empty editor list is refused');
select throws_ok($$ select public.admin_grant_project_access('54000000-0000-0000-0000-0000000000f1',
  array['54000000-0000-0000-0000-000000000005', '54000000-0000-0000-0000-0000000000ff']::uuid[], 'invited') $$,
  'ES422', null, 'a list with an unknown id is refused');
select throws_ok($$ select public.admin_grant_project_access('54000000-0000-0000-0000-0000000000f1',
  array['54000000-0000-0000-0000-000000000005', '54000000-0000-0000-0000-000000000003']::uuid[], 'invited') $$,
  'ES422', null, 'a list with an applicant is refused');
select throws_ok($$ select public.admin_grant_project_access('54000000-0000-0000-0000-0000000000f1',
  array['54000000-0000-0000-0000-000000000005', '54000000-0000-0000-0000-000000000004']::uuid[], 'invited') $$,
  'ES422', null, 'a list with a suspended editor is refused');
select throws_ok($$ select public.admin_grant_project_access('54000000-0000-0000-0000-0000000000f1',
  array['54000000-0000-0000-0000-000000000005', '54000000-0000-0000-0000-00000000000a']::uuid[], 'invited') $$,
  'ES422', null, 'a list with the calling admin is refused');
select throws_ok($$ select public.admin_grant_project_access('54000000-0000-0000-0000-0000000000f1',
  array['54000000-0000-0000-0000-000000000005', null]::uuid[], 'invited') $$,
  'ES422', null, 'a list with an empty entry is refused');
select throws_ok($$ select public.admin_grant_project_access('54000000-0000-0000-0000-0000000000f1',
  array(select gen_random_uuid() from generate_series(1, 101)), 'invited') $$,
  'ES422', null, 'more than 100 editors are refused');
select is(pg_temp.live_access('54000000-0000-0000-0000-0000000000f1'), 2,
  'refused lists grant nothing (all or nothing)');
select is(public.admin_grant_project_access('54000000-0000-0000-0000-0000000000f2',
  array['54000000-0000-0000-0000-000000000005', '54000000-0000-0000-0000-000000000005']::uuid[], 'available'), 1,
  'duplicate ids are granted once');
select throws_ok($$ select public.admin_grant_project_access('54000000-0000-0000-0000-0000000000d1',
  array['54000000-0000-0000-0000-000000000005']::uuid[], 'invited') $$, 'ES409', null,
  'a never-opened project refuses access grants');
select throws_ok($$ select public.admin_grant_project_access('54000000-0000-0000-0000-0000000000d2',
  array['54000000-0000-0000-0000-000000000005']::uuid[], 'invited') $$, 'ES409', null,
  'a draft project refuses access grants');
select throws_ok($$ select public.admin_grant_project_access('54000000-0000-0000-0000-0000000000e1',
  array['54000000-0000-0000-0000-000000000005']::uuid[], 'invited') $$, 'ES409', null,
  'an on-hold project refuses access grants');
select throws_ok($$ select public.admin_grant_project_access('54000000-0000-0000-0000-0000000000e2',
  array['54000000-0000-0000-0000-000000000005']::uuid[], 'invited') $$, 'ES409', null,
  'a cancelled project refuses access grants');
select throws_ok($$ select public.admin_grant_project_access('54000000-0000-0000-0000-0000000000e3',
  array['54000000-0000-0000-0000-000000000005']::uuid[], 'invited') $$, 'ES409', null,
  'an archived project refuses access grants');
select throws_ok($$ select public.admin_grant_project_access('54000000-0000-0000-0000-0000000000f1',
  array['54000000-0000-0000-0000-000000000005']::uuid[], null) $$, 'ES422', null, 'a missing reason is refused');

-- ---------------------------------------------------------------------------
-- admin_make_offer (Review Focus 3, 8; plan calls 10, 11, 19)
-- ---------------------------------------------------------------------------
insert into ids select 'a1', public.admin_make_offer('54000000-0000-0000-0000-0000000000f1',
  '54000000-0000-0000-0000-000000000001', 15000, 'LKR', 'Welcome aboard');
select ok((select status = 'offered' and proposed_amount = 15000 and currency = 'LKR' and agreed_amount is null
  from public.assignments where id = pg_temp.a('a1')), 'an offer creates an offered assignment');
select ok((select count(*) = 1 and bool_and(from_role = 'admin' and action = 'offer' and amount = 15000
    and currency = 'LKR' and message = 'Welcome aboard' and created_by = '54000000-0000-0000-0000-00000000000a')
  from public.negotiation_offers where assignment_id = pg_temp.a('a1')), 'the offer is recorded in the history');
select is((select count(*)::int from public.activity_logs where action = 'assignment.offered'
  and entity_id = pg_temp.a('a1')::text), 1, 'the offer is audited');
insert into ids select 'c1', public.admin_make_offer('54000000-0000-0000-0000-0000000000f1',
  '54000000-0000-0000-0000-000000000005', 12000);
select ok((select reason = 'invited' from public.project_access where project_id = '54000000-0000-0000-0000-0000000000f1'
  and editor_id = '54000000-0000-0000-0000-000000000005' and revoked_at is null),
  'an offer to an editor without access invites them');

select throws_ok($$ select public.admin_make_offer('54000000-0000-0000-0000-0000000000f1',
  '54000000-0000-0000-0000-000000000002', 0) $$, 'ES422', null, 'a zero amount is refused');
select throws_ok($$ select public.admin_make_offer('54000000-0000-0000-0000-0000000000f1',
  '54000000-0000-0000-0000-000000000002', -5) $$, 'ES422', null, 'a negative amount is refused');
select throws_ok($$ select public.admin_make_offer('54000000-0000-0000-0000-0000000000f1',
  '54000000-0000-0000-0000-000000000002', 1.234) $$, 'ES422', null, 'three decimals are refused');
select throws_ok($$ select public.admin_make_offer('54000000-0000-0000-0000-0000000000f1',
  '54000000-0000-0000-0000-000000000002', 10000000000) $$, 'ES422', null, 'an amount too large is refused');
select throws_ok($$ select public.admin_make_offer('54000000-0000-0000-0000-0000000000f1',
  '54000000-0000-0000-0000-000000000002', null) $$, 'ES422', null, 'a missing amount is refused');
select throws_ok($$ select public.admin_make_offer('54000000-0000-0000-0000-0000000000f1',
  '54000000-0000-0000-0000-000000000002', 100, 'LK') $$, 'ES422', null, 'a two-letter currency is refused');
insert into ids select 'b1', public.admin_make_offer('54000000-0000-0000-0000-0000000000f1',
  '54000000-0000-0000-0000-000000000002', 14000, 'lkr');
select is((select currency::text from public.assignments where id = pg_temp.a('b1')), 'LKR',
  'a lower-case currency is stored upper-case');
insert into ids select 'c2usd', public.admin_make_offer('54000000-0000-0000-0000-0000000000f2',
  '54000000-0000-0000-0000-000000000005', 250);
select is((select currency::text from public.assignments where id = pg_temp.a('c2usd')), 'USD',
  'a missing currency takes the project''s proposed currency');
select throws_ok($$ select public.admin_make_offer('54000000-0000-0000-0000-0000000000f2',
  '54000000-0000-0000-0000-00000000000a', 100) $$, 'ES422', null, 'an admin cannot make an offer to themselves');
select throws_ok($$ select public.admin_make_offer('54000000-0000-0000-0000-0000000000f2',
  '54000000-0000-0000-0000-000000000003', 100) $$, 'ES422', null, 'an applicant cannot receive an offer');
select throws_ok($$ select public.admin_make_offer('54000000-0000-0000-0000-0000000000f2',
  '54000000-0000-0000-0000-000000000004', 100) $$, 'ES422', null, 'a suspended editor cannot receive an offer');

-- Review Focus 8.
select throws_ok($$ select public.admin_make_offer('54000000-0000-0000-0000-0000000000f1',
  '54000000-0000-0000-0000-000000000001', 16000) $$, 'ES409', null,
  'a second offer while one is live is refused');
reset role;
update public.assignments set status = 'counteroffer_pending', proposed_amount = 18000 where id = pg_temp.a('a1');
select pg_temp.as_user('54000000-0000-0000-0000-00000000000a', 'aal2');
select is(public.admin_make_offer('54000000-0000-0000-0000-0000000000f1', '54000000-0000-0000-0000-000000000001',
  17000, null, 'Meet in the middle'), pg_temp.a('a1'), 'an offer on a counteroffer re-offers on the same row');
select ok((select status = 'offered' and proposed_amount = 17000 from public.assignments where id = pg_temp.a('a1'))
  and exists (select 1 from public.negotiation_offers where assignment_id = pg_temp.a('a1') and from_role = 'admin'
    and action = 'counter' and amount = 17000),
  'the re-offer sets offered with the new amount and records a counter');
select public.admin_withdraw_offer(pg_temp.a('a1'), 'Changed plans');
reset role;
create temp table a1_before as select to_jsonb(a) as row from public.assignments a where id = pg_temp.a('a1');
grant select on a1_before to authenticated;
select pg_temp.as_user('54000000-0000-0000-0000-00000000000a', 'aal2');
insert into ids select 'a2', public.admin_make_offer('54000000-0000-0000-0000-0000000000f1',
  '54000000-0000-0000-0000-000000000001', 19000);
select ok(pg_temp.a('a2') <> pg_temp.a('a1')
  and (select to_jsonb(a) from public.assignments a where id = pg_temp.a('a1')) = (select row from a1_before),
  'an offer after a terminal state creates a new row and leaves the old row unchanged');

-- ---------------------------------------------------------------------------
-- admin_respond_counter (Review Focus 9)
-- ---------------------------------------------------------------------------
select throws_ok($$ select public.admin_respond_counter(pg_temp.a('b1'), 'accept') $$, 'ES409', null,
  'there is no counteroffer to respond to on an offered row');
reset role;
update public.assignments set status = 'counteroffer_pending', proposed_amount = 16000 where id = pg_temp.a('b1');
update public.assignments set status = 'counteroffer_pending', proposed_amount = 13000 where id = pg_temp.a('c1');
select pg_temp.as_user('54000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_respond_counter(pg_temp.a('b1'), null) $$, 'ES422', null,
  'a missing action is refused');
select throws_ok($$ select public.admin_respond_counter(pg_temp.a('b1'), 'Accept') $$, 'ES422', null,
  'actions are case-sensitive');
select throws_ok($$ select public.admin_respond_counter(pg_temp.a('b1'), 'confirm') $$, 'ES422', null,
  'an unknown action is refused');
select lives_ok($$ select public.admin_respond_counter(pg_temp.a('b1'), 'accept', 1, 'USD') $$,
  'admin accepts a counteroffer (amount and currency ignored)');
select ok((select status = 'accepted' and agreed_amount = 16000 and agreed_currency = 'LKR'
  from public.assignments where id = pg_temp.a('b1')), 'accepting copies the counter amount into the agreed amount');
select lives_ok($$ select public.admin_respond_counter(pg_temp.a('c1'), 'counter', 12500) $$,
  'admin answers a counteroffer with a new amount');
select ok((select status = 'offered' and proposed_amount = 12500 from public.assignments where id = pg_temp.a('c1')),
  'a counter sets offered with the new amount');
select throws_ok($$ select public.admin_respond_counter(pg_temp.a('c1'), 'counter', 100, 'USD') $$, 'ES409', null,
  'a counter needs a pending counteroffer');
reset role;
update public.assignments set status = 'counteroffer_pending', proposed_amount = 13000 where id = pg_temp.a('c1');
select pg_temp.as_user('54000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_respond_counter(pg_temp.a('c1'), 'counter', 100, 'USD') $$, 'ES422', null,
  'a counter in another currency is refused');
select lives_ok($$ select public.admin_respond_counter(pg_temp.a('c1'), 'decline', null, null, 'Too high') $$,
  'admin declines a counteroffer');
select ok((select status = 'declined' and closed_at is not null from public.assignments where id = pg_temp.a('c1')),
  'declining closes the assignment');

-- Review Focus 10.
select throws_ok($$ select public.admin_make_offer('54000000-0000-0000-0000-0000000000f1',
  '54000000-0000-0000-0000-000000000005', 100, null, repeat('m', 2001)) $$, 'ES422', null,
  'a message over 2000 characters is refused');
insert into ids select 'c3', public.admin_make_offer('54000000-0000-0000-0000-0000000000f1',
  '54000000-0000-0000-0000-000000000005', 11000, null, '   ');
select ok((select message is null from public.negotiation_offers where assignment_id = pg_temp.a('c3')),
  'a whitespace-only message is stored as empty');

-- ---------------------------------------------------------------------------
-- admin_withdraw_offer
-- ---------------------------------------------------------------------------
select lives_ok($$ select public.admin_withdraw_offer(pg_temp.a('c3')) $$, 'admin withdraws an offered row');
reset role;
update public.assignments set status = 'counteroffer_pending', proposed_amount = 20000 where id = pg_temp.a('a2');
select pg_temp.as_user('54000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok($$ select public.admin_withdraw_offer(pg_temp.a('a2')) $$, 'admin withdraws a counteroffer row');
select lives_ok($$ select public.admin_withdraw_offer(pg_temp.a('b1'), 'Going another way') $$,
  'admin withdraws an accepted row');
select ok((select bool_and(status = 'withdrawn' and closed_at is not null) from public.assignments
  where id in (pg_temp.a('c3'), pg_temp.a('a2'), pg_temp.a('b1'))), 'withdrawn rows are closed');
select throws_ok($$ select public.admin_withdraw_offer(pg_temp.a('c1')) $$, 'ES409', null,
  'a declined row cannot be withdrawn');
select throws_ok($$ select public.admin_withdraw_offer('54000000-0000-0000-0000-0000000000b3') $$, 'ES409', null,
  'a confirmed row cannot be withdrawn (reassign instead)');
select throws_ok($$ select public.admin_withdraw_offer('54000000-0000-0000-0000-0000000000ff') $$, 'ES422',
  'Offer not found.', 'an unknown assignment is refused');

-- ---------------------------------------------------------------------------
-- admin_revoke_project_access (plan call 18)
-- ---------------------------------------------------------------------------
select public.admin_grant_project_access('54000000-0000-0000-0000-0000000000f2',
  array['54000000-0000-0000-0000-000000000002']::uuid[], 'invited');
insert into ids select 'b2', public.admin_make_offer('54000000-0000-0000-0000-0000000000f2',
  '54000000-0000-0000-0000-000000000002', 200);
select lives_ok($$ select public.admin_revoke_project_access('54000000-0000-0000-0000-0000000000f2',
  '54000000-0000-0000-0000-000000000002') $$, 'admin revokes an editor with a live offer');
select ok((select status = 'withdrawn' from public.assignments where id = pg_temp.a('b2'))
  and exists (select 1 from public.negotiation_offers where assignment_id = pg_temp.a('b2') and action = 'withdraw')
  and not exists (select 1 from public.project_access where project_id = '54000000-0000-0000-0000-0000000000f2'
    and editor_id = '54000000-0000-0000-0000-000000000002' and revoked_at is null)
  and exists (select 1 from public.activity_logs where action = 'project_access.revoked'),
  'revoking withdraws the live offer and revokes the access row');
select throws_ok($$ select public.admin_revoke_project_access('54000000-0000-0000-0000-0000000000f2',
  '54000000-0000-0000-0000-000000000002') $$, 'ES409', null, 'revoking an editor with nothing live is refused');
select throws_ok($$ select public.admin_revoke_project_access('54000000-0000-0000-0000-0000000000f3',
  '54000000-0000-0000-0000-000000000002') $$, 'ES409', null, 'revoking a confirmed editor is refused');

-- ---------------------------------------------------------------------------
-- Review Focus 11: on-hold project
-- ---------------------------------------------------------------------------
select throws_ok($$ select public.admin_make_offer('54000000-0000-0000-0000-0000000000e1',
  '54000000-0000-0000-0000-000000000005', 100) $$, 'ES409', null, 'no offers on an on-hold project');
select throws_ok($$ select public.admin_respond_counter('54000000-0000-0000-0000-0000000000b4', 'accept') $$,
  'ES409', null, 'no counteroffer responses on an on-hold project');
select ok((select status = 'counteroffer_pending' and proposed_amount = 8000 from public.assignments
  where id = '54000000-0000-0000-0000-0000000000b4'), 'the on-hold project''s live row is unchanged');

-- History rows on the main project: one per money/offer action performed above.
select is((select count(*)::int from public.negotiation_offers n join public.assignments a on a.id = n.assignment_id
  where a.project_id = '54000000-0000-0000-0000-0000000000f1'), 13,
  'one negotiation row per offer, counter, accept, decline and withdraw on the main project');
reset role;

-- ---------------------------------------------------------------------------
-- Non-admin identities
-- ---------------------------------------------------------------------------
create function pg_temp.refused(p_code text)
returns int language plpgsql as $$
declare
  v int := 0;
  v_p uuid := '54000000-0000-0000-0000-0000000000f1';
  v_e uuid := '54000000-0000-0000-0000-000000000005';
  v_x uuid := '54000000-0000-0000-0000-0000000000b4';
begin
  begin perform public.admin_grant_project_access(v_p, array[v_e], 'invited'); exception when sqlstate 'ES401' or sqlstate 'ES403' then if sqlstate = p_code then v := v + 1; end if; end;
  begin perform public.admin_revoke_project_access(v_p, v_e); exception when sqlstate 'ES401' or sqlstate 'ES403' then if sqlstate = p_code then v := v + 1; end if; end;
  begin perform public.admin_make_offer(v_p, v_e, 100); exception when sqlstate 'ES401' or sqlstate 'ES403' then if sqlstate = p_code then v := v + 1; end if; end;
  begin perform public.admin_respond_counter(v_x, 'accept'); exception when sqlstate 'ES401' or sqlstate 'ES403' then if sqlstate = p_code then v := v + 1; end if; end;
  begin perform public.admin_withdraw_offer(v_x); exception when sqlstate 'ES401' or sqlstate 'ES403' then if sqlstate = p_code then v := v + 1; end if; end;
  begin perform public.admin_confirm_assignment(v_x); exception when sqlstate 'ES401' or sqlstate 'ES403' then if sqlstate = p_code then v := v + 1; end if; end;
  begin perform public.admin_reassign(v_x); exception when sqlstate 'ES401' or sqlstate 'ES403' then if sqlstate = p_code then v := v + 1; end if; end;
  begin perform public.admin_add_project_note(v_p, 'x'); exception when sqlstate 'ES401' or sqlstate 'ES403' then if sqlstate = p_code then v := v + 1; end if; end;
  begin perform public.admin_pending_revocations(); exception when sqlstate 'ES401' or sqlstate 'ES403' then if sqlstate = p_code then v := v + 1; end if; end;
  return v;
end;
$$;
grant execute on function pg_temp.refused(text) to anon, authenticated;

select pg_temp.as_anon();
select is(pg_temp.refused('ES401'), 9, 'anon is refused (ES401) by all nine admin functions');
reset role;
select pg_temp.as_user('54000000-0000-0000-0000-00000000000a', 'aal1');
select is(pg_temp.refused('ES403'), 9, 'admin without MFA is refused (ES403) by all nine admin functions');
reset role;
select pg_temp.as_user('54000000-0000-0000-0000-000000000001');
select is(pg_temp.refused('ES403'), 9, 'editor A is refused (ES403) by all nine admin functions');
reset role;
select pg_temp.as_user('54000000-0000-0000-0000-000000000003');
select is(pg_temp.refused('ES403'), 9, 'an applicant is refused (ES403) by all nine admin functions');
reset role;

select is_empty($$ select action from public.activity_logs
  where (action like 'assignment.%' or action like 'project_access.%')
    and (details::text like '%15000%' or details::text like '%Welcome%' or details ?| array['amount', 'message']) $$,
  'access and assignment audit rows hold no amounts or messages');

select * from finish();

rollback;
