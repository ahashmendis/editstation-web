-- Open opportunities: schema, guards and RLS as admin, editor A, editor B, pending applicant,
-- suspended editor and anon. The editor-visible table holds no client column.
begin;

create extension if not exists pgtap with schema extensions;

select plan(37);

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

-- Counts visible rows of a table as a given identity (null = anon).
create function pg_temp.seen(p_uid uuid, p_aal text, p_table text)
returns int language plpgsql as $$
declare
  n int;
begin
  if p_uid is null then perform pg_temp.as_anon(); else perform pg_temp.as_user(p_uid, p_aal); end if;
  begin
    execute format('select count(*)::int from public.%I', p_table) into n;
  exception when insufficient_privilege then
    n := -1;
  end;
  reset role;
  return n;
end;
$$;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('c1000000-0000-0000-0000-00000000000a', 'opp-s-admin@test.local', '{}', '{}'),
  ('c1000000-0000-0000-0000-000000000001', 'opp-s-editor-a@test.local', '{}', '{}'),
  ('c1000000-0000-0000-0000-000000000002', 'opp-s-editor-b@test.local', '{}', '{}'),
  ('c1000000-0000-0000-0000-000000000003', 'opp-s-applicant@test.local', '{}', '{}'),
  ('c1000000-0000-0000-0000-000000000004', 'opp-s-suspended@test.local', '{}', '{}');
select private.grant_admin_by_email('opp-s-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('c1000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000002',
                  'c1000000-0000-0000-0000-000000000004');

insert into public.projects (id, title, brief_type, status, first_opened_at) values
  ('c1000000-0000-0000-0000-0000000000f1', 'ACMECLIENT launch film', 'fully_instructed', 'open', now());

-- ---------------------------------------------------------------------------
-- Catalogue
-- ---------------------------------------------------------------------------
select ok((select bool_and(relrowsecurity) from pg_class
           where oid in ('public.project_opportunities'::regclass, 'public.opportunity_interests'::regclass)),
  'RLS is on for both tables');
select ok(array['interest_registered', 'opportunity_selected', 'opportunity_not_selected']
          <@ enum_range(null::public.notification_kind)::text[], 'the three notification kinds exist');
select is_empty($$
  select t || ' ' || r || ' ' || p from
    unnest(array['public.project_opportunities', 'public.opportunity_interests']) t,
    unnest(array['anon', 'authenticated']) r,
    unnest(array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) p
  where has_table_privilege(r, t, p) $$,
  'no API role can write either table');
select ok(not has_table_privilege('anon', 'public.project_opportunities', 'SELECT')
          and not has_table_privilege('anon', 'public.opportunity_interests', 'SELECT'),
  'anon cannot read either table');
select set_eq($$ select column_name::text from information_schema.columns
                 where table_schema = 'public' and table_name = 'project_opportunities' $$,
  array['id', 'project_id', 'title', 'service_type_code', 'deliverables_summary', 'deadline', 'format_notes',
        'shown_pay_amount', 'shown_pay_currency', 'closes_at', 'status', 'close_reason', 'published_by',
        'published_at', 'closed_by', 'closed_at', 'updated_at'],
  'the editor-visible table has exactly the summary allow-list (no client column)');
select is_empty($$ select column_name from information_schema.columns
  where table_schema = 'public' and table_name in ('project_opportunities', 'opportunity_interests')
    and column_name ~ '(client|company|budget|price|email|phone|brief|asset|link|url|internal|inquiry)' $$,
  'no client, pricing, brief or link column on either table');
select ok(not has_table_privilege('authenticated', 'public.project_opportunities', 'SELECT')
          and not has_column_privilege('authenticated', 'public.project_opportunities', 'project_id', 'SELECT')
          and not has_column_privilege('authenticated', 'public.project_opportunities', 'published_by', 'SELECT')
          and not has_column_privilege('authenticated', 'public.project_opportunities', 'closed_by', 'SELECT'),
  'the API role cannot select project_id, published_by or closed_by (column-level grant)');
select ok(has_column_privilege('authenticated', 'public.project_opportunities', 'title', 'SELECT')
          and has_column_privilege('authenticated', 'public.project_opportunities', 'shown_pay_amount', 'SELECT'),
  'the summary columns stay readable');
select ok(exists (select 1 from pg_indexes where indexname = 'opportunity_interests_live_key'),
  'one live interest per editor per opportunity (partial unique index)');

-- ---------------------------------------------------------------------------
-- Fixtures through the functions
-- ---------------------------------------------------------------------------
select pg_temp.as_user('c1000000-0000-0000-0000-00000000000a', 'aal2');
create temp table ids (kind text primary key, id uuid not null);
grant all on ids to authenticated;
insert into ids values ('opp', public.admin_publish_opportunity('c1000000-0000-0000-0000-0000000000f1',
  'Promo edit, 60 seconds', 'One 60 s cut and a 15 s teaser'));
select pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
insert into ids values ('ia', public.editor_register_interest((select id from ids where kind = 'opp'), 30000, null, 'Keen'));
reset role;

