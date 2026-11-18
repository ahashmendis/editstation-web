-- Client area C2a: a client starts a new project (a lead, never a project). As anon, pending
-- applicant, editor A, editor B, a user of client X, a user of client Y, a revoked client user, a
-- user of an archived client, and admin with and without MFA.
begin;

create extension if not exists pgtap with schema extensions;

select plan(97);

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

-- Runs p_sql as the caller (null = anon) and returns 'ok' or the SQLSTATE. Rolls back.
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

-- Runs p_sql as the caller and keeps its effect. Returns 'ok' or the SQLSTATE.
create function pg_temp.do_as(p_uid uuid, p_aal text, p_sql text)
returns text language plpgsql as $$
declare
  v text := 'ok';
begin
  begin
    if p_uid is null then perform pg_temp.as_anon(); else perform pg_temp.as_user(p_uid, p_aal); end if;
    execute p_sql;
  exception when others then
    v := sqlstate;
  end;
  reset role;
  return v;
end;
$$;

-- Rows the caller can read from a query, or -1 when the read is refused outright.
create function pg_temp.visible_as(p_uid uuid, p_aal text, p_sql text)
returns bigint language plpgsql as $$
declare
  v bigint;
begin
  begin
    if p_uid is null then perform pg_temp.as_anon(); else perform pg_temp.as_user(p_uid, p_aal); end if;
    execute 'with q as (' || p_sql || ') select count(*) from q' into v;
  exception when others then
    v := -1;
  end;
  reset role;
  return v;
end;
$$;

-- A scalar result of p_sql as the caller (as text), or 'ERR <sqlstate>'.
create function pg_temp.value_as(p_uid uuid, p_aal text, p_sql text)
returns text language plpgsql as $$
declare
  v text;
begin
  begin
    if p_uid is null then perform pg_temp.as_anon(); else perform pg_temp.as_user(p_uid, p_aal); end if;
    execute p_sql into v;
  exception when others then
    v := 'ERR ' || sqlstate;
  end;
  reset role;
  return v;
end;
$$;

-- A valid submission (client-safe input only), with a description marker.
create function pg_temp.submit_sql(p_marker text default 'Edit our launch film')
returns text language sql as $$
  select format($f$ select public.client_submit_project('long_form', %L, 'One 3-minute film', null,
    '2099-03-01', 'Thanks', '[{"url": "https://example.com/ref", "label": "Style"}]', 'v-test') $f$, p_marker);
$$;

-- People: admin ...0a, editor A ...01, editor B ...02, applicant ...03, client X user ...11,
-- revoked client X user ...12, client Y user ...21, archived client Z user ...41.
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, email_confirmed_at, encrypted_password) values
  ('c5000000-0000-0000-0000-00000000000a', 'c2a-admin@test.local', '{}', '{}', now(), 'x'),
  ('c5000000-0000-0000-0000-000000000001', 'c2a-editor-a@test.local', '{}', '{}', now(), 'x'),
  ('c5000000-0000-0000-0000-000000000002', 'c2a-editor-b@test.local', '{}', '{}', now(), 'x'),
  ('c5000000-0000-0000-0000-000000000003', 'c2a-applicant@test.local', '{}', '{}', now(), 'x'),
  ('c5000000-0000-0000-0000-000000000011', 'c2a-client-x@test.local', '{}', '{"client_invite": true}', now(), 'x'),
  ('c5000000-0000-0000-0000-000000000012', 'c2a-client-x2@test.local', '{}', '{"client_invite": true}', now(), 'x'),
  ('c5000000-0000-0000-0000-000000000021', 'c2a-client-y@test.local', '{}', '{"client_invite": true}', now(), 'x'),
  ('c5000000-0000-0000-0000-000000000041', 'c2a-client-z@test.local', '{}', '{"client_invite": true}', now(), 'x'),
  ('c5000000-0000-0000-0000-000000000051', 'c2a-client-v@test.local', '{}', '{"client_invite": true}', now(), 'x');
