-- Phase 7: Phase 6 and Phase 4 functions with in_progress. Withdraw, revoke and re-offer are
-- refused; reassign and cancel work from in_progress; the revoke checklist; a fresh assignment
-- after reassignment needs its own interpretation and confirmation (Review Focus 12).
begin;

create extension if not exists pgtap with schema extensions;

select plan(25);

create function pg_temp.as_user(p_uid uuid, p_aal text default 'aal1')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;
grant execute on function pg_temp.as_user(uuid, text) to authenticated;

-- Confirmed assignment on a new project; with p_start the editor (after the interpretation,
-- when required) confirms the brief and starts work.
create function pg_temp.assignment(p_title text, p_editor uuid, p_interp boolean, p_start boolean)
returns uuid language plpgsql as $$
declare
  v_project uuid;
  v_id uuid;
  v_interp uuid;
begin
  perform pg_temp.as_user('65000000-0000-0000-0000-00000000000a', 'aal2');
  v_project := public.admin_create_project(jsonb_build_object('title', p_title, 'brief_type', 'fully_instructed',
    'deadline', '2026-12-31', 'requires_interpretation', p_interp, 'brief', jsonb_build_object('instructions', 'Cut it'),
    'deliverables', jsonb_build_array(jsonb_build_object('name', 'Main'))));
  perform public.admin_set_project_status(v_project, 'open');
  perform public.admin_agree_terms(v_project, 1);
  v_id := public.admin_make_offer(v_project, p_editor, 10000, 'LKR');
  perform pg_temp.as_user(p_editor);
  perform public.editor_respond_offer(v_id, 'accept');
  perform pg_temp.as_user('65000000-0000-0000-0000-00000000000a', 'aal2');
  perform public.admin_confirm_assignment(v_id);
  if p_start then
    if p_interp then
      perform pg_temp.as_user(p_editor);
      v_interp := public.editor_submit_interpretation(v_id, 1, 'Keep the pacing', null);
      perform pg_temp.as_user('65000000-0000-0000-0000-00000000000a', 'aal2');
      perform public.admin_review_interpretation(v_interp, 'accept');
    end if;
    perform pg_temp.as_user(p_editor);
    perform public.editor_confirm_brief(v_id, 1, '2026-12-31', 10000, 'LKR');
    perform public.editor_start_work(v_id);
  end if;
  reset role;
  return v_id;
end;
$$;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('65000000-0000-0000-0000-00000000000a', 'p7r-admin@test.local', '{}', '{}'),
  ('65000000-0000-0000-0000-000000000001', 'p7r-editor-a@test.local', '{}', '{}'),
  ('65000000-0000-0000-0000-000000000002', 'p7r-editor-b@test.local', '{}', '{}');
