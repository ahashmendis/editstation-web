-- Phase 6: confirmation (one confirmed editor per project), reassign, admin notes and the
-- revoke checklist v2. Review Focus 5 (two accepted editors) and 7 (editor suspended after accepting).
begin;

create extension if not exists pgtap with schema extensions;

select plan(33);

create function pg_temp.as_user(p_uid uuid, p_aal text default 'aal1')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- Fixtures (as postgres)
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('55000000-0000-0000-0000-00000000000a', 'p6c-admin@test.local', '{}', '{}'),
  ('55000000-0000-0000-0000-000000000001', 'p6c-editor-a@test.local', '{}', '{}'),
  ('55000000-0000-0000-0000-000000000002', 'p6c-editor-b@test.local', '{}', '{}'),
  ('55000000-0000-0000-0000-000000000005', 'p6c-editor-c@test.local', '{}', '{}'),
  ('55000000-0000-0000-0000-000000000006', 'p6c-editor-e@test.local', '{}', '{}');
select private.grant_admin_by_email('p6c-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('55000000-0000-0000-0000-000000000001', '55000000-0000-0000-0000-000000000002',
                  '55000000-0000-0000-0000-000000000005', '55000000-0000-0000-0000-000000000006');

-- P1 two accepted editors + invited C; P2 offered; P3 on hold; P4 archived; P5 editor E
-- suspended after accepting; P6 B confirmed (checklist case d).
insert into public.projects (id, title, brief_type, status, first_opened_at) values
  ('55000000-0000-0000-0000-0000000000f1', 'P1', 'fully_instructed', 'open', now()),
  ('55000000-0000-0000-0000-0000000000f2', 'P2', 'fully_instructed', 'open', now()),
  ('55000000-0000-0000-0000-0000000000f3', 'P3', 'fully_instructed', 'open', now()),
  ('55000000-0000-0000-0000-0000000000f4', 'P4', 'fully_instructed', 'open', now()),
  ('55000000-0000-0000-0000-0000000000f5', 'P5', 'fully_instructed', 'open', now()),
  ('55000000-0000-0000-0000-0000000000f6', 'P6', 'fully_instructed', 'open', now());

create temp table ids (kind text primary key, id uuid not null);
grant select, insert on ids to authenticated;
create function pg_temp.a(p_kind text) returns uuid language sql as $$ select id from ids where kind = p_kind $$;
grant execute on function pg_temp.a(text) to authenticated;

-- The editor's acceptance, set directly (editor_respond_offer is tested in 056).
create function pg_temp.accept(p_id uuid) returns void language sql as $$
  update public.assignments set status = 'accepted', agreed_amount = proposed_amount, agreed_currency = currency
  where id = p_id $$;

select pg_temp.as_user('55000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_grant_project_access('55000000-0000-0000-0000-0000000000f1',
  array['55000000-0000-0000-0000-000000000001', '55000000-0000-0000-0000-000000000002',
        '55000000-0000-0000-0000-000000000005']::uuid[], 'invited');
insert into ids select 'a1', public.admin_make_offer('55000000-0000-0000-0000-0000000000f1',
  '55000000-0000-0000-0000-000000000001', 20000);
insert into ids select 'b1', public.admin_make_offer('55000000-0000-0000-0000-0000000000f1',
  '55000000-0000-0000-0000-000000000002', 21000);
insert into ids select 'a2', public.admin_make_offer('55000000-0000-0000-0000-0000000000f2',
  '55000000-0000-0000-0000-000000000001', 5000);
insert into ids select 'a3', public.admin_make_offer('55000000-0000-0000-0000-0000000000f3',
  '55000000-0000-0000-0000-000000000001', 5000);
insert into ids select 'a4', public.admin_make_offer('55000000-0000-0000-0000-0000000000f4',
  '55000000-0000-0000-0000-000000000001', 5000);
insert into ids select 'e5', public.admin_make_offer('55000000-0000-0000-0000-0000000000f5',
  '55000000-0000-0000-0000-000000000006', 5000);
insert into ids select 'b6', public.admin_make_offer('55000000-0000-0000-0000-0000000000f6',
  '55000000-0000-0000-0000-000000000002', 5000);
-- Folder shares for the checklist (recorded while everyone is active and the projects open).
insert into ids select 'g_a', public.admin_record_asset_grant('55000000-0000-0000-0000-0000000000f1',
  '55000000-0000-0000-0000-000000000001', 'a@drive.example.com', 'google_drive');
insert into ids select 'g_b', public.admin_record_asset_grant('55000000-0000-0000-0000-0000000000f1',
  '55000000-0000-0000-0000-000000000002', 'b@drive.example.com', 'google_drive');
