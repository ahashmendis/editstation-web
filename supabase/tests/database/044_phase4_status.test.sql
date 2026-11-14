-- Phase 4: project details, status transitions (spec §10) and archive. Review Focus 5.
begin;

create extension if not exists pgtap with schema extensions;

select plan(57);

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
  ('44000000-0000-0000-0000-00000000000a', 'p4t-admin@test.local', '{}', '{}'),
  ('44000000-0000-0000-0000-000000000001', 'p4t-editor-a@test.local', '{}', '{}'),
  ('44000000-0000-0000-0000-000000000002', 'p4t-editor-b@test.local', '{}', '{}'),
  ('44000000-0000-0000-0000-000000000003', 'p4t-applicant@test.local', '{}', '{}');
select private.grant_admin_by_email('p4t-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('44000000-0000-0000-0000-000000000001', '44000000-0000-0000-0000-000000000002');

insert into public.clients (id, name, email) values
  ('44000000-0000-0000-0000-0000000000c1', 'Client One', 'one@example.com');
insert into public.clients (id, name, email, archived_at) values
  ('44000000-0000-0000-0000-0000000000c2', 'Archived', 'arch@example.com', now());

-- Every (from, to) status pair, each on its own ready-to-open project.
create temp table matrix as
select f.s as from_s, t.s as to_s, gen_random_uuid() as id
from unnest(enum_range(null::public.project_status)) f(s),
     unnest(enum_range(null::public.project_status)) t(s);
insert into public.projects (id, title, brief_type, deadline, status, status_before_hold, first_opened_at)
select id, 'Matrix', 'fully_instructed', '2026-12-31', from_s,
  case when from_s = 'on_hold' then 'draft'::public.project_status end,
  case when from_s <> 'draft' then now() end
from matrix;
insert into public.brief_versions (project_id, version, instructions) select id, 1, 'Do it' from matrix;
insert into public.project_deliverables (project_id, name) select id, 'Edit' from matrix;
grant select on matrix to authenticated;

create function pg_temp.try_matrix()
returns text[] language plpgsql as $$
declare
  r record;
  v_ok text[] := '{}';
begin
  for r in select * from matrix loop
    begin
      perform public.admin_set_project_status(r.id, r.to_s);
      v_ok := v_ok || (r.from_s || '>' || r.to_s);
    exception
      when sqlstate 'ES409' then null;
    end;
  end loop;
  return v_ok;
end;
$$;

create temp table p (kind text primary key, id uuid not null);
grant select, insert on p to authenticated, anon;

select pg_temp.as_user('44000000-0000-0000-0000-00000000000a', 'aal2');
insert into p select 'ready', public.admin_create_project('{
  "title": "Ready", "brief_type": "fully_instructed", "deadline": "2026-12-31",
  "brief": {"instructions": "Cut it"}, "deliverables": [{"name": "Main"}]}'::jsonb);
insert into p select 'fi_empty', public.admin_create_project('{"title": "FI", "brief_type": "fully_instructed"}'::jsonb);
insert into p select 'rb', public.admin_create_project('{"title": "RB", "brief_type": "reference_based",
  "deadline": "2026-12-31", "deliverables": [{"name": "Main"}]}'::jsonb);
insert into p select 'cl', public.admin_create_project('{"title": "CL", "brief_type": "creative_led",
  "deadline": "2026-12-31", "deliverables": [{"name": "Main"}]}'::jsonb);
insert into p select 'pre', public.admin_create_project('{
  "title": "Preopened", "brief_type": "fully_instructed", "deadline": "2026-12-31",
  "brief": {"instructions": "Cut it"}, "deliverables": [{"name": "Main"}]}'::jsonb);
insert into p select 'arch', public.admin_create_project('{
  "title": "To archive", "brief_type": "creative_led", "brief": {"desired_outcome": "Joy"}}'::jsonb);
reset role;

-- ---------------------------------------------------------------------------
-- Transition table
-- ---------------------------------------------------------------------------
select pg_temp.as_user('44000000-0000-0000-0000-00000000000a', 'aal2');
select is(
  (select array_agg(x order by x collate "C") from unnest(pg_temp.try_matrix()) x),
  array['assigned>cancelled', 'draft>cancelled', 'draft>on_hold', 'draft>open', 'in_progress>cancelled', 'on_hold>draft',
        'open>cancelled', 'open>draft', 'open>on_hold'],
  'exactly the allowed transitions succeed over every status pair');
reset role;

select ok((select bool_and(m.to_s = p.status) from matrix m join public.projects p on p.id = m.id
  where m.from_s || '>' || m.to_s in ('draft>open', 'open>draft', 'draft>cancelled', 'open>on_hold')),
  'allowed transitions set the new status');
select is((select status_before_hold from public.projects p join matrix m on m.id = p.id
  where m.from_s = 'open' and m.to_s = 'on_hold'), 'open'::public.project_status,
  'putting a project on hold stores the previous status');
select ok((select bool_and(p.status = m.from_s) from matrix m join public.projects p on p.id = m.id
  where m.from_s || '>' || m.to_s not in ('draft>open', 'draft>cancelled', 'draft>on_hold', 'open>draft',
    'open>cancelled', 'open>on_hold', 'on_hold>draft', 'assigned>cancelled', 'in_progress>cancelled')),
  'refused transitions leave the status unchanged');

-- ---------------------------------------------------------------------------
-- Opening, hold and resume
-- ---------------------------------------------------------------------------
select pg_temp.as_user('44000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok($$ select public.admin_set_project_status((select id from p where kind = 'ready'), 'open', 'Ready to go') $$,
  'a ready project can be opened');
select ok((select first_opened_at is not null from public.projects where id = (select id from p where kind = 'ready')),
  'opening sets first_opened_at');
select lives_ok($$ select public.admin_set_project_status((select id from p where kind = 'ready'), 'on_hold') $$,
  'an open project can be put on hold');
select throws_ok($$ select public.admin_set_project_status((select id from p where kind = 'ready'), 'draft') $$,
  'ES409', null, 'an on-hold project resumes only to its previous status');
select lives_ok($$ select public.admin_set_project_status((select id from p where kind = 'ready'), 'open') $$,
  'an on-hold project resumes to its previous status');
select ok((select status = 'open' and status_before_hold is null from public.projects
  where id = (select id from p where kind = 'ready')), 'resume restores open and clears status_before_hold');
select lives_ok($$ select public.admin_set_project_status((select id from p where kind = 'ready'), 'draft') $$,
  'an open project can go back to draft');
select lives_ok($$ select public.admin_set_project_status((select id from p where kind = 'ready'), 'open') $$,
  'and be opened again');
select throws_ok($$ select public.admin_set_project_status((select id from p where kind = 'ready'), 'assigned') $$,
  'ES409', null, 'moving to assigned is refused in Phase 4');
select throws_ok($$ select public.admin_set_project_status((select id from p where kind = 'ready'), null) $$,
  'ES422', null, 'a missing status is refused');
select throws_ok($$ select public.admin_set_project_status('44000000-0000-0000-0000-0000000000ff', 'open') $$,
  'ES422', null, 'an unknown project is refused');

-- Readiness, named per brief type.
select throws_ok($$ select public.admin_set_project_status((select id from p where kind = 'fi_empty'), 'open') $$,
  'ES422', 'Before opening this project, add at least one deliverable, a deadline, instructions.',
  'a fully instructed project needs deliverables, a deadline and instructions');
select throws_ok($$ select public.admin_set_project_status((select id from p where kind = 'rb'), 'open') $$,
  'ES422', 'Before opening this project, add at least one reference.',
  'a reference-based project needs a reference');
select throws_ok($$ select public.admin_set_project_status((select id from p where kind = 'cl'), 'open') $$,
  'ES422', 'Before opening this project, add a desired outcome.',
  'a creative-led project needs a desired outcome');
select is((select status from public.projects where id = (select id from p where kind = 'rb')),
  'draft'::public.project_status, 'a refused opening leaves the project in draft');
select lives_ok($$ select public.admin_set_project_status((select id from p where kind = 'rb'), 'on_hold') $$,
  'a draft project that is not ready can still be put on hold');
reset role;

-- first_opened_at is set once and survives open -> draft -> open.
update public.projects set first_opened_at = '2026-01-01 00:00:00+00' where id = (select id from p where kind = 'pre');
select pg_temp.as_user('44000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_set_project_status((select id from p where kind = 'pre'), 'open');
select public.admin_set_project_status((select id from p where kind = 'pre'), 'draft');
select public.admin_set_project_status((select id from p where kind = 'pre'), 'open');
select is((select first_opened_at from public.projects where id = (select id from p where kind = 'pre')),
  '2026-01-01 00:00:00+00'::timestamptz, 'first_opened_at is never overwritten by later openings');

-- Audit rows: one per change, ids and status names only (notes are not stored in Phase 4).
select is((select count(*)::int from public.activity_logs where action = 'project.open'
  and entity_id = (select id from p where kind = 'ready')::text), 3, 'one project.open audit row per opening');
select is((select count(*)::int from public.activity_logs where action like 'project.%' and details ? 'note'), 0,
  'the status note is not stored on any audit row');
select is((select count(*)::int from public.activity_logs where action = 'project.on_hold'
  and entity_id = (select id from p where kind = 'ready')::text), 1, 'one project.on_hold audit row');
select is((select count(*)::int from public.activity_logs where details::text like '%Ready to go%'), 0,
  'the note text appears nowhere in the audit log');

-- ---------------------------------------------------------------------------
-- admin_update_project
-- ---------------------------------------------------------------------------
select lives_ok($$ select public.admin_update_project((select id from p where kind = 'ready'), '{
  "title": "Ready (renamed)", "summary": "New summary", "deadline": "2027-01-15", "proposed_amount": 20000,
  "revision_allowance": 5, "client_id": "44000000-0000-0000-0000-0000000000c1", "client_price": 90000,
  "internal_notes": "Rush job"}') $$, 'admin updates project details');
select ok((select title = 'Ready (renamed)' and summary = 'New summary' and deadline = '2027-01-15'
  and proposed_amount = 20000 and revision_allowance = 5
  from public.projects where id = (select id from p where kind = 'ready')), 'project details are updated');
select ok((select client_id = '44000000-0000-0000-0000-0000000000c1' and client_price = 90000 and internal_notes = 'Rush job'
  from public.project_internal where project_id = (select id from p where kind = 'ready')), 'internal details are updated');
select lives_ok($$ select public.admin_update_project((select id from p where kind = 'ready'), '{"summary": null}') $$,
  'a key given as null clears the value');
select ok((select summary is null and title = 'Ready (renamed)' and proposed_amount = 20000
  from public.projects where id = (select id from p where kind = 'ready')), 'absent keys keep their values');
select ok((select current_brief_version = 1 from public.projects where id = (select id from p where kind = 'ready'))
  and (select count(*) = 1 from public.brief_versions where project_id = (select id from p where kind = 'ready')),
  'updating details never creates a brief version');

-- Pricing changes are audited with the changed field names only.
select is((select details from public.activity_logs where action = 'project.pricing_changed'
  and entity_id = (select id from p where kind = 'ready')::text),
  jsonb_build_object('project_id', (select id from p where kind = 'ready'),
                     'fields', '["proposed_amount", "client_price"]'::jsonb),
  'a pricing change is audited with the project id and changed field names');
select lives_ok($$ select public.admin_update_project((select id from p where kind = 'ready'),
  '{"proposed_amount": 20000, "client_price": 90000, "internal_notes": "Still rush"}') $$,
  'admin saves details with unchanged prices');
select lives_ok($$ select public.admin_update_project((select id from p where kind = 'ready'),
  '{"client_price_currency": "USD"}') $$, 'admin changes the client price currency');
select is((select array_agg(details -> 'fields' order by id) from public.activity_logs
  where action = 'project.pricing_changed' and entity_id = (select id from p where kind = 'ready')::text),
  array['["proposed_amount", "client_price"]'::jsonb, '["client_price_currency"]'::jsonb],
  'only actual pricing changes are audited (not unchanged prices or other fields)');
select throws_ok($$ select public.admin_update_project((select id from p where kind = 'ready'),
  '{"proposed_amount": 9999999999.995}') $$,
  'ES422', null, 'an amount that rounds past numeric(12,2) is refused');
select throws_ok($$ select public.admin_update_project((select id from p where kind = 'ready'), '{"brief_type": "creative_led"}') $$,
  'ES409', null, 'the brief type cannot change after the first opening');
select lives_ok($$ select public.admin_update_project((select id from p where kind = 'cl'), '{"brief_type": "reference_based"}') $$,
  'the brief type can change before the first opening');
select throws_ok($$ select public.admin_update_project((select id from p where kind = 'ready'), '{"title": null}') $$,
  'ES422', null, 'the title cannot be cleared');
select throws_ok($$ select public.admin_update_project((select id from p where kind = 'ready'), '{"proposed_currency": "rupees"}') $$,
  'ES422', null, 'a bad currency is refused');
select throws_ok($$ select public.admin_update_project((select id from p where kind = 'ready'), '{"client_id": "44000000-0000-0000-0000-0000000000c2"}') $$,
  'ES422', null, 'an archived client cannot be linked');
select throws_ok($$ select public.admin_update_project((select id from p where kind = 'ready'), '[]') $$,
  'ES422', null, 'non-object input is refused');

-- ---------------------------------------------------------------------------
-- Archive and cancelled
-- ---------------------------------------------------------------------------
select lives_ok($$ select public.admin_archive_project((select id from p where kind = 'arch'), true) $$,
  'admin archives a project');
select throws_ok($$ select public.admin_archive_project((select id from p where kind = 'arch'), true) $$,
  'ES409', null, 'archiving twice is refused');
select throws_ok($$ select public.admin_save_brief((select id from p where kind = 'arch'), '{"brief": {"desired_outcome": "More joy"}}') $$,
  'ES409', null, 'an archived project refuses brief edits');
select throws_ok($$ select public.admin_update_project((select id from p where kind = 'arch'), '{"title": "X"}') $$,
  'ES409', null, 'an archived project refuses detail edits');
select throws_ok($$ select public.admin_set_project_status((select id from p where kind = 'arch'), 'cancelled') $$,
  'ES409', null, 'an archived project refuses status changes');
select lives_ok($$ select public.admin_archive_project((select id from p where kind = 'arch'), false) $$,
  'admin restores an archived project');
select lives_ok($$ select public.admin_set_project_status((select id from p where kind = 'arch'), 'cancelled') $$,
  'a draft project can be cancelled');
select throws_ok($$ select public.admin_update_project((select id from p where kind = 'arch'), '{"title": "X"}') $$,
  'ES409', null, 'a cancelled project refuses detail edits');
reset role;

-- ---------------------------------------------------------------------------
-- Non-admin identities
-- ---------------------------------------------------------------------------
select pg_temp.as_anon();
select throws_ok($$ select public.admin_set_project_status((select id from p where kind = 'ready'), 'draft') $$,
  'ES401', null, 'anon cannot change project status');
select throws_ok($$ select public.admin_update_project((select id from p where kind = 'ready'), '{}') $$,
  'ES401', null, 'anon cannot update projects');
select throws_ok($$ select public.admin_archive_project((select id from p where kind = 'ready'), true) $$,
  'ES401', null, 'anon cannot archive projects');
reset role;

create function pg_temp.denied_for(p_uid uuid, p_aal text)
returns int language plpgsql as $$
declare
  v_denied int := 0;
  v_id uuid := (select id from p where kind = 'ready');
begin
  perform pg_temp.as_user(p_uid, p_aal);
  begin perform public.admin_set_project_status(v_id, 'draft'); exception when sqlstate 'ES403' then v_denied := v_denied + 1; end;
  begin perform public.admin_update_project(v_id, '{}'); exception when sqlstate 'ES403' then v_denied := v_denied + 1; end;
  begin perform public.admin_archive_project(v_id, true); exception when sqlstate 'ES403' then v_denied := v_denied + 1; end;
  reset role;
  return v_denied;
end;
$$;
select is(pg_temp.denied_for('44000000-0000-0000-0000-00000000000a', 'aal1'), 3, 'admin without MFA is refused by all three functions');
select is(pg_temp.denied_for('44000000-0000-0000-0000-000000000001', 'aal1'), 3, 'editor A is refused by all three functions');
select is(pg_temp.denied_for('44000000-0000-0000-0000-000000000002', 'aal1'), 3, 'editor B is refused by all three functions');
select is(pg_temp.denied_for('44000000-0000-0000-0000-000000000003', 'aal1'), 3, 'an applicant is refused by all three functions');

select * from finish();

rollback;
