-- Phase 12A: project_terms / project_terms_stages schema, admin-only RLS as every identity, guard
-- triggers (immutability of agreed rows, append-only versions), the initial-terms trigger and the
-- revision_allowance cache guard.
begin;

create extension if not exists pgtap with schema extensions;

select plan(34);

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

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('93000000-0000-0000-0000-00000000000a', 'p12s-admin@test.local', '{}', '{}'),
  ('93000000-0000-0000-0000-000000000001', 'p12s-editor-a@test.local', '{}', '{}'),
  ('93000000-0000-0000-0000-000000000002', 'p12s-editor-b@test.local', '{}', '{}'),
  ('93000000-0000-0000-0000-000000000003', 'p12s-applicant@test.local', '{}', '{}');
select private.grant_admin_by_email('p12s-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('93000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000002');

-- Editor A is confirmed on P1 (assigned stage), so RLS is tested against an editor who can see it.
insert into public.projects (id, title, brief_type, status, first_opened_at, revision_allowance) values
  ('93000000-0000-0000-0000-0000000000f1', 'Terms P1', 'fully_instructed', 'assigned', now(), 2);
insert into public.assignments (project_id, editor_id, status, proposed_amount, agreed_amount, agreed_currency,
  confirmed_at)
values ('93000000-0000-0000-0000-0000000000f1', '93000000-0000-0000-0000-000000000001', 'confirmed', 1000, 1000,
  'LKR', now());

-- ---------------------------------------------------------------------------
-- Structure
-- ---------------------------------------------------------------------------
select has_table('public', 'project_terms', 'project_terms exists');
select has_table('public', 'project_terms_stages', 'project_terms_stages exists');
select ok((select relrowsecurity from pg_class where oid = 'public.project_terms'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.project_terms_stages'::regclass), 'RLS is on');
select is_empty($$ select privilege_type from information_schema.role_table_grants
  where table_schema = 'public' and table_name in ('project_terms', 'project_terms_stages')
    and grantee in ('anon', 'authenticated') and privilege_type <> 'SELECT' $$,
  'no write grants for anon or authenticated');
select ok(not has_table_privilege('anon', 'public.project_terms', 'select'), 'anon has no select grant');

-- ---------------------------------------------------------------------------
-- Initial terms (trigger) and defaults
-- ---------------------------------------------------------------------------
select is((select count(*)::int from public.project_terms where project_id = '93000000-0000-0000-0000-0000000000f1'),
  1, 'a new project gets terms v1');
select ok((select version = 1 and status = 'draft' and included_rounds = 2 and deposit_days = 14 and balance_days = 7
  and editor_pay_days = 7 and late_balance_days = 14 and editor_milestone_shares = '{50,50}'
  and extra_round_charge is null and charge_currency is null
  from public.project_terms where project_id = '93000000-0000-0000-0000-0000000000f1'),
  'v1 is a draft with the project''s rounds, owner day counts, 50/50 shares and no charge');
select is((select count(*)::int from public.project_terms_stages s join public.project_terms t on t.id = s.terms_id
  where t.project_id = '93000000-0000-0000-0000-0000000000f1'), 0, 'no default cancellation stages');

-- ---------------------------------------------------------------------------
-- Guards
-- ---------------------------------------------------------------------------
select throws_ok($$ insert into public.project_terms (project_id, version) values ('93000000-0000-0000-0000-0000000000f1', 5) $$,
  'ES409', null, 'a version must be the next one');
select throws_ok($$ insert into public.project_terms (project_id, version, status, agreed_at, editor_milestone_shares)
  values ('93000000-0000-0000-0000-0000000000f1', 2, 'agreed', now(), '{60,30}') $$,
  '23514', null, 'agreed terms need shares adding up to 100');
select lives_ok($$ insert into public.project_terms_stages (terms_id, stage, editor_earned_percent, client_charge_percent)
  select id, 'assigned', 10, 20 from public.project_terms where project_id = '93000000-0000-0000-0000-0000000000f1' $$,
  'a draft can get stage rows');
select throws_ok($$ insert into public.project_terms_stages (terms_id, stage, editor_earned_percent, client_charge_percent)
  select id, 'in_review', 101, 0 from public.project_terms where project_id = '93000000-0000-0000-0000-0000000000f1' $$,
  '23514', null, 'percentages are capped at 100');
select lives_ok($$ update public.project_terms set status = 'agreed', agreed_at = now()
  where project_id = '93000000-0000-0000-0000-0000000000f1' $$, 'a draft can become agreed');
select throws_ok($$ update public.project_terms set included_rounds = 5
  where project_id = '93000000-0000-0000-0000-0000000000f1' $$, 'ES409', null, 'agreed terms cannot be edited');
select throws_ok($$ update public.project_terms set status = 'draft', agreed_at = null
  where project_id = '93000000-0000-0000-0000-0000000000f1' $$, 'ES409', null, 'agreed terms cannot return to draft');
select throws_ok($$ update public.project_terms set status = 'superseded', superseded_at = now(), deposit_days = 1
  where project_id = '93000000-0000-0000-0000-0000000000f1' $$, 'ES409', null,
  'superseding cannot change content at the same time');
select throws_ok($$ update public.project_terms_stages set editor_earned_percent = 50 $$,
  'ES409', null, 'stages of agreed terms cannot change');
select throws_ok($$ delete from public.project_terms_stages $$, 'ES409', null, 'stages of agreed terms cannot be deleted');
select throws_ok($$ delete from public.project_terms where project_id = '93000000-0000-0000-0000-0000000000f1' $$,
  'ES409', null, 'terms cannot be deleted');
select lives_ok($$ update public.project_terms set status = 'superseded', superseded_at = now()
  where project_id = '93000000-0000-0000-0000-0000000000f1' $$, 'agreed terms can be superseded');
select throws_ok($$ update public.project_terms set status = 'agreed', superseded_at = null
  where project_id = '93000000-0000-0000-0000-0000000000f1' $$, 'ES409', null, 'superseded terms are frozen');

-- revision_allowance cache
select throws_ok($$ update public.projects set revision_allowance = 7 where id = '93000000-0000-0000-0000-0000000000f1' $$,
  'ES409', null, 'revision_allowance cannot be edited directly');
insert into public.project_terms (project_id, version, status, included_rounds, agreed_at)
values ('93000000-0000-0000-0000-0000000000f1', 2, 'agreed', 7, now());
select lives_ok($$ update public.projects set revision_allowance = 7 where id = '93000000-0000-0000-0000-0000000000f1' $$,
  'revision_allowance may follow the agreed included rounds');
select lives_ok($$ update public.projects set title = 'Terms P1 renamed' where id = '93000000-0000-0000-0000-0000000000f1' $$,
  'other project edits are unaffected');

-- ---------------------------------------------------------------------------
-- RLS as every identity
-- ---------------------------------------------------------------------------
select pg_temp.as_user('93000000-0000-0000-0000-00000000000a', 'aal2');
select is((select count(*)::int from public.project_terms where project_id = '93000000-0000-0000-0000-0000000000f1'),
  2, 'admin (aal2) reads terms');
select is((select count(*)::int from public.project_terms_stages), 1, 'admin reads stages');
select throws_ok($$ update public.project_terms set included_rounds = 1 $$, '42501', null, 'admin cannot write terms directly');
select pg_temp.as_user('93000000-0000-0000-0000-00000000000a', 'aal1');
select is((select count(*)::int from public.project_terms), 0, 'admin without MFA reads nothing');
select pg_temp.as_user('93000000-0000-0000-0000-000000000001');
select is((select count(*)::int from public.project_terms), 0, 'the confirmed editor A reads no terms table rows');
select is((select count(*)::int from public.project_terms_stages), 0, 'editor A reads no stage rows');
select pg_temp.as_user('93000000-0000-0000-0000-000000000002');
select is((select count(*)::int from public.project_terms), 0, 'editor B reads nothing');
select pg_temp.as_user('93000000-0000-0000-0000-000000000003');
select is((select count(*)::int from public.project_terms), 0, 'a pending applicant reads nothing');
select pg_temp.as_anon();
select throws_ok($$ select count(*) from public.project_terms $$, '42501', null, 'anon cannot read terms');
reset role;

select ok(not exists (select 1 from information_schema.columns where table_schema = 'public'
  and table_name in ('projects', 'assignments', 'brief_versions', 'payments')
  and column_name in ('extra_round_charge', 'client_charge_percent')), 'client charges live only in admin-only tables');

select * from finish();
rollback;
