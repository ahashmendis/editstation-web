-- Open opportunities: publish, edit, close, the editor projection, register / withdraw interest,
-- limits, and choosing an editor (which must produce exactly the existing offer). Also the
-- races and states: two selections, withdraw after selection, cancelled / on-hold project,
-- suspended editor, editor with a live offer, closing date, reopen.
begin;

create extension if not exists pgtap with schema extensions;

select plan(82);

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

-- Fixture ids: c2..0a admin, 01 editor A, 02 editor B, 05 editor C (active), 03 applicant,
-- 04 suspended.
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('c2000000-0000-0000-0000-00000000000a', 'opp-f-admin@test.local', '{}', '{}'),
  ('c2000000-0000-0000-0000-000000000001', 'opp-f-editor-a@test.local', '{}', '{}'),
  ('c2000000-0000-0000-0000-000000000002', 'opp-f-editor-b@test.local', '{}', '{}'),
  ('c2000000-0000-0000-0000-000000000003', 'opp-f-applicant@test.local', '{}', '{}'),
  ('c2000000-0000-0000-0000-000000000004', 'opp-f-suspended@test.local', '{}', '{}'),
  ('c2000000-0000-0000-0000-000000000005', 'opp-f-editor-c@test.local', '{}', '{}');
select private.grant_admin_by_email('opp-f-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('c2000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000002',
                  'c2000000-0000-0000-0000-000000000005');
update public.editor_profiles set access_status = 'suspended' where user_id = 'c2000000-0000-0000-0000-000000000004';

insert into public.projects (id, title, brief_type, status, first_opened_at, archived_at) values
  ('c2000000-0000-0000-0000-0000000000f1', 'ACMECLIENT launch film', 'fully_instructed', 'open', now(), null),
  ('c2000000-0000-0000-0000-0000000000f2', 'Twin for a direct offer', 'fully_instructed', 'open', now(), null),
  ('c2000000-0000-0000-0000-0000000000f3', 'Declined before', 'fully_instructed', 'open', now(), null),
  ('c2000000-0000-0000-0000-0000000000f4', 'Live offer', 'fully_instructed', 'open', now(), null),
  ('c2000000-0000-0000-0000-0000000000f5', 'To be cancelled', 'fully_instructed', 'open', now(), null),
  ('c2000000-0000-0000-0000-0000000000f6', 'Closed and reopened', 'fully_instructed', 'open', now(), null),
  ('c2000000-0000-0000-0000-0000000000d1', 'Draft', 'fully_instructed', 'draft', null, null),
  ('c2000000-0000-0000-0000-0000000000e3', 'Archived', 'fully_instructed', 'open', now(), now());
insert into public.projects (id, title, brief_type, status, first_opened_at)
select ('c2000000-0000-0000-0000-0000000001' || lpad(g::text, 2, '0'))::uuid, 'Limit ' || g, 'fully_instructed', 'open', now()
from generate_series(1, 12) g;
insert into public.project_internal (project_id, client_price) values ('c2000000-0000-0000-0000-0000000000f1', 99999)
on conflict (project_id) do update set client_price = 99999;
insert into public.assignments (project_id, editor_id, status, proposed_amount, closed_at) values
  ('c2000000-0000-0000-0000-0000000000f3', 'c2000000-0000-0000-0000-000000000002', 'declined', 5000, now());

create temp table ids (kind text primary key, id uuid not null);
grant all on ids to authenticated, anon;
create function pg_temp.a(p_kind text) returns uuid language sql as $$ select id from ids where kind = p_kind $$;
grant execute on function pg_temp.a(text) to authenticated, anon;

-- ---------------------------------------------------------------------------
-- Publish and edit (admin, MFA)
-- ---------------------------------------------------------------------------
select pg_temp.as_user('c2000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_publish_opportunity(gen_random_uuid(), 'T', 'D') $$, 'ES422', 'Project not found.',
  'publish: unknown project');
select throws_ok($$ select public.admin_publish_opportunity('c2000000-0000-0000-0000-0000000000d1', 'T', 'D') $$, 'ES409', null,
  'publish: a draft project is refused');
