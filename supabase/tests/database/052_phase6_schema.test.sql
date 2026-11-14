-- Phase 6: access, assignments, negotiation and notes schema. Admin-only base reads (editor
-- own-row policies arrive in the visibility migration and are tested in 053, so the
-- editor-owned rows here belong to a suspended editor, who never sees them), no direct writes,
-- unique live/confirmed rows, the assignment transition guard, append-only offers and notes.
begin;

create extension if not exists pgtap with schema extensions;

select plan(53);

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

create function pg_temp.visible_counts()
returns int[] language sql as $$
  select array[
    (select count(*)::int from public.project_access),
    (select count(*)::int from public.assignments),
    (select count(*)::int from public.negotiation_offers),
    (select count(*)::int from public.project_notes)];
$$;
grant execute on function pg_temp.visible_counts() to authenticated;

-- ---------------------------------------------------------------------------
-- Fixtures (as postgres)
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('52000000-0000-0000-0000-00000000000a', 'p6s-admin@test.local', '{}', '{}'),
  ('52000000-0000-0000-0000-000000000001', 'p6s-editor-a@test.local', '{}', '{}'),
  ('52000000-0000-0000-0000-000000000002', 'p6s-editor-b@test.local', '{}', '{}'),
  ('52000000-0000-0000-0000-000000000003', 'p6s-applicant@test.local', '{}', '{}'),
  ('52000000-0000-0000-0000-000000000004', 'p6s-suspended@test.local', '{}', '{}');