select private.grant_admin_by_email('c2a-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('c5000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000002');
insert into public.editor_applications (editor_id) values ('c5000000-0000-0000-0000-000000000003');
update public.profiles set full_name = 'Xavier Real', phone = '+94 77 000 0000'
where id = 'c5000000-0000-0000-0000-000000000011';

-- Clients X, Y, archived Z, and W (merge target).
insert into public.clients (id, name, company, email, phone, archived_at) values
  ('c6000000-0000-0000-0000-000000000001', 'Client X', 'X Company', 'c2a-x@example.com', '+94 11 111 1111', null),
  ('c6000000-0000-0000-0000-000000000002', 'Client Y', null, 'c2a-y@example.com', null, null),
  ('c6000000-0000-0000-0000-000000000003', 'Client Z', null, 'c2a-z@example.com', null, now()),
  ('c6000000-0000-0000-0000-000000000004', 'Client W', null, 'c2a-w@example.com', null, null),
  ('c6000000-0000-0000-0000-000000000005', 'Client V', 'V Ltd', 'c2a-v@example.com', '+94 11 555 5555', null);
insert into public.client_users (user_id, client_id, revoked_at) values
  ('c5000000-0000-0000-0000-000000000011', 'c6000000-0000-0000-0000-000000000001', null),
  ('c5000000-0000-0000-0000-000000000012', 'c6000000-0000-0000-0000-000000000001', now()),
  ('c5000000-0000-0000-0000-000000000021', 'c6000000-0000-0000-0000-000000000002', null),
  ('c5000000-0000-0000-0000-000000000041', 'c6000000-0000-0000-0000-000000000003', null),
  ('c5000000-0000-0000-0000-000000000051', 'c6000000-0000-0000-0000-000000000005', null);

-- Budget options: one active, one inactive.
insert into public.budget_ranges (id, label, currency, active) values
  ('c7000000-0000-0000-0000-000000000001', 'C2A range', 'LKR', true),
  ('c7000000-0000-0000-0000-000000000002', 'C2A old range', 'LKR', false);

create temp table ids (kind text primary key, id uuid not null);
grant select, insert on ids to authenticated, anon;

-- ---------------------------------------------------------------------------
-- Schema and privileges
-- ---------------------------------------------------------------------------
select has_column('public', 'client_inquiries', 'client_id', 'client_inquiries has client_id');
select col_is_fk('public', 'client_inquiries', 'client_id', 'client_id references a table');
select col_is_null('public', 'client_inquiries', 'client_id', 'client_id is nullable (public-form inquiries have none)');
select ok(not has_table_privilege('authenticated', 'public.client_inquiries', 'INSERT')
      and not has_table_privilege('authenticated', 'public.client_inquiries', 'UPDATE')
      and not has_table_privilege('anon', 'public.client_inquiries', 'SELECT'),
  'client_inquiries stays read-only for the API roles (writes only through functions)');
select ok((select bool_and(has_function_privilege(r, f::regprocedure, 'execute'))
  from unnest(array['anon', 'authenticated']) r,
       unnest(array['public.client_submit_project(text, text, text, uuid, date, text, jsonb, text)',
                    'public.client_list_requests()']) f),
  'the new client functions are executable by anon and authenticated (authorise in the body)');
select ok(not has_function_privilege('authenticated', 'private.client_request_status_key(public.inquiry_status)', 'execute')
      and not has_function_privilege('anon', 'private.client_request_status_key(public.inquiry_status)', 'execute'),
  'the request status mapping is private');
select ok(pg_get_function_arguments('public.client_submit_project(text, text, text, uuid, date, text, jsonb, text)'::regprocedure)
            !~* '\mp_(contact_name|name|email|phone|company|client_id|contact)\M',
  'client_submit_project takes no contact or client parameter (they cannot be supplied)');
select ok(pg_get_functiondef('public.client_list_requests()'::regprocedure)
            !~* 'inquiry_notes|status_changed_by|email|phone|contact_name|company|budget|client_notes',
  'client_list_requests never reads notes, admin identities, contact details or budget');
select is(pg_get_function_result('public.client_list_requests()'::regprocedure),
  'TABLE(id uuid, service_type_label text, description text, expected_deadline date, submitted_at timestamp with time zone, request_status text, project_id uuid)',
  'client_list_requests returns exactly the client-safe columns');

-- ---------------------------------------------------------------------------
-- Pure mapping
-- ---------------------------------------------------------------------------
select is_empty($$ select s from unnest(enum_range(null::public.inquiry_status)) s
                   where private.client_request_status_key(s) is null $$,
  'every inquiry status maps to a client-facing request status');
select results_eq(
  $$ select t.s::text, private.client_request_status_key(t.s) from unnest(enum_range(null::public.inquiry_status)) with ordinality t(s, n) order by t.n $$,
  $$ values ('new', 'received'), ('reviewing', 'in_review'), ('contacted', 'in_review'),
            ('in_discussion', 'in_review'), ('converted', 'accepted'), ('declined', 'not_taken_forward'),
            ('closed', 'not_taken_forward'), ('spam', 'not_taken_forward') $$,
  'the request status mapping (spam is never revealed)');

-- ---------------------------------------------------------------------------
-- Who can submit
-- ---------------------------------------------------------------------------
select is(pg_temp.state_as(null, null, pg_temp.submit_sql()), 'ES401', 'anon cannot submit');
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000003', 'aal1', pg_temp.submit_sql()), 'ES403', 'a pending applicant cannot submit');
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000001', 'aal1', pg_temp.submit_sql()), 'ES403', 'editor A cannot submit');
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000002', 'aal1', pg_temp.submit_sql()), 'ES403', 'editor B cannot submit');
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000012', 'aal1', pg_temp.submit_sql()), 'ES403', 'a revoked client user cannot submit');
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000041', 'aal1', pg_temp.submit_sql()), 'ES403', 'a user of an archived client cannot submit');
select is(pg_temp.state_as('c5000000-0000-0000-0000-00000000000a', 'aal1', pg_temp.submit_sql()), 'ES403', 'admin without MFA cannot submit');
select is(pg_temp.state_as('c5000000-0000-0000-0000-00000000000a', 'aal2', pg_temp.submit_sql()), 'ES403', 'admin with MFA cannot submit (not a client account)');
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000011', 'aal1', pg_temp.submit_sql()), 'ok', 'an active client user can submit');

-- ---------------------------------------------------------------------------
-- Validation (same rules as the public form)
-- ---------------------------------------------------------------------------
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.client_submit_project('long_form', '  ', null, null, null, null, null, 'v') $$),
  'ES422', 'a description is required');
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.client_submit_project('no_such_service', 'x', null, null, null, null, null, 'v') $$),
  'ES422', 'the service type must be an active one');
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.client_submit_project('long_form', 'x', null, 'c7000000-0000-0000-0000-000000000002', null, null, null, 'v') $$),
  'ES422', 'an inactive budget option is refused');
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.client_submit_project('long_form', 'x', null, 'c7000000-0000-0000-0000-000000000001', null, null, null, 'v') $$),
  'ok', 'an active budget option is accepted');
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.client_submit_project('long_form', 'x', null, null, null, null, '[{"url": "http://example.com"}]', 'v') $$),
  'ES422', 'links must be https');
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.client_submit_project('long_form', 'x', null, null, null, null,
       (select jsonb_agg(jsonb_build_object('url', 'https://example.com/' || g)) from generate_series(1, 11) g), 'v') $$),
  'ES422', 'at most 10 links');
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.client_submit_project('long_form', 'x', null, null, null, null, '{"url": "https://example.com"}', 'v') $$),
  'ES422', 'links must be an array');
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.client_submit_project('long_form', 'x', null, null, null, null, '["https://example.com"]', 'v') $$),
  'ES422', 'each link must be an object');
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.client_submit_project('long_form', 'x', null, null, null, null, null, ' ') $$),
  'ES422', 'the privacy notice confirmation is required');
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.client_submit_project('long_form', repeat('x', 5001), null, null, null, null, null, 'v') $$),
  'ES422', 'an over-long description is refused with a user-safe error');