select throws_ok($$ select public.admin_publish_opportunity('c2000000-0000-0000-0000-0000000000e3', 'T', 'D') $$, 'ES409', null,
  'publish: an archived project is refused');
select throws_ok($$ select public.admin_publish_opportunity('c2000000-0000-0000-0000-0000000000f1', '  ', 'D') $$, 'ES422',
  'Please give the opportunity a title.', 'publish: a title is required');
select throws_ok($$ select public.admin_publish_opportunity('c2000000-0000-0000-0000-0000000000f1', 'T', null) $$, 'ES422',
  'Please summarise the deliverables.', 'publish: a deliverables summary is required');
select throws_ok($$ select public.admin_publish_opportunity('c2000000-0000-0000-0000-0000000000f1', 'T', 'D', null,
  current_date - 2) $$, 'ES422', 'The deadline cannot be in the past.', 'publish: no past deadline');
select throws_ok($$ select public.admin_publish_opportunity('c2000000-0000-0000-0000-0000000000f1', 'T', 'D', null, null, null,
  null, null, now() - interval '1 hour') $$, 'ES422', 'The closing date must be in the future.', 'publish: no past closing date');
select throws_ok($$ select public.admin_publish_opportunity('c2000000-0000-0000-0000-0000000000f1', 'T', 'D', 'no_such_type') $$,
  'ES422', 'Choose a service type from the list.', 'publish: unknown service type');
select throws_ok($$ select public.admin_publish_opportunity('c2000000-0000-0000-0000-0000000000f1', 'T', 'D', null, null, null, -5) $$,
  'ES422', null, 'publish: shown pay must be above zero');

insert into ids values ('o1', public.admin_publish_opportunity('c2000000-0000-0000-0000-0000000000f1',
  'Promo edit, 60 seconds', 'One 60 s cut and a 15 s teaser', null, current_date + 20, 'English, 16:9'));
select ok((select shown_pay_amount is null and shown_pay_currency is null and status = 'open'
           from public.project_opportunities where id = pg_temp.a('o1')), 'publish: pay is hidden by default');
select throws_ok($$ select public.admin_publish_opportunity('c2000000-0000-0000-0000-0000000000f1', 'T', 'D') $$, 'ES409',
  'This project is already published as an opportunity. Edit it instead.', 'publish: only once while open');
select lives_ok($$ select public.admin_update_opportunity(pg_temp.a('o1'), 'Promo edit, 60 seconds',
  'One 60 s cut and a 15 s teaser', null, current_date + 20, 'English, 16:9', 25000) $$, 'update: show pay');
reset role;
select is((select (shown_pay_amount, shown_pay_currency)::text from public.project_opportunities where id = pg_temp.a('o1')),
  '(25000.00,LKR)', 'update: the shown pay is stored, currency defaulted');
select is((select details -> 'fields' from public.activity_logs where action = 'opportunity.updated'
           and entity_id = pg_temp.a('o1')::text), '["shown_pay"]'::jsonb, 'update audit lists only the changed field');
select is_empty($$ select id from public.activity_logs where action like 'opportunit%'
  and (details::text like '%25000%' or details::text like '%Promo%' or details::text like '%English%') $$,
  'audit rows hold ids and field names only, never amounts or summary text');

-- ---------------------------------------------------------------------------
-- The editor projection
-- ---------------------------------------------------------------------------
select pg_temp.as_user('c2000000-0000-0000-0000-000000000001');
select is((select count(*)::int from public.editor_list_opportunities()), 1, 'editor A lists the one open opportunity');
select ok((select accepting_interest and interest_id is null and interest_status is null and selected_project_id is null
             and shown_pay_amount = 25000 and title = 'Promo edit, 60 seconds'
           from public.editor_list_opportunities()), 'the row has the summary, the shown pay and no interest yet');
select ok((select bool_and(to_jsonb(r)::text not like '%ACMECLIENT%' and to_jsonb(r)::text not like '%99999%')
           from public.editor_list_opportunities() r), 'no client name or client price in the projection');