select private.grant_admin_by_email('p6s-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('52000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000002');
update public.editor_profiles set access_status = 'suspended'
where user_id = '52000000-0000-0000-0000-000000000004';

insert into public.projects (id, title, brief_type, status, first_opened_at) values
  ('52000000-0000-0000-0000-0000000000f1', 'Seed', 'fully_instructed', 'open', now()),
  ('52000000-0000-0000-0000-0000000000f2', 'Constraints', 'fully_instructed', 'open', now());
insert into public.project_access (id, project_id, editor_id, reason, granted_by) values
  ('52000000-0000-0000-0000-0000000000a1', '52000000-0000-0000-0000-0000000000f1',
   '52000000-0000-0000-0000-000000000004', 'invited', '52000000-0000-0000-0000-00000000000a');
insert into public.assignments (id, project_id, editor_id, proposed_amount) values
  ('52000000-0000-0000-0000-0000000000b1', '52000000-0000-0000-0000-0000000000f1',
   '52000000-0000-0000-0000-000000000004', 10000);
insert into public.negotiation_offers (id, assignment_id, from_role, action, amount, currency, message, created_by)
values ('52000000-0000-0000-0000-0000000000c1', '52000000-0000-0000-0000-0000000000b1', 'admin', 'offer',
        10000, 'LKR', 'Welcome', '52000000-0000-0000-0000-00000000000a');
insert into public.project_notes (id, project_id, author_id, note) values
  ('52000000-0000-0000-0000-0000000000d1', '52000000-0000-0000-0000-0000000000f1',
   '52000000-0000-0000-0000-00000000000a', 'Called the client.');

create temp table expected as select pg_temp.visible_counts() as c;
grant select on expected to authenticated;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
select enum_has_labels('public', 'project_access_reason', array['invited', 'available'],
  'project_access_reason labels');
select enum_has_labels('public', 'assignment_status', array['offered', 'counteroffer_pending', 'accepted',
  'confirmed', 'in_progress', 'declined', 'withdrawn', 'not_selected', 'reassigned'], 'assignment_status labels');
select enum_has_labels('public', 'negotiation_role', array['admin', 'editor'], 'negotiation_role labels');
select enum_has_labels('public', 'negotiation_action', array['offer', 'counter', 'accept', 'decline', 'withdraw'],
  'negotiation_action labels');

-- ---------------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------------
select pg_temp.as_anon();
select throws_ok($$ select 1 from public.project_access $$, '42501', null, 'anon cannot read project_access');
select throws_ok($$ select 1 from public.assignments $$, '42501', null, 'anon cannot read assignments');
select throws_ok($$ select 1 from public.negotiation_offers $$, '42501', null, 'anon cannot read negotiation_offers');
select throws_ok($$ select 1 from public.project_notes $$, '42501', null, 'anon cannot read project_notes');
reset role;

select pg_temp.as_user('52000000-0000-0000-0000-000000000002');
select is(pg_temp.visible_counts(), array[0,0,0,0], 'editor B sees none of these rows');
reset role;
select pg_temp.as_user('52000000-0000-0000-0000-000000000004');
select is(pg_temp.visible_counts(), array[0,0,0,0], 'a suspended editor sees none of these rows, even their own');
reset role;
select pg_temp.as_user('52000000-0000-0000-0000-000000000003');
select is(pg_temp.visible_counts(), array[0,0,0,0], 'a pending applicant sees none of these rows');
reset role;
select pg_temp.as_user('52000000-0000-0000-0000-00000000000a', 'aal1');
select is(pg_temp.visible_counts(), array[0,0,0,0], 'admin without MFA sees none of these rows');
reset role;

select pg_temp.as_user('52000000-0000-0000-0000-00000000000a', 'aal2');
select is(pg_temp.visible_counts(), (select c from expected), 'admin with MFA sees every row');
select ok((select c from expected) = array[1,1,1,1], 'the seeded rows exist');
select throws_ok($$ insert into public.project_access (project_id, editor_id, reason)
  values ('52000000-0000-0000-0000-0000000000f1', '52000000-0000-0000-0000-000000000001', 'invited') $$,
  '42501', null, 'admin cannot insert project_access directly');
select throws_ok($$ update public.project_access set revoked_at = now() $$, '42501', null,
  'admin cannot update project_access directly');
select throws_ok($$ delete from public.project_access $$, '42501', null, 'admin cannot delete project_access directly');
select throws_ok($$ insert into public.assignments (project_id, editor_id, proposed_amount)
  values ('52000000-0000-0000-0000-0000000000f1', '52000000-0000-0000-0000-000000000001', 1) $$,
  '42501', null, 'admin cannot insert assignments directly');
select throws_ok($$ update public.assignments set status = 'withdrawn' $$, '42501', null,
  'admin cannot update assignments directly');
select throws_ok($$ delete from public.assignments $$, '42501', null, 'admin cannot delete assignments directly');
select throws_ok($$ insert into public.negotiation_offers (assignment_id, from_role, action)
  values ('52000000-0000-0000-0000-0000000000b1', 'admin', 'withdraw') $$,
  '42501', null, 'admin cannot insert negotiation_offers directly');
select throws_ok($$ update public.negotiation_offers set message = 'x' $$, '42501', null,
  'admin cannot update negotiation_offers directly');
select throws_ok($$ delete from public.negotiation_offers $$, '42501', null,
  'admin cannot delete negotiation_offers directly');
select throws_ok($$ insert into public.project_notes (project_id, note)
  values ('52000000-0000-0000-0000-0000000000f1', 'x') $$, '42501', null, 'admin cannot insert notes directly');
select throws_ok($$ update public.project_notes set note = 'x' $$, '42501', null, 'admin cannot update notes directly');
select throws_ok($$ delete from public.project_notes $$, '42501', null, 'admin cannot delete notes directly');
reset role;

-- ---------------------------------------------------------------------------
-- Assignment constraints (as postgres)
-- ---------------------------------------------------------------------------
insert into public.assignments (id, project_id, editor_id, proposed_amount) values
  ('52000000-0000-0000-0000-0000000000b2', '52000000-0000-0000-0000-0000000000f2',
   '52000000-0000-0000-0000-000000000001', 5000);
select throws_ok($$ insert into public.assignments (project_id, editor_id, proposed_amount)
  values ('52000000-0000-0000-0000-0000000000f2', '52000000-0000-0000-0000-000000000001', 6000) $$,
  '23505', null, 'one live assignment per project and editor');
update public.assignments set status = 'declined', closed_at = now() where id = '52000000-0000-0000-0000-0000000000b2';
select lives_ok($$ insert into public.assignments (project_id, editor_id, proposed_amount)
  values ('52000000-0000-0000-0000-0000000000f2', '52000000-0000-0000-0000-000000000001', 6000) $$,
  'a new offer after a declined one creates a second row');
insert into public.assignments (project_id, editor_id, status, proposed_amount, agreed_amount, agreed_currency,
  confirmed_at) values
  ('52000000-0000-0000-0000-0000000000f2', '52000000-0000-0000-0000-000000000002', 'confirmed', 5000, 5000, 'LKR', now());
select throws_ok($$ insert into public.assignments (project_id, editor_id, status, proposed_amount, agreed_amount,
  agreed_currency, confirmed_at)
  values ('52000000-0000-0000-0000-0000000000f2', '52000000-0000-0000-0000-000000000004', 'confirmed', 5000, 5000,
          'LKR', now()) $$, '23505', null, 'at most one confirmed assignment per project');
select throws_ok($$ insert into public.assignments (project_id, editor_id, status, proposed_amount)
  values ('52000000-0000-0000-0000-0000000000f1', '52000000-0000-0000-0000-000000000002', 'accepted', 5000) $$,
  '23514', null, 'accepted needs an agreed amount');
select throws_ok($$ insert into public.assignments (project_id, editor_id, status, proposed_amount, agreed_amount,
  agreed_currency) values ('52000000-0000-0000-0000-0000000000f1', '52000000-0000-0000-0000-000000000002',
  'accepted', 5000, 5000, 'USD') $$, '23514', null, 'the agreed currency must match the offer currency');
select throws_ok($$ insert into public.assignments (project_id, editor_id, status, proposed_amount)
  values ('52000000-0000-0000-0000-0000000000f1', '52000000-0000-0000-0000-000000000002', 'withdrawn', 5000) $$,
  '23514', null, 'a closed assignment needs closed_at');
select throws_ok($$ insert into public.assignments (project_id, editor_id, proposed_amount)
  values ('52000000-0000-0000-0000-0000000000f1', '52000000-0000-0000-0000-000000000002', 0) $$,
  '23514', null, 'an offer amount must be above zero');
select throws_ok($$ update public.assignments set editor_id = '52000000-0000-0000-0000-000000000002'
  where id = '52000000-0000-0000-0000-0000000000b1' $$, 'ES409', null, 'the editor of an assignment cannot change');
select throws_ok($$ update public.assignments set project_id = '52000000-0000-0000-0000-0000000000f2'
  where id = '52000000-0000-0000-0000-0000000000b1' $$, 'ES409', null, 'the project of an assignment cannot change');

-- Transition matrix: every (from, to) pair on its own project.
create temp table matrix as
select f.s as from_s, t.s as to_s, gen_random_uuid() as project_id, gen_random_uuid() as id
from unnest(enum_range(null::public.assignment_status)) f(s),
     unnest(enum_range(null::public.assignment_status)) t(s);
insert into public.projects (id, title, brief_type, status) select project_id, 'Matrix', 'creative_led', 'open' from matrix;
insert into public.assignments (id, project_id, editor_id, status, proposed_amount, agreed_amount, agreed_currency,
  confirmed_at, started_at, closed_at)
select id, project_id, '52000000-0000-0000-0000-000000000001', from_s, 1000,
  case when from_s not in ('offered', 'counteroffer_pending') then 1000 end,
  case when from_s not in ('offered', 'counteroffer_pending') then 'LKR' end,
  case when from_s in ('confirmed', 'in_progress', 'reassigned') then now() end,
  case when from_s = 'in_progress' then now() end,
  case when from_s in ('declined', 'withdrawn', 'not_selected', 'reassigned') then now() end
from matrix;

create function pg_temp.try_matrix()
returns text[] language plpgsql as $$
declare
  r record;
  v_ok text[] := '{}';
begin
  for r in select * from matrix loop
    begin
      update public.assignments set
        status = r.to_s,
        agreed_amount = case when r.to_s not in ('offered', 'counteroffer_pending') then 1000 end,
        agreed_currency = case when r.to_s not in ('offered', 'counteroffer_pending') then 'LKR' end,
        confirmed_at = case when r.to_s in ('confirmed', 'in_progress', 'reassigned') then now() end,
        started_at = case when r.to_s = 'in_progress' then now() end,
        closed_at = case when r.to_s in ('declined', 'withdrawn', 'not_selected', 'reassigned') then now() end
      where id = r.id;
      v_ok := v_ok || (r.from_s || '>' || r.to_s);
    exception
      when sqlstate 'ES409' then null;
    end;
  end loop;
  return v_ok;
end;
$$;

select is(
  (select array_agg(x order by x collate "C") from unnest(pg_temp.try_matrix()) x),
  (select array_agg(x order by x collate "C") from unnest(array[
    'offered>accepted', 'offered>declined', 'offered>counteroffer_pending', 'offered>withdrawn',
    'offered>not_selected', 'counteroffer_pending>accepted', 'counteroffer_pending>offered',
    'counteroffer_pending>declined', 'counteroffer_pending>withdrawn', 'counteroffer_pending>not_selected',
    'accepted>confirmed', 'accepted>withdrawn', 'accepted>not_selected', 'confirmed>reassigned',
    'confirmed>withdrawn', 'in_progress>reassigned', 'in_progress>withdrawn',
    'offered>offered', 'counteroffer_pending>counteroffer_pending', 'accepted>accepted', 'confirmed>confirmed',
    'in_progress>in_progress', 'declined>declined', 'withdrawn>withdrawn', 'not_selected>not_selected', 'reassigned>reassigned']) x),
  'exactly the allowed transitions (and same-status updates) succeed over all 81 pairs; confirmed>in_progress is refused by the gate');
select ok((select bool_and(a.status = m.from_s) from matrix m join public.assignments a on a.id = m.id
  where m.from_s <> m.to_s and not private.assignment_transition_allowed(m.from_s, m.to_s)),
  'refused transitions leave the status unchanged');

-- ---------------------------------------------------------------------------
-- Append-only negotiation offers and notes (UPDATE and DELETE refused, even for postgres)
-- ---------------------------------------------------------------------------
select throws_ok($$ insert into public.negotiation_offers (assignment_id, from_role, action, amount, currency)
  values ('52000000-0000-0000-0000-0000000000b1', 'editor', 'decline', 100, 'LKR') $$,
  '23514', null, 'a decline carries no amount');
select throws_ok($$ insert into public.negotiation_offers (assignment_id, from_role, action)
  values ('52000000-0000-0000-0000-0000000000b1', 'admin', 'offer') $$,
  '23514', null, 'an offer needs an amount');
select throws_ok($$ update public.negotiation_offers set message = 'Changed'
  where id = '52000000-0000-0000-0000-0000000000c1' $$, 'ES409', null, 'a negotiation row cannot be changed');
select throws_ok($$ delete from public.negotiation_offers where id = '52000000-0000-0000-0000-0000000000c1' $$,
  'ES409', null, 'a negotiation row cannot be deleted, even by postgres');
select throws_ok($$ update public.negotiation_offers set created_by = null, message = 'Changed'
  where id = '52000000-0000-0000-0000-0000000000c1' $$, 'ES409', null,
  'clearing created_by together with another column is refused');
select lives_ok($$ update public.negotiation_offers set created_by = null
  where id = '52000000-0000-0000-0000-0000000000c1' $$, 'clearing only created_by is allowed (account deletion)');

select throws_ok($$ update public.project_notes set note = 'Changed' where id = '52000000-0000-0000-0000-0000000000d1' $$,
  'ES409', null, 'a note cannot be changed');
select throws_ok($$ delete from public.project_notes where id = '52000000-0000-0000-0000-0000000000d1' $$,
  'ES409', null, 'a note cannot be deleted, even by postgres');
select throws_ok($$ update public.project_notes set author_id = null, note = 'Changed'
  where id = '52000000-0000-0000-0000-0000000000d1' $$, 'ES409', null,
  'clearing author_id together with the note is refused');
select lives_ok($$ update public.project_notes set author_id = null where id = '52000000-0000-0000-0000-0000000000d1' $$,
  'clearing only author_id is allowed (account deletion)');

-- ---------------------------------------------------------------------------
-- Project access
-- ---------------------------------------------------------------------------
select throws_ok($$ insert into public.project_access (project_id, editor_id, reason)
  values ('52000000-0000-0000-0000-0000000000f1', '52000000-0000-0000-0000-000000000004', 'available') $$,
  '23505', null, 'one live access row per project and editor');
update public.project_access set revoked_at = now() where id = '52000000-0000-0000-0000-0000000000a1';
select lives_ok($$ insert into public.project_access (project_id, editor_id, reason)
  values ('52000000-0000-0000-0000-0000000000f1', '52000000-0000-0000-0000-000000000004', 'available') $$,
  'access can be granted again after a revoke');

-- ---------------------------------------------------------------------------
-- Assignment audit trigger
-- ---------------------------------------------------------------------------
insert into public.assignments (id, project_id, editor_id, proposed_amount) values
  ('52000000-0000-0000-0000-0000000000b9', '52000000-0000-0000-0000-0000000000f1',
   '52000000-0000-0000-0000-000000000002', 7777);
update public.assignments set status = 'accepted', agreed_amount = 7777, agreed_currency = 'LKR'
where id = '52000000-0000-0000-0000-0000000000b9';
select is((select array_agg(action order by id) from public.activity_logs
  where entity_type = 'assignment' and entity_id = '52000000-0000-0000-0000-0000000000b9'),
  array['assignment.offered', 'assignment.accepted'], 'insert and status change write assignment audit rows');
select ok((select bool_and((select array_agg(k order by k) from jsonb_object_keys(details) k)
    = array['assignment_id', 'editor_id', 'from', 'project_id', 'to'])
  from public.activity_logs where entity_type = 'assignment' and entity_id = '52000000-0000-0000-0000-0000000000b9'),
  'assignment audit details have exactly the id and status keys');
select is((select details ->> 'from' || '>' || (details ->> 'to') from public.activity_logs
  where action = 'assignment.accepted' and entity_id = '52000000-0000-0000-0000-0000000000b9'),
  'offered>accepted', 'the audit row records the from and to statuses');
-- Every assignment audit row (not just the seeded one) carries only id and status keys, so none
-- can hold an amount.
select ok((select count(*) > 1 and bool_and((select array_agg(k order by k) from jsonb_object_keys(details) k)
    = array['assignment_id', 'editor_id', 'from', 'project_id', 'to'])
  from public.activity_logs where entity_type = 'assignment'),
  'assignment audit rows hold no amounts (only the allowed details keys, across all rows)');

select * from finish();

rollback;
