-- Phase 12A: admin_save_terms_draft, admin_agree_terms (versioning, race-safe agree, change
-- reason, editor-pay lock, day-count lock, cache), the confirm gate, editor_get_terms (tiered,
-- editor-safe) and admin_update_project no longer taking revision_allowance.
begin;

create extension if not exists pgtap with schema extensions;

select plan(49);

-- Phase 12C: work needs a verified client deposit (KB9b-4). Runs as the admin.
create function pg_temp.verify_deposit(p_project uuid) returns void language plpgsql as $$
declare
  v uuid;
begin
  perform public.admin_update_project(p_project, '{"client_price": 20000}');
  perform public.admin_create_client_milestones(p_project, '{100}');
  select id into v from public.client_milestones where project_id = p_project and kind = 'deposit' and voided_at is null;
  perform public.admin_record_client_payment(v, 'TEST-DEPOSIT');
  perform public.admin_verify_client_payment(v);
end;
$$;
grant execute on function pg_temp.verify_deposit(uuid) to authenticated;

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

-- Runs p_sql as an identity and returns 'ok' or the SQLSTATE, rolling the call back.
create function pg_temp.state_as(p_uid uuid, p_aal text, p_sql text)
returns text language plpgsql as $$
declare
  v text;
begin
  begin
    if p_uid is null then perform pg_temp.as_anon(); else perform pg_temp.as_user(p_uid, p_aal); end if;
    execute p_sql;
    raise exception 'rollback' using errcode = 'EST00';
  exception when others then
    v := case when sqlstate = 'EST00' then 'ok' else sqlstate end;
  end;
  reset role;
  return v;
end;
$$;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('94000000-0000-0000-0000-00000000000a', 'p12f-admin@test.local', '{}', '{}'),
  ('94000000-0000-0000-0000-000000000001', 'p12f-editor-a@test.local', '{}', '{}'),
  ('94000000-0000-0000-0000-000000000002', 'p12f-editor-b@test.local', '{}', '{}'),
  ('94000000-0000-0000-0000-000000000003', 'p12f-applicant@test.local', '{}', '{}');
