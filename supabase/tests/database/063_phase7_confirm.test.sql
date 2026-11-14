-- Phase 7: editor_confirm_brief. Exact copies, optimistic checks, carry-forward versus
-- re-acknowledgement, deadline drift, interpretation first. Review Focus 1, 2, 3, 6, 7, 11.
begin;

create extension if not exists pgtap with schema extensions;

select plan(48);

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

create function pg_temp.assignment(p_title text, p_editor uuid, p_interp boolean, p_confirm boolean default true)
returns uuid language plpgsql as $$
declare
  v_project uuid;
  v_id uuid;
begin
  perform pg_temp.as_user('63000000-0000-0000-0000-00000000000a', 'aal2');
  v_project := public.admin_create_project(jsonb_build_object('title', p_title, 'brief_type', 'fully_instructed',
    'deadline', '2026-12-31', 'requires_interpretation', p_interp, 'brief', jsonb_build_object('instructions', 'Cut it'),
    'deliverables', jsonb_build_array(jsonb_build_object('name', 'Main'))));
  perform public.admin_set_project_status(v_project, 'open');
  v_id := public.admin_make_offer(v_project, p_editor, 10000, 'LKR');
  perform pg_temp.as_user(p_editor);
  perform public.editor_respond_offer(v_id, 'accept');
  if p_confirm then
    perform pg_temp.as_user('63000000-0000-0000-0000-00000000000a', 'aal2');
    perform public.admin_confirm_assignment(v_id);
  end if;
  reset role;
  return v_id;
end;
$$;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('63000000-0000-0000-0000-00000000000a', 'p7c-admin@test.local', '{}', '{}'),
  ('63000000-0000-0000-0000-000000000001', 'p7c-editor-a@test.local', '{}', '{}'),
  ('63000000-0000-0000-0000-000000000002', 'p7c-editor-b@test.local', '{}', '{}');