-- ---------------------------------------------------------------------------
-- A submission: lead only, contact details from the account, audit and notification
-- ---------------------------------------------------------------------------
select is(pg_temp.do_as('c5000000-0000-0000-0000-000000000011', 'aal1',
  'insert into ids select ''x1'', (' || pg_temp.submit_sql('X first request') || ')'),
  'ok', 'client X submits a project');
select results_eq(
  $$ select contact_name, company, email, phone, client_id, status::text, converted_project_id, service_type_code,
            budget_label, expected_deadline
     from public.client_inquiries where id = (select id from ids where kind = 'x1') $$,
  $$ values ('Xavier Real'::text, 'X Company'::text, 'c2a-client-x@test.local'::text, '+94 77 000 0000'::text,
            'c6000000-0000-0000-0000-000000000001'::uuid, 'new'::text, null::uuid, 'long_form'::text,
            'Prefer to discuss'::text, '2099-03-01'::date) $$,
  'the lead is linked to client X, has status new, no project, and contact details from the account');
select is((select count(*)::int from public.client_inquiry_links where inquiry_id = (select id from ids where kind = 'x1')),
  1, 'the reference link is stored');
select is_empty($$ select 1 from public.project_internal p where p.source_inquiry_id = (select id from ids where kind = 'x1') $$,
  'submitting creates no project');