reset role;
select set_eq($$ select unnest(p.proargnames[p.pronargs + 1:]) from pg_proc p
                 where p.oid = 'public.editor_list_opportunities()'::regprocedure $$,
  array['opportunity_id', 'title', 'service_type', 'deliverables_summary', 'deadline', 'format_notes',
        'shown_pay_amount', 'shown_pay_currency', 'closes_at', 'published_at', 'accepting_interest', 'interest_id',
        'interest_status', 'proposed_amount', 'proposed_currency', 'note', 'selected_project_id'],
  'the projection returns exactly the summary allow-list');
select pg_temp.as_user('c2000000-0000-0000-0000-000000000004');
select throws_ok($$ select * from public.editor_list_opportunities() $$, 'ES403', null, 'a suspended editor gets nothing');
select pg_temp.as_user('c2000000-0000-0000-0000-000000000003');
select throws_ok($$ select * from public.editor_list_opportunities() $$, 'ES403', null, 'a pending applicant gets nothing');
select pg_temp.as_anon();
select throws_ok($$ select * from public.editor_list_opportunities() $$, 'ES401', null, 'anon gets nothing');
select pg_temp.as_user('c2000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select * from public.editor_list_opportunities() $$, 'ES403', null, 'an admin is not an editor');

-- ---------------------------------------------------------------------------
-- Register interest
-- ---------------------------------------------------------------------------
select pg_temp.as_user('c2000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.editor_register_interest(pg_temp.a('o1'), -5) $$, 'ES422', null, 'register: rate above zero');
select throws_ok($$ select public.editor_register_interest(pg_temp.a('o1'), null, null, repeat('x', 501)) $$, 'ES422',
  'The note can be at most 500 characters.', 'register: short note only');
select throws_ok($$ select public.editor_register_interest(gen_random_uuid()) $$, 'ES422', 'Opportunity not found.',
  'register: unknown opportunity');
insert into ids values ('ia', public.editor_register_interest(pg_temp.a('o1'), 30000, null, 'Did similar promos'));
select throws_ok($$ select public.editor_register_interest(pg_temp.a('o1')) $$, 'ES409',
  'You have already registered interest in this opportunity.', 'register: once per opportunity');
select is((select interest_status::text || ' ' || proposed_amount || ' ' || proposed_currency from public.editor_list_opportunities()),
  'interested 30000.00 LKR', 'editor A sees their interest; the rate currency defaults to the shown pay currency');
select pg_temp.as_user('c2000000-0000-0000-0000-000000000002');
insert into ids values ('ib', public.editor_register_interest(pg_temp.a('o1')));
select throws_ok($$ select public.editor_withdraw_interest(pg_temp.a('ia')) $$, 'ES422', 'Interest not found.',
  'editor B cannot withdraw editor A''s interest');
select pg_temp.as_user('c2000000-0000-0000-0000-000000000005');
insert into ids values ('ic0', public.editor_register_interest(pg_temp.a('o1')));
select lives_ok($$ select public.editor_withdraw_interest(pg_temp.a('ic0')) $$, 'editor C withdraws');
select throws_ok($$ select public.editor_withdraw_interest(pg_temp.a('ic0')) $$, 'ES409', 'This interest is already closed.',
  'withdrawing twice is refused');
insert into ids values ('ic', public.editor_register_interest(pg_temp.a('o1')));
reset role;
select is((select count(*)::int from public.opportunity_interests where editor_id = 'c2000000-0000-0000-0000-000000000005'), 2,
  'registering again after a withdrawal adds a new row (history kept)');
select is((select count(*)::int from public.notifications where kind = 'interest_registered'
           and recipient_id = 'c2000000-0000-0000-0000-00000000000a' and entity_id = 'c2000000-0000-0000-0000-0000000000f1'), 4,
  'the admin gets one notification per new interest');
select is((select details -> 'fields' from public.activity_logs where action = 'opportunity_interest.registered'
           and entity_id = pg_temp.a('ia')::text), '["proposed_amount", "note"]'::jsonb,
  'the register audit names the fields, never the rate or note');

-- ---------------------------------------------------------------------------
-- Choose an editor
-- ---------------------------------------------------------------------------
update public.editor_profiles set access_status = 'suspended' where user_id = 'c2000000-0000-0000-0000-000000000005';
select pg_temp.as_user('c2000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_select_editor(pg_temp.a('ic'), 20000) $$, 'ES409',
  'This editor''s access is not active, so they cannot be chosen.', 'select: a suspended editor cannot be chosen');
reset role;
update public.editor_profiles set access_status = 'active' where user_id = 'c2000000-0000-0000-0000-000000000005';
select pg_temp.as_user('c2000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_select_editor(pg_temp.a('ia'), null) $$, 'ES422', 'Please enter the offer amount.',
  'select: the admin sets the offer amount (the proposed rate never does)');
select throws_ok($$ select public.admin_select_editor(pg_temp.a('ic0'), 20000) $$, 'ES409',
  'This editor withdrew their interest.', 'select: a withdrawn interest cannot be chosen');
select throws_ok($$ select public.admin_select_editor(gen_random_uuid(), 20000) $$, 'ES422', 'Interest not found.',
  'select: unknown interest');
insert into ids values ('asg', public.admin_select_editor(pg_temp.a('ia'), 28000, null, 'Welcome aboard'));
select throws_ok($$ select public.admin_select_editor(pg_temp.a('ib'), 20000) $$, 'ES409',
  'An editor was already chosen for this opportunity.', 'select: a second selection is refused');
reset role;

select is((select status::text || ' ' || proposed_amount || ' ' || currency || ' ' || editor_id from public.assignments
           where id = pg_temp.a('asg')),
  'offered 28000.00 LKR c2000000-0000-0000-0000-000000000001', 'select: an offer at the admin''s amount, not the proposed rate');
select is((select array_agg(action::text || ' ' || from_role || ' ' || amount) from public.negotiation_offers
           where assignment_id = pg_temp.a('asg')), array['offer admin 28000.00'], 'select: one admin offer in the history');
select ok(exists (select 1 from public.project_access where project_id = 'c2000000-0000-0000-0000-0000000000f1'
                  and editor_id = 'c2000000-0000-0000-0000-000000000001' and reason = 'invited' and revoked_at is null),
  'select: the chosen editor gets the invited access row');
select is((select array_agg(status::text order by editor_id, created_at) from public.opportunity_interests
           where opportunity_id = pg_temp.a('o1')),
  array['selected', 'not_selected', 'withdrawn', 'not_selected'], 'select: chosen, the others not selected, withdrawn kept');
select is((select status::text || ' ' || close_reason from public.project_opportunities where id = pg_temp.a('o1')),
  'filled selected', 'select: the opportunity is filled');
select is((select count(*)::int from public.notifications where kind = 'opportunity_selected'
           and recipient_id = 'c2000000-0000-0000-0000-000000000001' and entity_type = 'project'), 1,
  'the chosen editor is notified');
select is((select count(*)::int from public.notifications where kind = 'opportunity_not_selected'
           and entity_type = 'project_opportunity' and entity_id = pg_temp.a('o1')
           and recipient_id in ('c2000000-0000-0000-0000-000000000002', 'c2000000-0000-0000-0000-000000000005')), 2,
  'each editor not chosen is notified once');
select is_empty($$ select id from public.notifications where kind in ('opportunity_selected', 'opportunity_not_selected')
  and (title || body) like '%ACMECLIENT%' $$, 'editor notifications use the opportunity title, never the project title');
select is((select details ->> 'assignment_id' from public.activity_logs where action = 'opportunity_interest.selected'
           and entity_id = pg_temp.a('ia')::text), pg_temp.a('asg')::text, 'the selection is audited with the assignment id');

-- Exactly the existing offer: the same call made directly on a twin project.
select pg_temp.as_user('c2000000-0000-0000-0000-00000000000a', 'aal2');
insert into ids values ('direct', public.admin_make_offer('c2000000-0000-0000-0000-0000000000f2',
  'c2000000-0000-0000-0000-000000000001', 28000, null, 'Welcome aboard'));
reset role;
select is(
  (select jsonb_build_object('a', to_jsonb(a) - 'id' - 'project_id' - 'created_at' - 'updated_at',
     'n', (select jsonb_agg(to_jsonb(n) - 'id' - 'assignment_id' - 'created_at') from public.negotiation_offers n where n.assignment_id = a.id),
     'p', (select jsonb_agg(pa.reason) from public.project_access pa where pa.project_id = a.project_id and pa.editor_id = a.editor_id))
   from public.assignments a where a.id = pg_temp.a('asg')),
  (select jsonb_build_object('a', to_jsonb(a) - 'id' - 'project_id' - 'created_at' - 'updated_at',
     'n', (select jsonb_agg(to_jsonb(n) - 'id' - 'assignment_id' - 'created_at') from public.negotiation_offers n where n.assignment_id = a.id),
     'p', (select jsonb_agg(pa.reason) from public.project_access pa where pa.project_id = a.project_id and pa.editor_id = a.editor_id))
   from public.assignments a where a.id = pg_temp.a('direct')),
  'selection produces exactly the offer, history and access a direct offer produces');

-- The editors' view afterwards.
select pg_temp.as_user('c2000000-0000-0000-0000-000000000001');
select is((select interest_status::text || ' ' || selected_project_id from public.editor_list_opportunities()
           where opportunity_id = pg_temp.a('o1')),
  'selected c2000000-0000-0000-0000-0000000000f1', 'editor A sees Selected and the project link');
select throws_ok($$ select public.editor_withdraw_interest(pg_temp.a('ia')) $$, 'ES409',
  'You were already selected. Answer the offer on the project page instead.', 'a selected editor cannot withdraw');
select pg_temp.as_user('c2000000-0000-0000-0000-000000000002');
select is((select interest_status::text || ' ' || accepting_interest || ' ' || coalesce(selected_project_id::text, '-')
           from public.editor_list_opportunities() where opportunity_id = pg_temp.a('o1')),
  'not_selected false -', 'editor B sees Not selected and no project link');
select throws_ok($$ select public.editor_withdraw_interest(pg_temp.a('ib')) $$, 'ES409', 'This interest is already closed.',
  'withdrawing after not being selected is refused');
select throws_ok($$ select public.editor_register_interest(pg_temp.a('o1')) $$, 'ES409',
  'This opportunity is no longer taking interest.', 'a filled opportunity takes no new interest');

-- ---------------------------------------------------------------------------
-- Previously declined; live offer
-- ---------------------------------------------------------------------------
select pg_temp.as_user('c2000000-0000-0000-0000-00000000000a', 'aal2');
insert into ids values ('o3', public.admin_publish_opportunity('c2000000-0000-0000-0000-0000000000f3', 'Short cut', 'One reel'));
insert into ids values ('o4', public.admin_publish_opportunity('c2000000-0000-0000-0000-0000000000f4', 'Podcast clips', 'Five clips'));
select pg_temp.as_user('c2000000-0000-0000-0000-000000000002');
select throws_ok($$ select public.editor_register_interest(pg_temp.a('o3')) $$, 'ES409',
  'You cannot register interest in this project again.', 'an editor who declined this project cannot register');
select pg_temp.as_user('c2000000-0000-0000-0000-000000000001');
insert into ids values ('ia4', public.editor_register_interest(pg_temp.a('o4')));
select pg_temp.as_user('c2000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok($$ select public.admin_make_offer('c2000000-0000-0000-0000-0000000000f4', 'c2000000-0000-0000-0000-000000000001', 9000) $$,
  'the admin can still invite directly (call 8)');
select lives_ok($$ select public.admin_make_offer('c2000000-0000-0000-0000-0000000000f4', 'c2000000-0000-0000-0000-000000000005', 9000) $$,
  'and invite an editor who has no interest');
select throws_ok($$ select public.admin_select_editor(pg_temp.a('ia4'), 9000) $$, 'ES409',
  'This editor already has a live offer on this project. Continue it in the Editors card.',
  'select: an editor who already has a live offer');
select pg_temp.as_user('c2000000-0000-0000-0000-000000000005');
select throws_ok($$ select public.editor_register_interest(pg_temp.a('o4')) $$, 'ES409',
  'You already have an offer on this project. Answer it from your dashboard.', 'register: not with a live offer');

-- ---------------------------------------------------------------------------
-- Project cancelled (auto-close) and on hold
-- ---------------------------------------------------------------------------
select pg_temp.as_user('c2000000-0000-0000-0000-00000000000a', 'aal2');
insert into ids values ('o5', public.admin_publish_opportunity('c2000000-0000-0000-0000-0000000000f5', 'Wedding teaser', 'One teaser'));
select pg_temp.as_user('c2000000-0000-0000-0000-000000000001');
insert into ids values ('ia5', public.editor_register_interest(pg_temp.a('o5')));
reset role;
update public.projects set status = 'cancelled' where id = 'c2000000-0000-0000-0000-0000000000f5';
select is((select status::text || ' ' || close_reason from public.project_opportunities where id = pg_temp.a('o5')),
  'closed project_closed', 'cancelling the project closes its opportunity');
select is((select details - 'opportunity_id' - 'project_id' from public.activity_logs where action = 'opportunity.closed'
           and entity_id = pg_temp.a('o5')::text),
  '{"reason": "project_closed", "status": "closed", "not_selected": 1, "project_fields": ["status"], "closed_by_project_change": true}'::jsonb,
  'a project-triggered close records the reason and the changed project field names');
select is((select status::text from public.opportunity_interests where id = pg_temp.a('ia5')), 'not_selected',
  'and its interested editors become not selected');
select pg_temp.as_user('c2000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_select_editor(pg_temp.a('ia5'), 9000) $$, 'ES409',
  'This opportunity is closed. Publish it again to choose an editor.', 'select: closed by the project');
select throws_ok($$ select public.admin_publish_opportunity('c2000000-0000-0000-0000-0000000000f5', 'T', 'D') $$, 'ES409',
  null, 'a cancelled project cannot be published again');

insert into ids values ('o6', public.admin_publish_opportunity('c2000000-0000-0000-0000-0000000000f6', 'Event recap', 'Two cuts'));
select pg_temp.as_user('c2000000-0000-0000-0000-000000000002');
insert into ids values ('ib6', public.editor_register_interest(pg_temp.a('o6'), 15000, 'usd'));
reset role;
select is((select proposed_currency::text from public.opportunity_interests where id = pg_temp.a('ib6')), 'USD',
  'a typed currency is upper-cased');
update public.projects set status = 'on_hold', status_before_hold = 'open' where id = 'c2000000-0000-0000-0000-0000000000f6';
select pg_temp.as_user('c2000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_select_editor(pg_temp.a('ib6'), 9000) $$, 'ES409',
  'The project is not open (it is on hold), so an editor cannot be chosen now.', 'select: not while the project is on hold');
reset role;
select is((select status::text from public.project_opportunities where id = pg_temp.a('o6')), 'open',
  'on hold only hides the opportunity (it stays open)');
update public.projects set status = 'open', status_before_hold = null where id = 'c2000000-0000-0000-0000-0000000000f6';

-- ---------------------------------------------------------------------------
-- Admin close, reopen, closing date
-- ---------------------------------------------------------------------------
select pg_temp.as_user('c2000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok($$ select public.admin_close_opportunity(pg_temp.a('o6')) $$, 'the admin closes an opportunity');
select throws_ok($$ select public.admin_close_opportunity(pg_temp.a('o6')) $$, 'ES409', 'This opportunity is already closed.',
  'closing twice is refused');
select throws_ok($$ select public.admin_update_opportunity(pg_temp.a('o6'), 'T', 'D') $$, 'ES409',
  'This opportunity is closed. Publish it again to reopen it.', 'a closed opportunity cannot be edited');
reset role;
select is((select status::text || ' ' || close_reason from public.project_opportunities where id = pg_temp.a('o6'))
          || ' ' || (select status::text from public.opportunity_interests where id = pg_temp.a('ib6')),
  'closed admin not_selected', 'admin close: closed, interested editors not selected');
select pg_temp.as_user('c2000000-0000-0000-0000-00000000000a', 'aal2');
select is(public.admin_publish_opportunity('c2000000-0000-0000-0000-0000000000f6', 'Event recap', 'Two cuts', null, null,
  null, null, null, now() + interval '1 day'), pg_temp.a('o6'), 'publishing again reopens the same opportunity');
select pg_temp.as_user('c2000000-0000-0000-0000-000000000002');
select throws_ok($$ select public.editor_register_interest(pg_temp.a('o6')) $$, 'ES409',
  'You cannot register interest in this project again.', 'an editor not selected before cannot register again');
select pg_temp.as_user('c2000000-0000-0000-0000-000000000001');
insert into ids values ('ia6', public.editor_register_interest(pg_temp.a('o6')));
reset role;
update public.project_opportunities set closes_at = now() - interval '1 minute' where id = pg_temp.a('o6');
select pg_temp.as_user('c2000000-0000-0000-0000-000000000005');
select throws_ok($$ select public.editor_register_interest(pg_temp.a('o6')) $$, 'ES409',
  'This opportunity is no longer taking interest.', 'no new interest after the closing date');
select pg_temp.as_user('c2000000-0000-0000-0000-00000000000a', 'aal2');
select lives_ok($$ select public.admin_select_editor(pg_temp.a('ia6'), 12000) $$,
  'the admin can still choose an interested editor after the closing date');

-- ---------------------------------------------------------------------------
-- Limit: 10 live interests
-- ---------------------------------------------------------------------------
insert into ids select 'L' || g, public.admin_publish_opportunity(
  ('c2000000-0000-0000-0000-0000000001' || lpad(g::text, 2, '0'))::uuid, 'Limit ' || g, 'One cut')
from generate_series(1, 12) g;
select pg_temp.as_user('c2000000-0000-0000-0000-000000000005');
insert into ids select 'iL' || g, public.editor_register_interest(pg_temp.a('L' || g)) from generate_series(1, 10) g;
select throws_ok($$ select public.editor_register_interest(pg_temp.a('L11')) $$, 'ES409',
  'You can be interested in up to 10 opportunities at a time. Withdraw one first.', 'an 11th live interest is refused');
select lives_ok($$ select public.editor_withdraw_interest(pg_temp.a('iL1')) $$, 'withdrawing one');
select lives_ok($$ select public.editor_register_interest(pg_temp.a('L11')) $$, 'frees a place');
select throws_ok($$ select public.editor_register_interest(pg_temp.a('L12')) $$, 'ES409', null, 'at 10 again');
reset role;
-- Stale rows do not count: an opportunity past its closing date, or on a project on hold.
update public.project_opportunities set closes_at = now() - interval '1 minute' where id = pg_temp.a('L2');
update public.projects set status = 'on_hold', status_before_hold = 'open' where id = 'c2000000-0000-0000-0000-000000000103';
select pg_temp.as_user('c2000000-0000-0000-0000-000000000005');
select lives_ok($$ select public.editor_register_interest(pg_temp.a('L12')) $$,
  'interests on opportunities no longer taking interest do not count towards the 10');
reset role;

-- The admin card's single round trip.
select pg_temp.as_user('c2000000-0000-0000-0000-00000000000a', 'aal2');
select is((select (x -> 'opportunity' ->> 'project_id') || ' ' || jsonb_array_length(x -> 'interests')
           from public.admin_get_opportunity('c2000000-0000-0000-0000-0000000000f1') x),
  'c2000000-0000-0000-0000-0000000000f1 4', 'admin_get_opportunity returns the opportunity and its interests');
select is(public.admin_get_opportunity('c2000000-0000-0000-0000-0000000000d1'),
  '{"opportunity": null, "interests": []}'::jsonb, 'and null with no interests when not published');
reset role;

select * from finish();
rollback;