select private.grant_admin_by_email('p7c-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('63000000-0000-0000-0000-000000000001', '63000000-0000-0000-0000-000000000002');

create temp table ids (kind text primary key, id uuid not null);
grant select, insert on ids to authenticated;
create function pg_temp.a(p_kind text) returns uuid language sql as $$ select id from ids where kind = p_kind $$;
grant execute on function pg_temp.a(text) to authenticated;
create function pg_temp.project(p_kind text) returns uuid language sql as $$
  select project_id from public.assignments where id = (select id from ids where kind = p_kind) $$;
grant execute on function pg_temp.project(text) to authenticated;
create function pg_temp.rows(p_kind text) returns int language sql as $$
  select count(*)::int from public.brief_confirmations where assignment_id = (select id from ids where kind = p_kind) $$;

insert into ids select 'p', pg_temp.assignment('P', '63000000-0000-0000-0000-000000000001', false);
insert into ids select 'i', pg_temp.assignment('I interp', '63000000-0000-0000-0000-000000000001', true);
insert into ids select 'x', pg_temp.assignment('X accepted', '63000000-0000-0000-0000-000000000001', false, false);
insert into ids select 'r', pg_temp.assignment('R archived', '63000000-0000-0000-0000-000000000001', false);
insert into ids select 'd', pg_temp.assignment('D deadline', '63000000-0000-0000-0000-000000000001', false);
update public.projects set archived_at = now() where id = pg_temp.project('r');

-- ---------------------------------------------------------------------------
-- Optimistic checks and input classes (Review Focus 1, 2)
-- ---------------------------------------------------------------------------
select pg_temp.as_user('63000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_confirm_brief(pg_temp.a('p'), null, '2026-12-31', 10000, 'LKR') $$, 'ES422',
  null, 'a missing version is refused');
select throws_ok($$ select public.editor_confirm_brief(pg_temp.a('p'), 0, '2026-12-31', 10000, 'LKR') $$, 'ES422',
  null, 'version 0 is refused');
select throws_ok($$ select public.editor_confirm_brief(pg_temp.a('p'), 2, '2026-12-31', 10000, 'LKR') $$, 'ES409',
  'The brief, deadline or pay changed while you were reviewing. Please review it again.',
  'a future version is refused as a mismatch');
select throws_ok($$ select public.editor_confirm_brief(pg_temp.a('p'), 1, '2027-01-01', 10000, 'LKR') $$, 'ES409',
  null, 'a stale deadline is refused');
select throws_ok($$ select public.editor_confirm_brief(pg_temp.a('p'), 1, null, 10000, 'LKR') $$, 'ES422', null,
  'a missing deadline is refused');
select throws_ok($$ select public.editor_confirm_brief(pg_temp.a('p'), 1, '2026-12-31', 9000, 'LKR') $$, 'ES409',
  null, 'a different amount is refused');
select throws_ok($$ select public.editor_confirm_brief(pg_temp.a('p'), 1, '2026-12-31', 10000, 'USD') $$, 'ES409',
  null, 'the same amount in another currency is refused');
select throws_ok($$ select public.editor_confirm_brief(pg_temp.a('p'), 1, '2026-12-31', 10000, 'LK') $$, 'ES422',
  null, 'a malformed currency is refused');
select throws_ok($$ select public.editor_confirm_brief(pg_temp.a('p'), 1, '2026-12-31', 10000, null) $$, 'ES422',
  null, 'a missing currency is refused');
select throws_ok($$ select public.editor_confirm_brief(pg_temp.a('p'), 1, '2026-12-31', null, 'LKR') $$, 'ES422',
  null, 'a missing amount is refused');
select is(pg_temp.rows('p'), 0, 'refused confirmations write nothing');

-- ---------------------------------------------------------------------------
-- Confirm v1 with the displayed values (currency case-insensitive)
-- ---------------------------------------------------------------------------
insert into ids select 'c1', public.editor_confirm_brief(pg_temp.a('p'), 1, '2026-12-31', 10000, 'lkr');
select throws_ok($$ select public.editor_confirm_brief(pg_temp.a('p'), 1, '2026-12-31', 10000, 'LKR') $$, 'ES409',
  'You have already confirmed this brief.', 'confirming the same brief twice is refused');
select ok((select brief_confirmed and ready from public.get_assignment_gate(pg_temp.a('p'))),
  'the gate shows the brief confirmed and ready');
reset role;
select ok((select c.kind = 'confirmed' and c.carried_from_id is null and c.brief_version = 1
    and c.brief_version_id = bv.id and c.confirmed_deadline = '2026-12-31' and c.confirmed_deliverables = bv.deliverables
    and c.confirmed_amount = 10000 and c.confirmed_currency = 'LKR' and c.created_by = '63000000-0000-0000-0000-000000000001'
    and c.project_id = pg_temp.project('p') and c.editor_id = '63000000-0000-0000-0000-000000000001'
  from public.brief_confirmations c
  join public.brief_versions bv on bv.project_id = c.project_id and bv.version = 1
  where c.id = pg_temp.a('c1')), 'the row holds exact copies of version, deadline, deliverables and pay');

-- ---------------------------------------------------------------------------
-- Carry-forward (false) versus re-acknowledgement (true); deadline drift
-- ---------------------------------------------------------------------------
select pg_temp.as_user('63000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_save_brief(pg_temp.project('p'), '{"brief": {"instructions": "Cut it well"},
  "change_summary": "Wording", "requires_reacknowledgement": false}');
select ok((select brief_confirmed and confirmed_brief_version = 2 from public.get_assignment_gate(pg_temp.a('p'))),
  'a v2 without re-acknowledgement keeps the brief confirmed');
reset role;
select ok((select count(*) = 1 and bool_and(carried_from_id = pg_temp.a('c1'))
  from public.brief_confirmations where assignment_id = pg_temp.a('p') and kind = 'carried_forward'),
  'and records a carried-forward row');
select pg_temp.as_user('63000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_save_brief(pg_temp.project('p'), '{"brief": {"instructions": "Cut it very well"},
  "change_summary": "Material", "requires_reacknowledgement": true}');
select ok((select reacknowledgement_required and not ready from public.get_assignment_gate(pg_temp.a('p'))),
  'a v3 with re-acknowledgement requires re-confirmation');
reset role;
select is(pg_temp.rows('p'), 2, 'nothing is carried to a re-acknowledgement version');
select pg_temp.as_user('63000000-0000-0000-0000-000000000001');
select lives_ok($$ select public.editor_confirm_brief(pg_temp.a('p'), 3, '2026-12-31', 10000, 'LKR') $$,
  'editor A confirms v3');
select ok((select brief_confirmed and confirmed_brief_version = 3 from public.get_assignment_gate(pg_temp.a('p'))),
  'the gate is clear again');
reset role;
select pg_temp.as_user('63000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_update_project(pg_temp.project('p'), '{"deadline": "2027-02-01"}');
select ok((select deadline_changed and not brief_confirmed from public.get_assignment_gate(pg_temp.a('p'))),
  'a moved deadline shows deadline_changed');
reset role;
select pg_temp.as_user('63000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_confirm_brief(pg_temp.a('p'), 3, '2026-12-31', 10000, 'LKR') $$, 'ES409',
  null, 'confirming with the old deadline is refused');
select lives_ok($$ select public.editor_confirm_brief(pg_temp.a('p'), 3, '2027-02-01', 10000, 'LKR') $$,
  'editor A re-confirms the same version with the new deadline');
select ok((select brief_confirmed and ready and not deadline_changed from public.get_assignment_gate(pg_temp.a('p'))),
  'the latest confirmation clears the drift');
reset role;
select is(pg_temp.rows('p'), 4, 'four rows: v1, carried v2, v3, v3 again');

-- Confirming during in_progress (after start) is allowed.
select pg_temp.as_user('63000000-0000-0000-0000-000000000001');
select public.editor_start_work(pg_temp.a('p'));
reset role;
select pg_temp.as_user('63000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_save_brief(pg_temp.project('p'), '{"brief": {"instructions": "Cut it again"},
  "change_summary": "Material after start", "requires_reacknowledgement": true}');
reset role;
select pg_temp.as_user('63000000-0000-0000-0000-000000000001');
select lives_ok($$ select public.editor_confirm_brief(pg_temp.a('p'), 4, '2027-02-01', 10000, 'LKR') $$,
  'an in_progress editor can confirm a new version');
reset role;
select is((select status::text from public.assignments where id = pg_temp.a('p')), 'in_progress',
  'the assignment stays in_progress');

-- ---------------------------------------------------------------------------
-- Interpretation first; states; deadline cleared (Review Focus 3)
-- ---------------------------------------------------------------------------
select pg_temp.as_user('63000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_confirm_brief(pg_temp.a('i'), 1, '2026-12-31', 10000, 'LKR') $$, 'ES409',
  'Your interpretation needs to be accepted first.', 'a required interpretation must be accepted first');
insert into ids select 'ii', public.editor_submit_interpretation(pg_temp.a('i'), 1, 'Keep it', null);
reset role;
select pg_temp.as_user('63000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_review_interpretation(pg_temp.a('ii'), 'accept');
reset role;
select pg_temp.as_user('63000000-0000-0000-0000-000000000001');
select lives_ok($$ select public.editor_confirm_brief(pg_temp.a('i'), 1, '2026-12-31', 10000, 'LKR') $$,
  'after acceptance the brief can be confirmed');
select throws_ok($$ select public.editor_confirm_brief(pg_temp.a('x'), 1, '2026-12-31', 10000, 'LKR') $$, 'ES409',
  null, 'an accepted (not confirmed) assignment cannot confirm the brief');
select throws_ok($$ select public.editor_confirm_brief(pg_temp.a('r'), 1, '2026-12-31', 10000, 'LKR') $$, 'ES409',
  null, 'an archived project cannot confirm the brief');
select lives_ok($$ select public.editor_confirm_brief(pg_temp.a('d'), 1, '2026-12-31', 10000, 'LKR') $$,
  'editor A confirms D');
reset role;
select pg_temp.as_user('63000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_update_project(pg_temp.project('d'), '{"deadline": null}');
select ok((select deadline_changed and not ready from public.get_assignment_gate(pg_temp.a('d'))),
  'a cleared deadline shows deadline_changed and is not ready');
reset role;
select pg_temp.as_user('63000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_confirm_brief(pg_temp.a('d'), 1, '2026-12-31', 10000, 'LKR') $$, 'ES409',
  'This project has no deadline yet.', 'a project without a deadline cannot be confirmed');
select throws_ok($$ select public.editor_confirm_brief(pg_temp.a('d'), 1, null, 10000, 'LKR') $$, 'ES409',
  'This project has no deadline yet.', 'even when the editor sends no deadline');
reset role;

-- ---------------------------------------------------------------------------
-- Other editors, roles, suspension (Review Focus 6, 7)
-- ---------------------------------------------------------------------------
select pg_temp.as_user('63000000-0000-0000-0000-000000000002');
select throws_ok($$ select public.editor_confirm_brief(pg_temp.a('d'), 1, '2026-12-31', 10000, 'LKR') $$, 'ES422',
  'Assignment not found.', 'editor B cannot confirm A''s brief');
select throws_ok($$ select public.editor_confirm_brief(gen_random_uuid(), 1, '2026-12-31', 10000, 'LKR') $$, 'ES422',
  'Assignment not found.', 'an unknown assignment gives the same message');
select is((select count(*)::int from public.brief_confirmations), 0, 'editor B sees none of A''s confirmations');
reset role;
select pg_temp.as_user('63000000-0000-0000-0000-000000000001');
select is((select count(*)::int from public.brief_confirmations), 7,
  'editor A sees their own confirmations');
reset role;
select pg_temp.as_anon();
select throws_ok($$ select public.editor_confirm_brief(gen_random_uuid(), 1, '2026-12-31', 10000, 'LKR') $$, 'ES401',
  null, 'anon cannot confirm');
reset role;
select pg_temp.as_user('63000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.editor_confirm_brief(pg_temp.a('d'), 1, '2026-12-31', 10000, 'LKR') $$, 'ES403',
  null, 'an admin cannot confirm as an editor');
reset role;
update public.editor_profiles set access_status = 'suspended' where user_id = '63000000-0000-0000-0000-000000000001';
select pg_temp.as_user('63000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_confirm_brief(pg_temp.a('d'), 1, '2026-12-31', 10000, 'LKR') $$, 'ES403',
  null, 'a suspended editor cannot confirm (Review Focus 7)');
select is((select count(*)::int from public.brief_confirmations), 0, 'a suspended editor sees no confirmations');
reset role;

-- ---------------------------------------------------------------------------
-- Audit hygiene and locking (Review Focus 11)
-- ---------------------------------------------------------------------------
select ok((select count(*) >= 5 and bool_and((select array_agg(k order by k) from jsonb_object_keys(details) k)
    = array['assignment_id', 'brief_version', 'carried_from_id', 'confirmation_id'])
  from public.activity_logs where action = 'brief_confirmation.confirmed'),
  'confirmation audit rows have exactly the id and version keys');
select is_empty($$ select id from public.activity_logs where action like 'brief_confirmation.%'
  and (details::text like '%10000%' or details::text like '%2026-12-31%' or details::text like '%2027-02-01%'
       or details::text like '%Main%') $$, 'confirmation audit rows hold no amount, deadline or deliverable');
select ok(pg_get_functiondef('private.lock_assignment(uuid)'::regprocedure) ~* 'for\s+update',
  'lock_assignment locks with for update');
select ok((select bool_and(prosrc ~ 'private\.lock_assignment') from pg_proc where oid in (
    'public.editor_confirm_brief(uuid, int, date, numeric, text)'::regprocedure,
    'public.editor_submit_interpretation(uuid, int, text, text, text)'::regprocedure,
    'public.admin_review_interpretation(uuid, text, text)'::regprocedure,
    'public.editor_start_work(uuid)'::regprocedure, 'public.admin_start_work(uuid)'::regprocedure)),
  'every Phase 7 workflow function locks project then assignment through lock_assignment');
select ok(pg_get_functiondef('public.admin_save_brief(uuid, jsonb)'::regprocedure) ~* 'for\s+update',
  'admin_save_brief locks the project row first as well');

select * from finish();

rollback;