-- ---------------------------------------------------------------------------
-- RLS reads
-- ---------------------------------------------------------------------------
select is(pg_temp.seen('c1000000-0000-0000-0000-00000000000a', 'aal2', 'project_opportunities'), 1, 'admin (MFA) reads the opportunity');
select is(pg_temp.seen('c1000000-0000-0000-0000-00000000000a', 'aal2', 'opportunity_interests'), 1, 'admin (MFA) reads every interest');
select is(pg_temp.seen('c1000000-0000-0000-0000-00000000000a', 'aal1', 'project_opportunities'), 0, 'admin without MFA reads nothing');
select is(pg_temp.seen('c1000000-0000-0000-0000-000000000001', 'aal1', 'project_opportunities'), 1, 'editor A reads the open opportunity');
select is(pg_temp.seen('c1000000-0000-0000-0000-000000000001', 'aal1', 'opportunity_interests'), 1, 'editor A reads their own interest');
select is(pg_temp.seen('c1000000-0000-0000-0000-000000000002', 'aal1', 'project_opportunities'), 1, 'editor B reads the open opportunity');
select is(pg_temp.seen('c1000000-0000-0000-0000-000000000002', 'aal1', 'opportunity_interests'), 0, 'editor B cannot read editor A''s interest');
select is(pg_temp.seen('c1000000-0000-0000-0000-000000000003', 'aal1', 'project_opportunities'), 0, 'a pending applicant reads no opportunity');
select is(pg_temp.seen('c1000000-0000-0000-0000-000000000003', 'aal1', 'opportunity_interests'), 0, 'a pending applicant reads no interest');
select is(pg_temp.seen('c1000000-0000-0000-0000-000000000004', 'aal1', 'opportunity_interests'), 0,
  'another active editor without an interest reads no interest');

-- Editor B registers too; A still reads only their own row.
select pg_temp.as_user('c1000000-0000-0000-0000-000000000002');
insert into ids values ('ib', public.editor_register_interest((select id from ids where kind = 'opp')));
reset role;
select is(pg_temp.seen('c1000000-0000-0000-0000-000000000001', 'aal1', 'opportunity_interests'), 1, 'editor A still reads only their own interest');
select pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
select is((select editor_id from public.opportunity_interests), 'c1000000-0000-0000-0000-000000000001'::uuid,
  'and that row is editor A''s');
select is((select title from public.project_opportunities), 'Promo edit, 60 seconds',
  'an editor selects the summary columns directly');
reset role;

-- Suspending editor A: their own rows disappear too.
update public.editor_profiles set access_status = 'suspended' where user_id = 'c1000000-0000-0000-0000-000000000001';
select is(pg_temp.seen('c1000000-0000-0000-0000-000000000001', 'aal1', 'project_opportunities'), 0, 'a suspended editor reads no opportunity');
select is(pg_temp.seen('c1000000-0000-0000-0000-000000000001', 'aal1', 'opportunity_interests'), 0, 'a suspended editor reads no interest');
update public.editor_profiles set access_status = 'active' where user_id = 'c1000000-0000-0000-0000-000000000001';

-- On hold hides it from editors without an interest; editors with one still see it.
update public.projects set status = 'on_hold', status_before_hold = 'open' where id = 'c1000000-0000-0000-0000-0000000000f1';
select is(pg_temp.seen('c1000000-0000-0000-0000-000000000004', 'aal1', 'project_opportunities'), 0,
  'an opportunity on a project on hold is hidden from editors without an interest');
select is(pg_temp.seen('c1000000-0000-0000-0000-000000000001', 'aal1', 'project_opportunities'), 1,
  'an editor with an interest still sees it');
update public.projects set status = 'open', status_before_hold = null where id = 'c1000000-0000-0000-0000-0000000000f1';

-- A passed closing date hides it from editors without an interest.
update public.project_opportunities set closes_at = now() - interval '1 minute' where id = (select id from ids where kind = 'opp');
select is(pg_temp.seen('c1000000-0000-0000-0000-000000000004', 'aal1', 'project_opportunities'), 0,
  'an opportunity past its closing date is hidden from editors without an interest');
update public.project_opportunities set closes_at = null where id = (select id from ids where kind = 'opp');

-- ---------------------------------------------------------------------------
-- Guards (as the table owner)
-- ---------------------------------------------------------------------------
select throws_ok($$ update public.opportunity_interests set proposed_amount = 1 where id = (select id from ids where kind = 'ia') $$,
  'ES409', 'Interest history cannot be changed.', 'interest content cannot change');
select throws_ok($$ update public.opportunity_interests set status = 'interested', decided_at = null
  where id = (select id from ids where kind = 'ia') $$,
  'ES409', 'Interest history cannot be changed.', 'an interest cannot move to interested');
select throws_ok($$ delete from public.opportunity_interests where id = (select id from ids where kind = 'ia') $$,
  'ES409', 'Interest history cannot be deleted.', 'interests cannot be deleted');
select throws_ok($$ insert into public.opportunity_interests (opportunity_id, editor_id, status, decided_at)
  values ((select id from ids where kind = 'opp'), 'c1000000-0000-0000-0000-000000000004', 'selected', now()) $$,
  'ES409', 'A new interest starts as interested.', 'a new interest starts as interested');
select throws_ok($$ insert into public.opportunity_interests (opportunity_id, editor_id)
  values ((select id from ids where kind = 'opp'), 'c1000000-0000-0000-0000-000000000001') $$,
  '23505', null, 'a second live interest for the same editor is refused');
select throws_ok($$ delete from public.project_opportunities where id = (select id from ids where kind = 'opp') $$,
  'ES409', 'An opportunity cannot be deleted. Close it instead.', 'opportunities cannot be deleted');
select throws_ok($$ update public.project_opportunities set project_id = gen_random_uuid() where id = (select id from ids where kind = 'opp') $$,
  'ES409', 'An opportunity cannot move to another project.', 'an opportunity cannot move project');
select throws_ok($$ update public.project_opportunities set status = 'closed' where id = (select id from ids where kind = 'opp') $$,
  '23514', null, 'a closed opportunity needs closed_at and a reason');

-- Deleting the project (cascade) removes its opportunity and interests.
delete from public.projects where id = 'c1000000-0000-0000-0000-0000000000f1';
select is((select count(*)::int from public.opportunity_interests), 0, 'the cascade from the project removes the interests');
select is((select count(*)::int from public.project_opportunities), 0, 'and the opportunity');

select * from finish();
rollback;