select private.grant_admin_by_email('p7r-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('65000000-0000-0000-0000-000000000001', '65000000-0000-0000-0000-000000000002');

create temp table ids (kind text primary key, id uuid not null);
grant select, insert on ids to authenticated;
create function pg_temp.a(p_kind text) returns uuid language sql as $$ select id from ids where kind = p_kind $$;
grant execute on function pg_temp.a(text) to authenticated;
create function pg_temp.project(p_kind text) returns uuid language sql as $$
  select project_id from public.assignments where id = (select id from ids where kind = p_kind) $$;
grant execute on function pg_temp.project(text) to authenticated;

insert into ids select 'p', pg_temp.assignment('P', '65000000-0000-0000-0000-000000000001', true, true);
insert into ids select 'c', pg_temp.assignment('C', '65000000-0000-0000-0000-000000000001', false, true);
insert into ids select 'e', pg_temp.assignment('E', '65000000-0000-0000-0000-000000000001', false, true);
insert into ids select 'g', (select gen_random_uuid());
insert into public.asset_access_grants (id, project_id, editor_id, shared_with_email, provider)
values (pg_temp.a('g'), pg_temp.project('p'), '65000000-0000-0000-0000-000000000001', 'a@drive.example.com',
        'google_drive');
-- An open project with A in_progress (seeded) for the live-offer check.
insert into public.projects (id, title, brief_type, status, first_opened_at) values
  ('65000000-0000-0000-0000-0000000000f9', 'Seeded open', 'fully_instructed', 'open', now());
-- Phase 12A: an editor is confirmed only after the project terms are agreed.
update public.project_terms set status = 'agreed', agreed_at = now() where status = 'draft';
insert into public.assignments (project_id, editor_id, status, proposed_amount, agreed_amount, agreed_currency,
  confirmed_at, started_at) values
  ('65000000-0000-0000-0000-0000000000f9', '65000000-0000-0000-0000-000000000001', 'in_progress', 1000, 1000, 'LKR',
   now(), now());

create temp table before_rows as
select (select count(*) from public.editor_interpretations where assignment_id = pg_temp.a('p')) as interps,
       (select count(*) from public.brief_confirmations where assignment_id = pg_temp.a('p')) as confirmations;

select is((select status::text from public.assignments where id = pg_temp.a('p')), 'in_progress', 'P is in_progress');

-- ---------------------------------------------------------------------------
-- Refused while in_progress
-- ---------------------------------------------------------------------------
select pg_temp.as_user('65000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_withdraw_offer(pg_temp.a('p')) $$, 'ES409',
  'This editor is confirmed. Use reassign instead.', 'an in_progress assignment cannot be withdrawn');
select throws_ok($$ select public.admin_revoke_project_access(pg_temp.project('p'), '65000000-0000-0000-0000-000000000001') $$,
  'ES409', 'This editor is confirmed on the project. Use reassign instead.',
  'an in_progress editor''s access cannot be revoked');
select throws_ok($$ select public.admin_make_offer(pg_temp.project('p'), '65000000-0000-0000-0000-000000000001', 5000) $$,
  'ES409', null, 'no offer on an in_progress project');
select throws_ok($$ select public.admin_make_offer('65000000-0000-0000-0000-0000000000f9',
  '65000000-0000-0000-0000-000000000001', 5000) $$, 'ES409', 'This editor already has a live offer on this project.',
  'an in_progress assignment counts as live for new offers');
select is_empty($$ select grant_id from public.admin_pending_revocations() where grant_id = pg_temp.a('g') $$,
  'a folder share of an in_progress editor is not on the checklist');
select throws_ok($$ select public.admin_set_project_status(pg_temp.project('e'), 'on_hold') $$, 'ES409', null,
  'an in_progress project cannot go on hold');

-- ---------------------------------------------------------------------------
-- Reassign from in_progress
-- ---------------------------------------------------------------------------
select lives_ok($$ select public.admin_reassign(pg_temp.a('p'), 'Editor unavailable') $$,
  'admin reassigns an in_progress editor');
select ok((select reason = 'no_active_assignment' from public.admin_pending_revocations() where grant_id = pg_temp.a('g')),
  'after reassignment the folder share is listed as no_active_assignment');
reset role;
select ok((select status = 'reassigned' and closed_at is not null from public.assignments where id = pg_temp.a('p')),
  'the assignment is reassigned and closed');
select ok(exists (select 1 from public.negotiation_offers where assignment_id = pg_temp.a('p') and from_role = 'admin'
  and action = 'withdraw' and message = 'Editor unavailable'), 'the reason is stored as an admin withdraw row');
select is((select status::text from public.projects where id = pg_temp.project('p')), 'open', 'the project is open again');
select is((select count(*)::int from public.project_access where project_id = pg_temp.project('p')
  and editor_id = '65000000-0000-0000-0000-000000000001' and revoked_at is null), 0, 'A''s access is revoked');
select ok((select count(*) from public.editor_interpretations where assignment_id = pg_temp.a('p')) = (select interps from before_rows)
  and (select count(*) from public.brief_confirmations where assignment_id = pg_temp.a('p')) = (select confirmations from before_rows)
  and (select interps from before_rows) = 1 and (select confirmations from before_rows) = 1,
  'A''s interpretation and confirmation rows are unchanged');
select pg_temp.as_user('65000000-0000-0000-0000-000000000001');
select is(private.editor_project_stage(pg_temp.project('p')), 'none', 'A has no stage on the project any more');
reset role;
select pg_temp.as_user('65000000-0000-0000-0000-00000000000a', 'aal2');
select is((select count(*)::int from public.brief_confirmations where assignment_id = pg_temp.a('p')), 1,
  'admin still reads A''s confirmation history');

-- Review Focus 12: a fresh assignment needs its own interpretation and confirmation.
insert into ids select 'p2', public.admin_make_offer(pg_temp.project('p'), '65000000-0000-0000-0000-000000000001', 11000);
reset role;
select pg_temp.as_user('65000000-0000-0000-0000-000000000001');
select public.editor_respond_offer(pg_temp.a('p2'), 'accept');
reset role;
select pg_temp.as_user('65000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_confirm_assignment(pg_temp.a('p2'));
select is((select row(confirmed_brief_version, reacknowledgement_required, interpretation_accepted, ready)::text
  from public.get_assignment_gate(pg_temp.a('p2'))), '(,t,f,f)',
  'the new assignment has no confirmation and no accepted interpretation');
reset role;
select ok(pg_temp.a('p2') <> pg_temp.a('p'), 'the re-offer is a new assignment row');

-- ---------------------------------------------------------------------------
-- Cancel from in_progress
-- ---------------------------------------------------------------------------
select pg_temp.as_user('65000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok($$ select public.admin_set_project_status(pg_temp.project('c'), 'cancelled') $$,
  'an in_progress project can be cancelled');
reset role;
select is((select status::text from public.projects where id = pg_temp.project('c')), 'cancelled', 'the project is cancelled');
select ok((select status = 'withdrawn' and closed_at is not null from public.assignments where id = pg_temp.a('c')),
  'the in_progress assignment is withdrawn');
select ok(exists (select 1 from public.negotiation_offers where assignment_id = pg_temp.a('c') and from_role = 'admin'
  and action = 'withdraw'), 'with an admin withdraw row');
select is((select count(*)::int from public.project_access where project_id = pg_temp.project('c') and revoked_at is null),
  0, 'and every live access row is revoked');
select ok((select bool_and(private.project_transition_allowed('in_progress', t, null) = (t = 'cancelled'))
  from unnest(enum_range(null::public.project_status)) t), 'in_progress may move only to cancelled through the table');
select ok(private.close_live_assignments(pg_temp.project('e'), 'not_selected', null) = 0,
  'closing as not_selected never touches the in_progress editor');

select * from finish();

rollback;