select private.grant_admin_by_email('p12f-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('94000000-0000-0000-0000-000000000001', '94000000-0000-0000-0000-000000000002');

create temp table ids (kind text primary key, id uuid not null);
grant select, insert, update on ids to authenticated, anon;
create function pg_temp.a(p_kind text) returns uuid language sql as $$ select id from ids where kind = p_kind $$;
grant execute on function pg_temp.a(text) to authenticated, anon;
create function pg_temp.terms(p_version int) returns public.project_terms language sql as $$
  select * from public.project_terms where project_id = (select id from ids where kind = 'p') and version = p_version $$;

-- ---------------------------------------------------------------------------
-- Creation: v1 draft with the form's rounds
-- ---------------------------------------------------------------------------
select pg_temp.as_user('94000000-0000-0000-0000-00000000000a', 'aal2');
insert into ids select 'p', public.admin_create_project(jsonb_build_object('title', 'Terms flow', 'brief_type',
  'fully_instructed', 'deadline', '2099-12-31', 'revision_allowance', 0, 'brief', jsonb_build_object('instructions', 'Cut'),
  'deliverables', jsonb_build_array(jsonb_build_object('name', 'Main'))));
insert into ids select 'q', public.admin_create_project('{"title": "Default rounds", "brief_type": "creative_led"}');
reset role;

select ok((pg_temp.terms(1)).status = 'draft' and (pg_temp.terms(1)).included_rounds = 0,
  'the new project has draft terms v1 with the entered rounds (0)');
select is((select included_rounds::int from public.project_terms where project_id = pg_temp.a('q')), 3,
  'without an entry the rounds default to 3');

-- ---------------------------------------------------------------------------
-- Draft validation
-- ---------------------------------------------------------------------------
select is(pg_temp.state_as('94000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_save_terms_draft(pg_temp.a('p'), '{"included_rounds": 21}') $$), 'ES422', 'rounds above 20 are refused');
select is(pg_temp.state_as('94000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_save_terms_draft(pg_temp.a('p'), '{"deposit_days": 400}') $$), 'ES422', 'day counts above 365 are refused');
select is(pg_temp.state_as('94000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_save_terms_draft(pg_temp.a('p'), '{"editor_milestone_shares": [0, 100]}') $$), 'ES422',
  'a zero share is refused');
select is(pg_temp.state_as('94000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_save_terms_draft(pg_temp.a('p'), '{"stages": [{"stage": "assigned", "editor_earned_percent": 1,
     "client_charge_percent": 1}, {"stage": "assigned", "editor_earned_percent": 2, "client_charge_percent": 2}]}') $$),
  'ES422', 'a stage listed twice is refused');
select is(pg_temp.state_as('94000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_save_terms_draft(pg_temp.a('p'), '{"stages": [{"stage": "approved", "editor_earned_percent": 1,
     "client_charge_percent": 1}]}') $$), 'ES422', 'an unknown stage is refused');
select is(pg_temp.state_as('94000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_save_terms_draft(pg_temp.a('p'), '{"client_price": 5}') $$), 'ES422', 'unknown keys are refused');
select is(pg_temp.state_as('94000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_update_project(pg_temp.a('p'), '{"revision_allowance": 5}') $$), 'ES422',
  'admin_update_project no longer accepts revision_allowance');

-- ---------------------------------------------------------------------------
-- Save, agree, confirm gate
-- ---------------------------------------------------------------------------
select pg_temp.as_user('94000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_set_project_status(pg_temp.a('p'), 'open');
insert into ids select 'asg', public.admin_make_offer(pg_temp.a('p'), '94000000-0000-0000-0000-000000000001', 10000, 'LKR');
select is(public.admin_save_terms_draft(pg_temp.a('p'), '{"included_rounds": 2, "extra_round_charge": 7777,
  "charge_currency": "usd", "editor_milestone_shares": [60, 30],
  "stages": [{"stage": "assigned", "editor_earned_percent": 11, "client_charge_percent": 22},
             {"stage": "in_progress", "editor_earned_percent": 33, "client_charge_percent": 44}],
  "change_reason": "Secret reason rr"}'), (pg_temp.terms(1)).id, 'saving edits the existing draft (no new version)');
reset role;
select ok((pg_temp.terms(1)).included_rounds = 2 and (pg_temp.terms(1)).extra_round_charge = 7777
  and (pg_temp.terms(1)).charge_currency = 'USD' and (pg_temp.terms(1)).editor_milestone_shares = '{60,30}'
  and (select count(*) = 2 from public.project_terms_stages where terms_id = (pg_temp.terms(1)).id),
  'the draft holds the saved values and stages');
select is((select revision_allowance::int from public.projects where id = pg_temp.a('p')), 0,
  'saving a draft does not touch the revision allowance cache');

select pg_temp.as_user('94000000-0000-0000-0000-000000000001');
select public.editor_respond_offer(pg_temp.a('asg'), 'accept');
select pg_temp.as_user('94000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_confirm_assignment(pg_temp.a('asg')) $$, 'ES409', null,
  'an editor cannot be confirmed before the terms are agreed');
select throws_ok($$ select public.admin_agree_terms(pg_temp.a('p'), 1) $$, 'ES422', null,
  'terms whose editor shares do not add up to 100 cannot be agreed');
select public.admin_save_terms_draft(pg_temp.a('p'), '{"editor_milestone_shares": [50, 50]}');
select throws_ok($$ select public.admin_agree_terms(pg_temp.a('p'), 9) $$, 'ES422', null, 'an unknown version is not found');
select lives_ok($$ select public.admin_agree_terms(pg_temp.a('p'), 1) $$, 'admin agrees v1');
select throws_ok($$ select public.admin_agree_terms(pg_temp.a('p'), 1) $$, 'ES409', null,
  'agreeing the same version twice is refused (the second of two racing admins loses)');
reset role;
select ok((pg_temp.terms(1)).status = 'agreed' and (pg_temp.terms(1)).agreed_by = '94000000-0000-0000-0000-00000000000a'
  and (pg_temp.terms(1)).agreed_at is not null, 'v1 is agreed by the admin');
select is((select revision_allowance::int from public.projects where id = pg_temp.a('p')), 2,
  'agreeing writes the included rounds to the revision allowance cache');

-- editor_get_terms while editor A is at the opportunity stage
select pg_temp.as_user('94000000-0000-0000-0000-000000000001');
select ok((select included_rounds = 2 and editor_milestone_shares = '{50,50}' and version = 1
  and editor_kill_fee = '[{"stage": "assigned", "editor_earned_percent": 11.00},
                          {"stage": "in_progress", "editor_earned_percent": 33.00}]'::jsonb
  from public.editor_get_terms(pg_temp.a('p'))), 'editor A (offered) sees rounds, shares and editor kill-fee shares');
select ok((select to_jsonb(t)::text !~ '(7777|USD|client|reason)'
    and (select array_agg(k order by k) from jsonb_object_keys(to_jsonb(t)) k)
        = array['agreed_at', 'editor_kill_fee', 'editor_milestone_shares', 'included_rounds', 'version']
  from public.editor_get_terms(pg_temp.a('p')) t),
  'the editor view holds no client charge, currency, client percentages or reason');
reset role;
select is(pg_temp.state_as('94000000-0000-0000-0000-000000000002', 'aal1',
  $$ select * from public.editor_get_terms(pg_temp.a('p')) $$), 'ES422', 'editor B (no access) gets not found');
select is(pg_temp.state_as('94000000-0000-0000-0000-000000000003', 'aal1',
  $$ select * from public.editor_get_terms(pg_temp.a('p')) $$), 'ES403', 'a pending applicant is refused');
select is(pg_temp.state_as(null, 'aal1', $$ select * from public.editor_get_terms(pg_temp.a('p')) $$), 'ES401',
  'anon is refused');
select is(pg_temp.state_as('94000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select * from public.editor_get_terms(pg_temp.a('p')) $$), 'ES403', 'the admin uses the admin view instead');
select is(pg_temp.state_as('94000000-0000-0000-0000-000000000001', 'aal1',
  $$ select * from public.editor_get_terms(pg_temp.a('q')) $$), 'ES422', 'editor A cannot read another project''s terms');

select pg_temp.as_user('94000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok($$ select public.admin_confirm_assignment(pg_temp.a('asg')) $$, 'with agreed terms the editor is confirmed');

-- ---------------------------------------------------------------------------
-- New version while an editor is confirmed (not started)
-- ---------------------------------------------------------------------------
insert into ids select 'v2', public.admin_save_terms_draft(pg_temp.a('p'), '{"editor_milestone_shares": [40, 60]}');
reset role;
select ok((pg_temp.terms(2)).status = 'draft' and (pg_temp.terms(2)).included_rounds = 2
  and (pg_temp.terms(2)).extra_round_charge = 7777
  and (select count(*) = 2 from public.project_terms_stages where terms_id = (pg_temp.terms(2)).id),
  'saving after agreement starts v2 as a copy of v1, stages included');
select is((pg_temp.terms(1)).status::text, 'agreed', 'v1 stays agreed while v2 is a draft');
select pg_temp.as_user('94000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_agree_terms(pg_temp.a('p'), 2) $$, 'ES409', null,
  'editor milestone shares cannot change while an editor is confirmed');
select public.admin_save_terms_draft(pg_temp.a('p'), '{"editor_milestone_shares": [50, 50],
  "stages": [{"stage": "assigned", "editor_earned_percent": 12, "client_charge_percent": 22},
             {"stage": "in_progress", "editor_earned_percent": 33, "client_charge_percent": 44}]}');
select throws_ok($$ select public.admin_agree_terms(pg_temp.a('p'), 2) $$, 'ES409', null,
  'editor kill-fee shares cannot change while an editor is confirmed');
select public.admin_save_terms_draft(pg_temp.a('p'), '{"deposit_days": 10,
  "stages": [{"stage": "assigned", "editor_earned_percent": 11, "client_charge_percent": 25},
             {"stage": "in_progress", "editor_earned_percent": 33, "client_charge_percent": 44}]}');
select lives_ok($$ select public.admin_agree_terms(pg_temp.a('p'), 2) $$,
  'client-side and day-count changes before work begins need no reason');
reset role;
select ok((pg_temp.terms(1)).status = 'superseded' and (pg_temp.terms(1)).superseded_at is not null
  and (pg_temp.terms(2)).status = 'agreed' and (pg_temp.terms(2)).deposit_days = 10,
  'v1 is superseded and v2 agreed');

-- ---------------------------------------------------------------------------
-- After work begins
-- ---------------------------------------------------------------------------
select pg_temp.as_user('94000000-0000-0000-0000-00000000000a', 'aal2');
select pg_temp.verify_deposit(pg_temp.a('p'));
select pg_temp.as_user('94000000-0000-0000-0000-000000000001');
select public.editor_confirm_brief(pg_temp.a('asg'), 1, '2099-12-31', 10000, 'LKR');
select public.editor_start_work(pg_temp.a('asg'));
select pg_temp.as_user('94000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_save_terms_draft(pg_temp.a('p'), '{"included_rounds": 1}');
select throws_ok($$ select public.admin_agree_terms(pg_temp.a('p'), 3) $$, 'ES422', null,
  'a change after work begins needs a reason');
select public.admin_save_terms_draft(pg_temp.a('p'), '{"balance_days": 9}');
select throws_ok($$ select public.admin_agree_terms(pg_temp.a('p'), 3, 'Client asked') $$, 'ES409', null,
  'day counts cannot change after work begins');
select public.admin_save_terms_draft(pg_temp.a('p'), '{"balance_days": 7}');
select throws_ok($$ select public.admin_agree_terms(pg_temp.a('p'), 3, '   ') $$, 'ES422', null, 'a blank reason is no reason');
select lives_ok($$ select public.admin_agree_terms(pg_temp.a('p'), 3, 'Client asked qq') $$,
  'with a reason the client-side change is agreed');
reset role;
select ok((pg_temp.terms(3)).status = 'agreed' and (pg_temp.terms(3)).change_reason = 'Client asked qq'
  and (pg_temp.terms(2)).status = 'superseded', 'v3 records the reason; v2 is superseded');
select is((select revision_allowance::int from public.projects where id = pg_temp.a('p')), 1, 'the cache follows v3');
select is((select count(*)::int from public.project_terms where project_id = pg_temp.a('p') and status = 'agreed'), 1,
  'exactly one agreed version per project');
select pg_temp.as_user('94000000-0000-0000-0000-000000000001');
select ok((select count(*) = 1 and min(version) = 3 and min(included_rounds) = 1 from public.editor_get_terms(pg_temp.a('p'))),
  'the assigned editor sees only the agreed version');
reset role;

-- A stored draft reason is used when the agree call gives none.
select pg_temp.as_user('94000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_save_terms_draft(pg_temp.a('p'), '{"included_rounds": 2, "change_reason": "Stored reason"}');
select lives_ok($$ select public.admin_agree_terms(pg_temp.a('p'), 4) $$, 'the draft''s stored reason counts');
reset role;

-- Cancelled project
update public.projects set status = 'cancelled' where id = pg_temp.a('q');
select is(pg_temp.state_as('94000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_save_terms_draft(pg_temp.a('q'), '{"included_rounds": 1}') $$), 'ES409',
  'terms of a cancelled project cannot change');
select is(pg_temp.state_as('94000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_agree_terms(pg_temp.a('q'), 1) $$), 'ES409', 'nor be agreed');

-- ---------------------------------------------------------------------------
-- Audit hygiene and locking
-- ---------------------------------------------------------------------------
select set_eq($$ select distinct action from public.activity_logs where action like 'project_terms.%' $$,
  array['project_terms.draft_saved', 'project_terms.agreed'], 'saves and agreements are audited');
select is_empty($$ select id from public.activity_logs where action like 'project_terms.%'
  and details::text ~ '(7777|USD|Secret reason|Client asked|Stored reason|\m22\M|\m44\M)' $$,
  'audit rows hold no amounts, currencies, percentages or reasons');
select is_empty($$ select id from public.activity_logs where action like 'project_terms.%'
  and exists (select 1 from jsonb_object_keys(details) k
              where k not in ('project_id', 'terms_id', 'version', 'superseded_id', 'fields')) $$,
  'audit rows carry only ids, version and field names');
select ok(pg_get_functiondef('public.admin_agree_terms(uuid, integer, text)'::regprocedure) ~ 'lock_writable_project'
  and pg_get_functiondef('public.admin_agree_terms(uuid, integer, text)'::regprocedure) ~* 'for\s+update',
  'agree locks the project row and the terms rows');
select ok(pg_get_function_result('public.editor_get_terms(uuid)'::regprocedure) !~* '(charge|client|currency|reason)',
  'editor_get_terms returns no client columns');

select * from finish();
rollback;