insert into ids select 'g_c', public.admin_record_asset_grant('55000000-0000-0000-0000-0000000000f1',
  '55000000-0000-0000-0000-000000000005', 'c@drive.example.com', 'google_drive');
insert into ids select 'g_d', public.admin_record_asset_grant('55000000-0000-0000-0000-0000000000f6',
  '55000000-0000-0000-0000-000000000002', 'b@drive.example.com', 'dropbox');
insert into ids select 'g_e', public.admin_record_asset_grant('55000000-0000-0000-0000-0000000000f5',
  '55000000-0000-0000-0000-000000000006', 'e@drive.example.com', 'other');
reset role;

select pg_temp.accept(pg_temp.a('a1'));
select pg_temp.accept(pg_temp.a('b1'));
select pg_temp.accept(pg_temp.a('a3'));
select pg_temp.accept(pg_temp.a('a4'));
select pg_temp.accept(pg_temp.a('e5'));
select pg_temp.accept(pg_temp.a('b6'));
update public.projects set status = 'on_hold', status_before_hold = 'open' where id = '55000000-0000-0000-0000-0000000000f3';
update public.projects set archived_at = now() where id = '55000000-0000-0000-0000-0000000000f4';

-- ---------------------------------------------------------------------------
-- Review Focus 5: two accepted editors, one confirmation
-- ---------------------------------------------------------------------------
select pg_temp.as_user('55000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok($$ select public.admin_confirm_assignment(pg_temp.a('a1')) $$, 'admin confirms editor A');
select ok((select status = 'confirmed' and confirmed_by = '55000000-0000-0000-0000-00000000000a'
    and confirmed_at is not null and agreed_amount = 20000
  from public.assignments where id = pg_temp.a('a1')), 'A is confirmed by the admin at the agreed amount');
select is((select status from public.projects where id = '55000000-0000-0000-0000-0000000000f1'),
  'assigned'::public.project_status, 'the project becomes assigned');
select is((select count(*)::int from public.activity_logs where action = 'project.assigned'
  and entity_id = '55000000-0000-0000-0000-0000000000f1'), 1, 'the Phase 4 trigger audits project.assigned');
select ok((select status = 'not_selected' and closed_at is not null from public.assignments where id = pg_temp.a('b1')),
  'the other accepted editor becomes not selected');
select is((select count(*)::int from public.negotiation_offers where assignment_id = pg_temp.a('b1')), 1,
  'not selected adds no negotiation row (activity log only)');
select is((select array_agg(editor_id order by editor_id) from public.project_access
  where project_id = '55000000-0000-0000-0000-0000000000f1' and revoked_at is null),
  array['55000000-0000-0000-0000-000000000001']::uuid[],
  'B''s and invited-only C''s access are revoked; A keeps theirs');
select throws_ok($$ select public.admin_confirm_assignment(pg_temp.a('b1')) $$, 'ES409', null,
  'a second confirmation on the project is refused');
reset role;
select throws_ok($$ insert into public.assignments (project_id, editor_id, status, proposed_amount, agreed_amount,
  agreed_currency, confirmed_at) values ('55000000-0000-0000-0000-0000000000f1', '55000000-0000-0000-0000-000000000005',
  'confirmed', 1, 1, 'LKR', now()) $$, '23505', null, 'the database refuses a second confirmed row');
select ok(pg_get_functiondef('public.admin_confirm_assignment(uuid)'::regprocedure) ~* 'for\s+update'
      and pg_get_functiondef('private.lock_assignment(uuid)'::regprocedure) ~* 'for\s+update',
  'confirmation locks the project and assignment rows (for update)');
select ok(pg_get_functiondef('public.admin_confirm_assignment(uuid)'::regprocedure)
      ~* 'when\s+unique_violation\s+then\s+raise\s+exception\s+''Another editor is already confirmed for this project\.''\s+using\s+errcode\s*=\s*''ES409''',
  'a concurrent second confirmation (unique index race) is mapped to ES409');

-- ---------------------------------------------------------------------------
-- Refused confirmations
-- ---------------------------------------------------------------------------
select pg_temp.as_user('55000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_confirm_assignment(pg_temp.a('a2')) $$, 'ES409', null,
  'an offered row cannot be confirmed');
reset role;
update public.assignments set status = 'counteroffer_pending', proposed_amount = 5500 where id = pg_temp.a('a2');
select pg_temp.as_user('55000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_confirm_assignment(pg_temp.a('a2')) $$, 'ES409', null,
  'a counteroffer row cannot be confirmed');
select throws_ok($$ select public.admin_confirm_assignment(pg_temp.a('a3')) $$, 'ES409', null,
  'no confirmation on an on-hold project');
select throws_ok($$ select public.admin_confirm_assignment(pg_temp.a('a4')) $$, 'ES409', null,
  'no confirmation on an archived project');
select throws_ok($$ select public.admin_confirm_assignment('55000000-0000-0000-0000-0000000000ff') $$, 'ES422',
  'Offer not found.', 'an unknown assignment is refused');
reset role;
update public.editor_profiles set access_status = 'suspended' where user_id = '55000000-0000-0000-0000-000000000006';
select pg_temp.as_user('55000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_confirm_assignment(pg_temp.a('e5')) $$, 'ES409', null,
  'an editor suspended after accepting cannot be confirmed');
select lives_ok($$ select public.admin_confirm_assignment(pg_temp.a('b6')) $$, 'admin confirms B on P6');

-- ---------------------------------------------------------------------------
-- Reassign (plan call 14)
-- ---------------------------------------------------------------------------
select lives_ok($$ select public.admin_reassign(pg_temp.a('a1'), 'Client changed the scope') $$,
  'admin reassigns the confirmed editor');
select ok((select status = 'reassigned' and closed_at is not null from public.assignments where id = pg_temp.a('a1')),
  'the assignment is reassigned and closed');
select ok(exists (select 1 from public.negotiation_offers where assignment_id = pg_temp.a('a1')
  and from_role = 'admin' and action = 'withdraw' and message = 'Client changed the scope'),
  'the reason is recorded as an admin withdraw row the editor can read');
select is((select status from public.projects where id = '55000000-0000-0000-0000-0000000000f1'),
  'open'::public.project_status, 'the project goes back to open');
select ok(not exists (select 1 from public.project_access where project_id = '55000000-0000-0000-0000-0000000000f1'
  and editor_id = '55000000-0000-0000-0000-000000000001' and revoked_at is null), 'the reassigned editor''s access is revoked');
select throws_ok($$ select public.admin_reassign(pg_temp.a('a2')) $$, 'ES409', null,
  'only a confirmed row can be reassigned');

-- Checklist v2 (plan call 3), before A is offered again.
select set_eq($$ select grant_id, reason from public.admin_pending_revocations()
  where grant_id in (select id from ids where kind like 'g\_%') $$,
  $$ select * from (values (pg_temp.a('g_a'), 'no_active_assignment'), (pg_temp.a('g_b'), 'no_active_assignment'),
       (pg_temp.a('g_c'), 'no_active_assignment'), (pg_temp.a('g_e'), 'editor_not_active')) v(id, reason) $$,
  'the checklist lists reassigned, not-selected, invited-only and suspended editors, not the confirmed one');

insert into ids select 'a1b', public.admin_make_offer('55000000-0000-0000-0000-0000000000f1',
  '55000000-0000-0000-0000-000000000001', 22000);
select is((select count(*)::int from public.assignments where project_id = '55000000-0000-0000-0000-0000000000f1'
  and editor_id = '55000000-0000-0000-0000-000000000001'), 2, 'a new offer after reassign creates a new row');
select ok((select status = 'offered' from public.assignments where id = pg_temp.a('a1b'))
  and (select status = 'reassigned' from public.assignments where id = pg_temp.a('a1')),
  'the reassigned row keeps its history');

-- ---------------------------------------------------------------------------
-- Admin notes (KB6)
-- ---------------------------------------------------------------------------
insert into ids select 'n1', public.admin_add_project_note('55000000-0000-0000-0000-0000000000f1',
  '  Spoke to the client about the music licence.  ');
select is((select note from public.project_notes where id = pg_temp.a('n1')),
  'Spoke to the client about the music licence.', 'admin adds a trimmed note');
select lives_ok($$ select public.admin_add_project_note('55000000-0000-0000-0000-0000000000f4', 'Archived note') $$,
  'notes can be added to an archived project');
select throws_ok($$ select public.admin_add_project_note('55000000-0000-0000-0000-0000000000f1', '   ') $$, 'ES422',
  null, 'a blank note is refused');
select throws_ok($$ select public.admin_add_project_note('55000000-0000-0000-0000-0000000000f1', repeat('n', 4001)) $$,
  'ES422', null, 'a note over 4000 characters is refused');
select throws_ok($$ select public.admin_add_project_note('55000000-0000-0000-0000-0000000000ff', 'x') $$, 'ES422',
  null, 'a note on an unknown project is refused');
select is((select details from public.activity_logs where action = 'project.note_added'
  and entity_id = '55000000-0000-0000-0000-0000000000f1'),
  jsonb_build_object('project_id', '55000000-0000-0000-0000-0000000000f1'::uuid, 'note_id', pg_temp.a('n1')),
  'the note audit row holds ids only');
reset role;

select * from finish();

rollback;