select ok(exists (select 1 from public.activity_logs a
  where a.action = 'inquiry.submitted' and a.entity_id = (select id::text from ids where kind = 'x1')
    and a.actor_id = 'c5000000-0000-0000-0000-000000000011'
    and a.details ->> 'client_id' = 'c6000000-0000-0000-0000-000000000001'),
  'the submission is audited with the client user as actor and the client id');
select is_empty($$ select a.id from public.activity_logs a
  where a.entity_type = 'client_inquiry' and a.entity_id = (select id::text from ids where kind = 'x1')
    and (a.details::text ~ '@|Xavier|X Company|launch|first request'
         or exists (select 1 from jsonb_object_keys(a.details) k where k not in ('from', 'to', 'client_id'))) $$,
  'the audit details hold ids and statuses only (no personal data)');
select ok(exists (select 1 from public.notifications n
  where n.kind = 'inquiry_new' and n.entity_id = (select id from ids where kind = 'x1')
    and n.recipient_id = 'c5000000-0000-0000-0000-00000000000a'),
  'admins get the existing inquiry_new notification');
select ok(not exists (select 1 from public.notifications n
  where n.entity_id = (select id from ids where kind = 'x1') and n.recipient_id <> 'c5000000-0000-0000-0000-00000000000a'
    and n.recipient_id in ('c5000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000002',
                      'c5000000-0000-0000-0000-000000000011', 'c5000000-0000-0000-0000-000000000021')),
  'no editor or client is notified of the lead');

-- A client user without a name on the account: the client record's name is used.
select is(pg_temp.do_as('c5000000-0000-0000-0000-000000000021', 'aal1',
  'insert into ids select ''y1'', (' || pg_temp.submit_sql('Y request') || ')'), 'ok', 'client Y submits a project');
select results_eq(
  $$ select contact_name, company, email, phone, client_id from public.client_inquiries where id = (select id from ids where kind = 'y1') $$,
  $$ values ('Client Y'::text, null::text, 'c2a-client-y@test.local'::text, null::text, 'c6000000-0000-0000-0000-000000000002'::uuid) $$,
  'without an account name the client name is used; contact details still come from the account');

-- ---------------------------------------------------------------------------
-- Rate limit: 10 per client per 24 hours
-- ---------------------------------------------------------------------------
select is((select string_agg(pg_temp.do_as('c5000000-0000-0000-0000-000000000011', 'aal1',
  'insert into ids select ''x' || g || ''', (' || pg_temp.submit_sql('X request ' || g) || ')'), ',')
  from generate_series(2, 10) g), 'ok,ok,ok,ok,ok,ok,ok,ok,ok', 'client X submits nine more (ten in 24 hours)');
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000011', 'aal1', pg_temp.submit_sql()),
  'ES409', 'the eleventh submission within 24 hours is refused (ES409)');
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000021', 'aal1', pg_temp.submit_sql()),
  'ok', 'client Y is not affected by client X''s limit');
update public.client_inquiries set submitted_at = now() - interval '25 hours' where id = (select id from ids where kind = 'x10');
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000011', 'aal1', pg_temp.submit_sql()),
  'ok', 'requests older than 24 hours no longer count');

-- ---------------------------------------------------------------------------
-- client_list_requests
-- ---------------------------------------------------------------------------
select is(pg_temp.state_as(null, null, 'select * from public.client_list_requests()'), 'ES401', 'anon cannot list requests');
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000003', 'aal1', 'select * from public.client_list_requests()'), 'ES403', 'the applicant cannot list requests');
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000001', 'aal1', 'select * from public.client_list_requests()'), 'ES403', 'editor A cannot list requests');
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000002', 'aal1', 'select * from public.client_list_requests()'), 'ES403', 'editor B cannot list requests');
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000012', 'aal1', 'select * from public.client_list_requests()'), 'ES403', 'a revoked client user cannot list requests');
select is(pg_temp.state_as('c5000000-0000-0000-0000-000000000041', 'aal1', 'select * from public.client_list_requests()'), 'ES403', 'a user of an archived client cannot list requests');
select is(pg_temp.state_as('c5000000-0000-0000-0000-00000000000a', 'aal2', 'select * from public.client_list_requests()'), 'ES403', 'admin (MFA) is not a client');

select is(pg_temp.visible_as('c5000000-0000-0000-0000-000000000011', 'aal1', 'select * from public.client_list_requests()'),
  10::bigint, 'client X lists its ten requests');
select is(pg_temp.visible_as('c5000000-0000-0000-0000-000000000011', 'aal1',
  $$ select * from public.client_list_requests() r
     where r.id not in (select k.id from ids k where k.kind ~ '^x\d+$') $$),
  0::bigint, 'client X sees no request of another client');
select is(pg_temp.visible_as('c5000000-0000-0000-0000-000000000021', 'aal1',
  $$ select * from public.client_list_requests() r where r.id = (select id from ids where kind = 'x1') $$),
  0::bigint, 'client Y cannot see client X''s request');
select is(pg_temp.visible_as('c5000000-0000-0000-0000-000000000021', 'aal1', 'select * from public.client_list_requests()'),
  1::bigint, 'client Y lists only its own request');
select is(pg_temp.value_as('c5000000-0000-0000-0000-000000000011', 'aal1',
  $$ select request_status || '|' || coalesce(project_id::text, '-') || '|' || description from public.client_list_requests()
     where id = (select id from ids where kind = 'x1') $$),
  'received|-|X first request', 'a new request reads Received, with the description the client wrote');
select is(pg_temp.visible_as('c5000000-0000-0000-0000-000000000011', 'aal1', 'select * from public.client_inquiries'),
  0::bigint, 'client X cannot read client_inquiries directly');
select is(pg_temp.visible_as('c5000000-0000-0000-0000-000000000001', 'aal1', 'select * from public.client_inquiries'),
  0::bigint, 'editor A cannot read client_inquiries');

-- Status changes by the admin are shown mapped.
select is(pg_temp.do_as('c5000000-0000-0000-0000-00000000000a', 'aal2', $$
  select public.admin_set_inquiry_status((select id from ids where kind = 'x2'), 'contacted', 'Internal note: called them');
  select public.admin_set_inquiry_status((select id from ids where kind = 'x3'), 'spam', null);
  select public.admin_set_inquiry_status((select id from ids where kind = 'x4'), 'declined', null) $$),
  'ok', 'the admin changes three request statuses (one with an internal note)');
select results_eq(
  $$ select k.kind, pg_temp.value_as('c5000000-0000-0000-0000-000000000011', 'aal1',
       format('select request_status from public.client_list_requests() where id = %L', k.id))
     from ids k where k.kind in ('x2', 'x3', 'x4') order by k.kind $$,
  $$ values ('x2', 'in_review'), ('x3', 'not_taken_forward'), ('x4', 'not_taken_forward') $$,
  'contacted reads In review; spam and declined read Not taken forward');
select is(pg_temp.value_as('c5000000-0000-0000-0000-000000000011', 'aal1',
  $$ select count(*) from public.client_list_requests() r where r::text ~* 'Internal note|spam|contacted|c5000000-0000-0000-0000-00000000000a' $$),
  '0', 'no internal note, raw status or admin id appears in the client''s list');

-- ---------------------------------------------------------------------------
-- Admin view and conversion
-- ---------------------------------------------------------------------------
select is(pg_temp.value_as('c5000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select c.name from public.client_inquiries i join public.clients c on c.id = i.client_id
     where i.id = (select id from ids where kind = 'x1') $$),
  'Client X', 'the admin (MFA) sees which client account the request came from');
select is(pg_temp.visible_as('c5000000-0000-0000-0000-00000000000a', 'aal1', 'select * from public.client_inquiries where client_id is not null'),
  0::bigint, 'the admin without MFA sees no requests');

select is(pg_temp.state_as('c5000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_convert_inquiry((select id from ids where kind = 'x1'),
       '{"brief_type": "fully_instructed", "client_id": "c6000000-0000-0000-0000-000000000002"}') $$),
  'ES409', 'a client-account request cannot be converted for another client');
select is(pg_temp.do_as('c5000000-0000-0000-0000-00000000000a', 'aal2',
  $$ insert into ids select 'px1', public.admin_convert_inquiry((select id from ids where kind = 'x1'), '{
       "brief_type": "fully_instructed", "deadline": "2099-03-01", "brief": {"instructions": "Cut"},
       "deliverables": [{"name": "Main"}]}') $$),
  'ok', 'the admin converts client X''s request');
select is((select client_id from public.project_internal where project_id = (select id from ids where kind = 'px1')),
  'c6000000-0000-0000-0000-000000000001'::uuid, 'conversion carries the client link to the project');
select is(pg_temp.do_as('c5000000-0000-0000-0000-00000000000a', 'aal2',
  $$ insert into ids select 'px2', public.admin_convert_inquiry((select id from ids where kind = 'x2'), '{
       "brief_type": "fully_instructed", "client_id": "c6000000-0000-0000-0000-000000000001"}') $$),
  'ok', 'naming the same client explicitly is accepted');
select is(pg_temp.value_as('c5000000-0000-0000-0000-000000000011', 'aal1',
  $$ select request_status || '|' || coalesce(project_id::text, '-') from public.client_list_requests()
     where id = (select id from ids where kind = 'x1') $$),
  'accepted|-', 'a converted request reads Accepted, with no link while the project is a draft');

select is(pg_temp.do_as('c5000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_set_project_status((select id from ids where kind = 'px1'), 'open', 'Opening') $$),
  'ok', 'the admin opens the project');
select is(pg_temp.value_as('c5000000-0000-0000-0000-000000000011', 'aal1',
  $$ select request_status || '|' || (project_id = (select id from ids where kind = 'px1'))::text from public.client_list_requests()
     where id = (select id from ids where kind = 'x1') $$),
  'accepted|true', 'once visible, the request links to the project');
select is(pg_temp.value_as('c5000000-0000-0000-0000-000000000011', 'aal1',
  $$ select count(*) from public.client_list_projects() where id = (select id from ids where kind = 'px1') $$),
  '1', 'client X sees the project in its projects list');
select is(pg_temp.value_as('c5000000-0000-0000-0000-000000000021', 'aal1',
  $$ select count(*) from public.client_list_requests() where project_id = (select id from ids where kind = 'px1') $$),
  '0', 'client Y never sees the project link');
select is(pg_temp.value_as('c5000000-0000-0000-0000-000000000021', 'aal1',
  $$ select public.client_get_project((select id from ids where kind = 'px1'))::text $$),
  null, 'client Y cannot open client X''s project');

-- Archiving the project removes the link again (C1 visibility rules).
update public.projects set archived_at = now() where id = (select id from ids where kind = 'px1');
select is(pg_temp.value_as('c5000000-0000-0000-0000-000000000011', 'aal1',
  $$ select coalesce(project_id::text, '-') from public.client_list_requests() where id = (select id from ids where kind = 'x1') $$),
  '-', 'an archived project is not linked');
update public.projects set archived_at = null where id = (select id from ids where kind = 'px1');

-- Public-form inquiries still convert by email matching (no client_id).
insert into public.client_inquiries (id, contact_name, email, service_type_code, service_type_label, description,
  budget_label, privacy_notice_version)
values ('c8000000-0000-0000-0000-000000000001', 'Public Person', 'c2a-public@example.com', 'long_form', 'Long-form video',
  'Public request', 'Prefer to discuss', 'v');
select is(pg_temp.do_as('c5000000-0000-0000-0000-00000000000a', 'aal2',
  $$ insert into ids select 'ppub', public.admin_convert_inquiry('c8000000-0000-0000-0000-000000000001', '{"brief_type": "fully_instructed"}') $$),
  'ok', 'a public-form inquiry still converts');
select is((select c.email from public.project_internal pi join public.clients c on c.id = pi.client_id
           where pi.project_id = (select id from ids where kind = 'ppub')),
  'c2a-public@example.com', 'a public-form inquiry still matches or creates a client by email');

-- ---------------------------------------------------------------------------
-- The link is fixed, except to follow a client merge
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ update public.client_inquiries set client_id = 'c6000000-0000-0000-0000-000000000002' where id = (select id from ids where kind = 'x5') $$,
  'ES409', null, 'the client of a request cannot be rewritten');
select throws_ok(
  $$ update public.client_inquiries set client_id = 'c6000000-0000-0000-0000-000000000002' where id = 'c8000000-0000-0000-0000-000000000001' $$,
  'ES409', null, 'a public-form inquiry cannot be attached to a client afterwards');
select is(pg_temp.do_as('c5000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_merge_clients('c6000000-0000-0000-0000-000000000002', 'c6000000-0000-0000-0000-000000000004') $$),
  'ok', 'the admin merges client Y into client W');
select is((select client_id from public.client_inquiries where id = (select id from ids where kind = 'y1')),
  'c6000000-0000-0000-0000-000000000004'::uuid, 'the request follows the merge');
select is(pg_temp.value_as('c5000000-0000-0000-0000-000000000021', 'aal1',
  $$ select count(*) from public.client_list_requests() where id = (select id from ids where kind = 'y1') $$),
  '1', 'client Y''s user (moved with the merge) still sees the request');

select ok(exists (select 1 from public.activity_logs a
  where a.action = 'client_inquiry.moved_on_merge' and a.entity_id = 'c6000000-0000-0000-0000-000000000002'
    and a.details = jsonb_build_object('to_client_id', 'c6000000-0000-0000-0000-000000000004'::uuid, 'count', 1)),
  'the move of requests on merge is audited with ids and a count only');
select throws_ok(
  $$ update public.client_inquiries set client_id = 'c6000000-0000-0000-0000-000000000002' where id = (select id from ids where kind = 'y1') $$,
  'ES409', null, 'a request cannot be moved back to the merged (source) client');
select throws_ok(
  $$ update public.client_inquiries set client_id = null where id = (select id from ids where kind = 'x5') $$,
  'ES409', null, 'the client link cannot be removed');
select is(pg_temp.do_as('c5000000-0000-0000-0000-00000000000a', 'aal2',
  $$ insert into ids select 'py1', public.admin_convert_inquiry((select id from ids where kind = 'y1'), '{"brief_type": "fully_instructed"}') $$),
  'ok', 'a request of a merged client converts');
select is((select client_id from public.project_internal where project_id = (select id from ids where kind = 'py1')),
  'c6000000-0000-0000-0000-000000000004'::uuid, 'after a merge the project goes to the kept client');

-- Client V: a user without a name or phone on the account (client name and phone are used).
select is(pg_temp.do_as('c5000000-0000-0000-0000-000000000051', 'aal1',
  'insert into ids select ''v1'', (' || pg_temp.submit_sql('V request') || ')'), 'ok', 'client V submits a project');
select results_eq(
  $$ select contact_name, company, email, phone from public.client_inquiries where id = (select id from ids where kind = 'v1') $$,
  $$ values ('Client V'::text, 'V Ltd'::text, 'c2a-client-v@test.local'::text, '+94 11 555 5555'::text) $$,
  'without an account name or phone, the client record''s name and phone are used');
update public.clients set archived_at = now() where id = 'c6000000-0000-0000-0000-000000000005';
select is(pg_temp.state_as('c5000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_convert_inquiry((select id from ids where kind = 'v1'), '{"brief_type": "fully_instructed"}') $$),
  'ES409', 'a request of an archived client cannot be converted (restore the client first)');
select is(pg_temp.value_as('c5000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select (select status::text from public.client_inquiries where id = (select id from ids where kind = 'v1')) $$),
  'new', 'the refused conversion changed nothing');
update public.clients set archived_at = null where id = 'c6000000-0000-0000-0000-000000000005';

-- A public-form inquiry converted for an explicitly chosen client still works.
insert into public.client_inquiries (id, contact_name, email, service_type_code, service_type_label, description,
  budget_label, privacy_notice_version)
values ('c8000000-0000-0000-0000-000000000002', 'Public Two', 'c2a-public2@example.com', 'long_form', 'Long-form video',
  'Public request two', 'Prefer to discuss', 'v');
select is(pg_temp.do_as('c5000000-0000-0000-0000-00000000000a', 'aal2',
  $$ insert into ids select 'ppub2', public.admin_convert_inquiry('c8000000-0000-0000-0000-000000000002',
       '{"brief_type": "fully_instructed", "client_id": "c6000000-0000-0000-0000-000000000005"}') $$),
  'ok', 'a public-form inquiry converts for a chosen client');
select is((select client_id from public.project_internal where project_id = (select id from ids where kind = 'ppub2')),
  'c6000000-0000-0000-0000-000000000005'::uuid, 'the chosen client is used');

select is_empty($$ select a.id from public.activity_logs a
  where a.action = 'inquiry.converted'
    and a.entity_id in (select id::text from ids where kind in ('x1', 'x2', 'y1'))
    and (a.details::text ~ '@|Xavier|Client|launch|request'
         or exists (select 1 from jsonb_object_keys(a.details) k where k not in ('from', 'to', 'client_id'))) $$,
  'inquiry.converted audit details hold ids and statuses only');
select is(pg_temp.visible_as(null, null, 'select * from public.client_inquiries'), -1::bigint,
  'anon cannot read client_inquiries');
select is(pg_temp.visible_as('c5000000-0000-0000-0000-000000000002', 'aal1', 'select * from public.client_inquiries'),
  0::bigint, 'editor B cannot read client_inquiries');
select ok(pg_get_functiondef('public.client_submit_project(text, text, text, uuid, date, text, jsonb, text)'::regprocedure)
            ~* 'for\s+no\s+key\s+update'
      and pg_get_functiondef('public.client_submit_project(text, text, text, uuid, date, text, jsonb, text)'::regprocedure)
            ~* 'merged_into_id is not null',
  'client_submit_project locks the client (no key update) and re-checks archive/merge under the lock (the race itself is not testable here)');

-- ---------------------------------------------------------------------------
-- Error codes: never 42501 from the new functions
-- ---------------------------------------------------------------------------
select ok(pg_get_functiondef('public.client_submit_project(text, text, text, uuid, date, text, jsonb, text)'::regprocedure) !~ '42501'
      and pg_get_functiondef('public.client_list_requests()'::regprocedure) !~ '42501',
  'the new functions never raise 42501');

select * from finish();

rollback;
