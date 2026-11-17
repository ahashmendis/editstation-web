-- Client area C1: client_users, client_project_updates, the bank details setting, the status
-- mappings and the client/admin functions, as anon, pending applicant, editor A, editor B, a user
-- of client X, a user of client Y, a revoked client user, and admin with and without MFA.
begin;

create extension if not exists pgtap with schema extensions;

select plan(165);

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

-- People. admin ...0a, editor A ...01, editor B ...02, applicant ...03, client X user ...11,
-- second client X user (revoked later) ...12, client Y user ...21, invitable (created by the
-- invitation flow: app_metadata.client_invite, confirmed) ...31, self-registered ...32 (user_metadata
-- claims an invite, which must be ignored), invitation-created but unconfirmed ...33.
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, email_confirmed_at, encrypted_password) values
  ('c1000000-0000-0000-0000-00000000000a', 'ca-admin@test.local', '{}', '{}', now(), 'x'),
  ('c1000000-0000-0000-0000-000000000001', 'ca-editor-a@test.local', '{}', '{}', now(), 'x'),
  ('c1000000-0000-0000-0000-000000000002', 'ca-editor-b@test.local', '{}', '{}', now(), 'x'),
  ('c1000000-0000-0000-0000-000000000003', 'ca-applicant@test.local', '{}', '{}', now(), 'x'),
  ('c1000000-0000-0000-0000-000000000011', 'ca-client-x@test.local', '{}', '{"client_invite": true}', now(), 'x'),
  ('c1000000-0000-0000-0000-000000000012', 'ca-client-x2@test.local', '{}', '{"client_invite": true}', now(), 'x'),
  ('c1000000-0000-0000-0000-000000000021', 'ca-client-y@test.local', '{}', '{"client_invite": true}', now(), 'x'),
  ('c1000000-0000-0000-0000-000000000031', 'ca-invitable@test.local', '{}', '{"client_invite": true}', now(), 'x'),
  ('c1000000-0000-0000-0000-000000000032', 'ca-selfreg@test.local', '{"client_invite": true}', '{}', now(), 'x'),
  ('c1000000-0000-0000-0000-000000000033', 'ca-unconfirmed@test.local', '{}', '{"client_invite": true}', null, 'x');
select private.grant_admin_by_email('ca-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('c1000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000002');
insert into public.editor_applications (editor_id) values ('c1000000-0000-0000-0000-000000000003');

-- Clients X, Y, archived Z, and W (merge target).
insert into public.clients (id, name, email, archived_at) values
  ('c2000000-0000-0000-0000-000000000001', 'Client X', 'ca-x@example.com', null),
  ('c2000000-0000-0000-0000-000000000002', 'Client Y', 'ca-y@example.com', null),
  ('c2000000-0000-0000-0000-000000000003', 'Client Z', 'ca-z@example.com', now()),
  ('c2000000-0000-0000-0000-000000000004', 'Client W', 'ca-w@example.com', null);

-- Projects: PX (in progress, X), PX2 (draft, X), PXA (archived, X), PY (Y), PN (no client).
insert into public.projects (id, title, brief_type, status, first_opened_at, deadline, summary, proposed_amount, archived_at) values
  ('c3000000-0000-0000-0000-000000000001', 'CA project X', 'fully_instructed', 'in_progress', now(), '2099-01-31', 'Secret editor summary', 12345, null),
  ('c3000000-0000-0000-0000-000000000002', 'CA project X2', 'fully_instructed', 'draft', null, null, null, null, null),
  ('c3000000-0000-0000-0000-000000000003', 'CA project X archived', 'fully_instructed', 'draft', null, null, null, null, now()),
  ('c3000000-0000-0000-0000-000000000004', 'CA project Y', 'fully_instructed', 'open', now(), null, null, null, null),
  ('c3000000-0000-0000-0000-000000000005', 'CA project none', 'fully_instructed', 'open', now(), null, null, null, null);
insert into public.project_internal (project_id, client_id, client_price, internal_notes) values
  ('c3000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 20000, 'Internal note text'),
  ('c3000000-0000-0000-0000-000000000002', 'c2000000-0000-0000-0000-000000000001', null, null),
  ('c3000000-0000-0000-0000-000000000003', 'c2000000-0000-0000-0000-000000000001', null, null),
  ('c3000000-0000-0000-0000-000000000004', 'c2000000-0000-0000-0000-000000000002', null, null),
  ('c3000000-0000-0000-0000-000000000005', null, null, null);
insert into public.project_deliverables (project_id, name, format, notes) values
  ('c3000000-0000-0000-0000-000000000001', 'Main cut', 'MP4', 'Editor-only deliverable note');

-- Agreed terms and client milestones on PX: invoiced deposit, uninvoiced balance, one voided row.
-- Fixture only: the workflow guards are bypassed (replica mode) to place rows in a known state.
set local session_replication_role = replica;
-- Inserting a project creates its draft terms (version 1); mark them agreed.
update public.project_terms set id = 'c4000000-0000-0000-0000-000000000001', status = 'agreed', agreed_at = now()
where project_id = 'c3000000-0000-0000-0000-000000000001' and version = 1;
insert into public.client_milestones (project_id, terms_id, seq, kind, share_percent, amount, currency, invoice_issued_at, due_date, voided_at) values
  ('c3000000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001', 1, 'deposit', 50, 10000, 'LKR', now(), '2099-01-01', null),
  ('c3000000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001', 2, 'balance', 50, 10000, 'LKR', null, null, null),
  ('c3000000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001', 3, 'extra_work', null, 999, 'LKR', null, null, now());
set local session_replication_role = origin;

-- ---------------------------------------------------------------------------
-- Schema and privileges
-- ---------------------------------------------------------------------------
select has_table('public', 'client_users', 'client_users exists');
select has_table('public', 'client_project_updates', 'client_project_updates exists');
select ok((select bool_and(relrowsecurity) from pg_class
           where oid in ('public.client_users'::regclass, 'public.client_project_updates'::regclass)),
  'both new tables have RLS enabled');
select ok(not exists (
    select 1 from unnest(array['anon', 'authenticated']) r, unnest(array['public.client_users', 'public.client_project_updates']) t,
      unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE']) p
    where has_table_privilege(r, t, p)),
  'anon and authenticated have no table privilege on client_users or client_project_updates');
select is_empty($$ select key from public.app_settings where key = 'client_bank_details' $$,
  'bank details are not pre-filled (hidden until the owner supplies them)');
select ok(pg_get_functiondef('public.client_get_project(uuid)'::regprocedure) !~* 'proposed_amount|internal_notes|client_price|assignment|summary',
  'client_get_project never reads editor pay, notes, client price, assignments or the editor summary');

-- ---------------------------------------------------------------------------
-- Pure mappings
-- ---------------------------------------------------------------------------
select is_empty($$ select s from unnest(enum_range(null::public.project_status)) s
                   where private.client_status_key(s) is null $$,
  'every project status maps to a client-facing status');
select results_eq(
  $$ select t.s::text, private.client_status_key(t.s) from unnest(enum_range(null::public.project_status)) with ordinality t(s, n) order by t.n $$,
  $$ values ('draft', 'received'), ('open', 'planning'), ('assigned', 'planning'), ('in_progress', 'in_production'),
            ('in_review', 'in_production'), ('revision_requested', 'revisions_in_progress'),
            ('approved', 'finalising'), ('completed', 'completed'), ('on_hold', 'on_hold'),
            ('cancelled', 'cancelled') $$,
  'the client status mapping');
select results_eq(
  $$ values (private.client_payment_status_key('deposit', 'expected', null)),
            (private.client_payment_status_key('deposit', 'expected', now())),
            (private.client_payment_status_key('balance', 'received_unverified', now())),
            (private.client_payment_status_key('balance', 'verified', now())),
            (private.client_payment_status_key('refund', 'verified', now())) $$,
  $$ values ('not_invoiced'), ('awaiting_payment'), ('confirming'), ('paid'), ('refunded') $$,
  'the client payment status mapping');

-- ---------------------------------------------------------------------------
-- admin_invite_client_user
-- ---------------------------------------------------------------------------
select is(pg_temp.state_as(null, null,
  $$ select public.admin_invite_client_user('c2000000-0000-0000-0000-000000000001', 'ca-invitable@test.local') $$),
  'ES401', 'anon cannot invite');
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal1',
  $$ select public.admin_invite_client_user('c2000000-0000-0000-0000-000000000001', 'ca-invitable@test.local') $$),
  'ES403', 'admin without MFA cannot invite');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000001', 'aal1',
  $$ select public.admin_invite_client_user('c2000000-0000-0000-0000-000000000001', 'ca-invitable@test.local') $$),
  'ES403', 'editor A cannot invite');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000003', 'aal1',
  $$ select public.admin_invite_client_user('c2000000-0000-0000-0000-000000000001', 'ca-invitable@test.local') $$),
  'ES403', 'the applicant cannot invite');

select is(pg_temp.do_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_invite_client_user('c2000000-0000-0000-0000-000000000001', '  CA-Client-X@test.local ') $$),
  'ok', 'admin invites the client X user (email normalised)');
select is(pg_temp.do_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_invite_client_user('c2000000-0000-0000-0000-000000000001', 'ca-client-x2@test.local') $$),
  'ok', 'admin invites a second client X user');
select is(pg_temp.do_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_invite_client_user('c2000000-0000-0000-0000-000000000002', 'ca-client-y@test.local') $$),
  'ok', 'admin invites the client Y user');

select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.admin_invite_client_user('c2000000-0000-0000-0000-000000000001', 'ca-invitable@test.local') $$),
  'ES403', 'a client user cannot invite');
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_invite_client_user('c2000000-0000-0000-0000-000000000001', 'ca-editor-a@test.local') $$),
  'ES409', 'an active editor cannot become a client user');
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_invite_client_user('c2000000-0000-0000-0000-000000000001', 'ca-applicant@test.local') $$),
  'ES409', 'an applicant cannot become a client user');
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_invite_client_user('c2000000-0000-0000-0000-000000000001', 'ca-admin@test.local') $$),
  'ES409', 'an admin cannot become a client user');
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_invite_client_user('c2000000-0000-0000-0000-000000000001', 'ca-selfreg@test.local') $$),
  'ES409', 'a self-registered account cannot be linked (user_metadata is ignored)');
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_invite_client_user('c2000000-0000-0000-0000-000000000001', 'ca-unconfirmed@test.local') $$),
  'ES409', 'an unconfirmed account cannot be linked');
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_invite_client_user('c2000000-0000-0000-0000-000000000001', 'nobody@test.local') $$),
  'ES422', 'an email with no account is refused (the app creates the account first)');
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_invite_client_user('c2000000-0000-0000-0000-000000000001', 'not-an-email') $$),
  'ES422', 'an invalid email is refused');
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_invite_client_user('c2000000-0000-0000-0000-000000000003', 'ca-invitable@test.local') $$),
  'ES409', 'an archived client cannot get new users');
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_invite_client_user('c2000000-0000-0000-0000-000000000001', 'ca-client-x@test.local') $$),
  'ES409', 'the same person cannot be invited twice');
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_invite_client_user('c2000000-0000-0000-0000-000000000002', 'ca-client-x@test.local') $$),
  'ES409', 'a client user cannot also belong to another client');
select is(pg_temp.do_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_invite_client_user('c2000000-0000-0000-0000-000000000001', 'ca-invitable@test.local') $$),
  'ok', 'an invitation-created account can be linked');
select ok((select count(*) = 4 from public.activity_logs where action = 'client_user.invited'),
  'each invitation wrote one audit row');
select is_empty($$ select id from public.activity_logs where action like 'client_user.%'
                   and (details::text like '%@%' or details::text like '%Client X%'
                        or not (details ?& array['client_id', 'user_id'])) $$,
  'invitation audit rows hold ids only (no email or name)');

-- ---------------------------------------------------------------------------
-- admin_revoke_client_user
-- ---------------------------------------------------------------------------
create temp table ids (kind text primary key, id uuid not null);
grant select on ids to authenticated, anon;
insert into ids select 'x2', id from public.client_users where user_id = 'c1000000-0000-0000-0000-000000000012';
insert into ids select 'x1', id from public.client_users where user_id = 'c1000000-0000-0000-0000-000000000011';

select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal1',
  $$ select public.admin_revoke_client_user((select id from ids where kind = 'x2')) $$),
  'ES403', 'admin without MFA cannot revoke');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.admin_revoke_client_user((select id from ids where kind = 'x2')) $$),
  'ES403', 'a client user cannot revoke');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000002', 'aal1',
  $$ select public.admin_revoke_client_user((select id from ids where kind = 'x2')) $$),
  'ES403', 'editor B cannot revoke');
select is(pg_temp.do_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_revoke_client_user((select id from ids where kind = 'x2')) $$),
  'ok', 'admin revokes the second client X user');
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_revoke_client_user((select id from ids where kind = 'x2')) $$),
  'ES409', 'revoking twice is refused');
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_revoke_client_user(gen_random_uuid()) $$),
  'ES422', 'revoking an unknown row is refused');
select ok(exists (select 1 from public.activity_logs where action = 'client_user.revoked'
                  and entity_id = (select id::text from ids where kind = 'x2')),
  'the revocation is audited');

-- ---------------------------------------------------------------------------
-- admin_list_client_users
-- ---------------------------------------------------------------------------
select is(pg_temp.value_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select count(*) from public.admin_list_client_users('c2000000-0000-0000-0000-000000000001') $$),
  '3', 'admin lists the three client X users (revoked included)');
select is(pg_temp.value_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select count(*) from public.admin_list_client_users(null) where revoked_at is null $$),
  '3', 'admin lists every active client user when no client is given');
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal1',
  $$ select * from public.admin_list_client_users(null) $$), 'ES403', 'admin without MFA cannot list client users');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select * from public.admin_list_client_users(null) $$), 'ES403', 'a client user cannot list client users');
select is(pg_temp.state_as(null, null,
  $$ select * from public.admin_list_client_users(null) $$), 'ES401', 'anon cannot list client users');

-- ---------------------------------------------------------------------------
-- my_client_status (routing)
-- ---------------------------------------------------------------------------
select is(pg_temp.value_as('c1000000-0000-0000-0000-000000000011', 'aal1', 'select public.my_client_status()'),
  'active', 'client X user: active');
select is(pg_temp.value_as('c1000000-0000-0000-0000-000000000012', 'aal1', 'select public.my_client_status()'),
  'revoked', 'revoked client user: revoked');
select is(pg_temp.value_as('c1000000-0000-0000-0000-000000000001', 'aal1', 'select public.my_client_status()'),
  null, 'editor A: not a client');
select is(pg_temp.value_as('c1000000-0000-0000-0000-000000000003', 'aal1', 'select public.my_client_status()'),
  null, 'applicant: not a client');
select is(pg_temp.value_as('c1000000-0000-0000-0000-00000000000a', 'aal2', 'select public.my_client_status()'),
  null, 'admin: not a client');
select is(pg_temp.value_as(null, null, 'select public.my_client_status()'), null, 'anon: null');

-- ---------------------------------------------------------------------------
-- Guards: a client account is never an editor or an admin; history is fixed
-- ---------------------------------------------------------------------------
select throws_ok($$ update public.editor_profiles set access_status = 'active'
                    where user_id = 'c1000000-0000-0000-0000-000000000011' $$,
  'ES409', null, 'an active client user cannot be made an active editor (even by the table owner)');
select throws_ok($$ insert into public.admin_users (user_id, note) values ('c1000000-0000-0000-0000-000000000011', 'x') $$,
  'ES409', null, 'an active client user cannot be made an admin');
select throws_ok($$ insert into public.client_users (user_id, client_id)
                    values ('c1000000-0000-0000-0000-000000000002', 'c2000000-0000-0000-0000-000000000001') $$,
  'ES409', null, 'an editor cannot be linked to a client even directly');
select throws_ok($$ update public.client_users set revoked_at = null, revoked_by = null
                    where user_id = 'c1000000-0000-0000-0000-000000000012' $$,
  'ES409', null, 'a revocation cannot be undone');
select throws_ok($$ update public.client_users set user_id = 'c1000000-0000-0000-0000-000000000031'
                    where user_id = 'c1000000-0000-0000-0000-000000000011' $$,
  'ES409', null, 'a membership cannot be moved to another account');

-- ---------------------------------------------------------------------------
-- Client reads: client_list_projects
-- ---------------------------------------------------------------------------
select is(pg_temp.value_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select string_agg(id::text || ':' || client_status, ',' order by id) from public.client_list_projects() $$),
  'c3000000-0000-0000-0000-000000000001:in_production',
  'client X user sees only client X''s projects past draft and not archived, with the mapped status');
select is(pg_temp.value_as('c1000000-0000-0000-0000-000000000021', 'aal1',
  $$ select string_agg(id::text, ',') from public.client_list_projects() $$),
  'c3000000-0000-0000-0000-000000000004', 'client Y user sees only client Y''s project');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000012', 'aal1',
  $$ select * from public.client_list_projects() $$), 'ES403', 'a revoked client user sees nothing at once');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000001', 'aal1',
  $$ select * from public.client_list_projects() $$), 'ES403', 'editor A cannot list client projects');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000002', 'aal1',
  $$ select * from public.client_list_projects() $$), 'ES403', 'editor B cannot list client projects');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000003', 'aal1',
  $$ select * from public.client_list_projects() $$), 'ES403', 'the applicant cannot list client projects');
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select * from public.client_list_projects() $$), 'ES403', 'admin (MFA) is not a client');
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal1',
  $$ select * from public.client_list_projects() $$), 'ES403', 'admin without MFA is not a client');
select is(pg_temp.state_as(null, null,
  $$ select * from public.client_list_projects() $$), 'ES401', 'anon must sign in');

-- ---------------------------------------------------------------------------
-- Client reads: client_get_project
-- ---------------------------------------------------------------------------
-- Two updates on PX (one withdrawn later), one on PY.
select is(pg_temp.do_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_publish_client_update('c3000000-0000-0000-0000-000000000001', '  Rough cut is underway. ') $$),
  'ok', 'admin publishes an update on PX');
select is(pg_temp.do_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_publish_client_update('c3000000-0000-0000-0000-000000000001', 'Oops, wrong project') $$),
  'ok', 'admin publishes a second update on PX');
select is(pg_temp.do_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_publish_client_update('c3000000-0000-0000-0000-000000000004', 'Y planning update') $$),
  'ok', 'admin publishes an update on PY');
insert into ids select 'oops', id from public.client_project_updates where body = 'Oops, wrong project';
select is(pg_temp.do_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_withdraw_client_update((select id from ids where kind = 'oops')) $$),
  'ok', 'admin withdraws the mistaken update');

create temp table px as select null::jsonb as j;
grant select, insert, delete on px to authenticated;
select is(pg_temp.do_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ delete from px; insert into px select public.client_get_project('c3000000-0000-0000-0000-000000000001') $$),
  'ok', 'client X user reads their project');

select set_eq($$ select jsonb_object_keys(j) from px $$,
  array['id', 'title', 'client_status', 'created_at', 'deliverables', 'updates', 'milestones'],
  'the client projection has exactly the client-safe keys');
select is((select j ->> 'client_status' from px), 'in_production', 'PX shows the mapped status, not the raw one');
select set_eq($$ select jsonb_object_keys(d) from px, jsonb_array_elements(j -> 'deliverables') d $$,
  array['name', 'format', 'resolution', 'aspect_ratio', 'duration_seconds'],
  'deliverables carry only name and format details (no notes)');
select is((select jsonb_array_length(j -> 'updates') from px), 1, 'only the published update is shown');
select is((select j -> 'updates' -> 0 ->> 'body' from px), 'Rough cut is underway.', 'the update text is trimmed');
select set_eq($$ select jsonb_object_keys(m) from px, jsonb_array_elements(j -> 'milestones') m $$,
  array['id', 'seq', 'kind', 'amount', 'currency', 'due_date', 'invoice_issued_at', 'received_at', 'payment_status'],
  'milestones carry only client-safe keys (no transfer reference, reasons or verifier)');
select is((select string_agg(m ->> 'payment_status', ',' order by (m ->> 'seq')::int) from px, jsonb_array_elements(j -> 'milestones') m),
  'awaiting_payment,not_invoiced', 'voided milestones are hidden; statuses are client labels');
select ok((select j::text !~* 'c1000000-0000-0000-0000-00000000000[12]|editor|proposed|12345|Internal note|Secret editor summary|20000|transfer|assignment|notes|deadline|2099-01-31' from px),
  'the client projection never contains an editor identifier, editor pay, notes, summary, client price or deadline');
select is(pg_temp.value_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.client_get_project('c3000000-0000-0000-0000-000000000002')::text $$),
  null, 'a draft project is hidden from its client');
select ok(pg_temp.value_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select string_agg(row_to_json(t)::text, ',') from public.client_list_projects() t $$) !~ 'deadline|2099',
  'the project list carries no deadline');

select is(pg_temp.value_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.client_get_project('c3000000-0000-0000-0000-000000000004')::text $$),
  null, 'client X user gets nothing for client Y''s project');
select is(pg_temp.value_as('c1000000-0000-0000-0000-000000000021', 'aal1',
  $$ select public.client_get_project('c3000000-0000-0000-0000-000000000001')::text $$),
  null, 'client Y user gets nothing for client X''s project');
select is(pg_temp.value_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.client_get_project('c3000000-0000-0000-0000-000000000003')::text $$),
  null, 'archived projects are hidden');
select is(pg_temp.value_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.client_get_project('c3000000-0000-0000-0000-000000000005')::text $$),
  null, 'a project with no client is hidden');
select is(pg_temp.value_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.client_get_project(gen_random_uuid())::text $$),
  null, 'an unknown id gets the same empty answer');
select is(pg_temp.value_as('c1000000-0000-0000-0000-000000000021', 'aal1',
  $$ select jsonb_array_length(public.client_get_project('c3000000-0000-0000-0000-000000000004') -> 'updates')::text $$),
  '1', 'client Y user sees client Y''s update');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000012', 'aal1',
  $$ select public.client_get_project('c3000000-0000-0000-0000-000000000001') $$), 'ES403', 'revoked user: refused');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000001', 'aal1',
  $$ select public.client_get_project('c3000000-0000-0000-0000-000000000001') $$), 'ES403', 'editor A: refused');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000003', 'aal1',
  $$ select public.client_get_project('c3000000-0000-0000-0000-000000000001') $$), 'ES403', 'applicant: refused');
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.client_get_project('c3000000-0000-0000-0000-000000000001') $$), 'ES403', 'admin: not a client');
select is(pg_temp.state_as(null, null,
  $$ select public.client_get_project('c3000000-0000-0000-0000-000000000001') $$), 'ES401', 'anon: must sign in');

-- ---------------------------------------------------------------------------
-- Client reads: client_get_payment_info and the bank details setting
-- ---------------------------------------------------------------------------
select is(pg_temp.value_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select coalesce(public.client_get_payment_info() ->> 'bank_details', 'HIDDEN') $$),
  'HIDDEN', 'no bank details are shown until the admin sets them');
select is(pg_temp.value_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select jsonb_array_length(public.client_get_payment_info() -> 'projects')::text $$),
  '1', 'payments cover only client X''s visible project (drafts hidden)');
select is(pg_temp.value_as('c1000000-0000-0000-0000-000000000021', 'aal1',
  $$ select (public.client_get_payment_info() -> 'projects' -> 0 ->> 'project_id') $$),
  'c3000000-0000-0000-0000-000000000004', 'client Y user sees only client Y''s payments');
select ok(pg_temp.value_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.client_get_payment_info()::text $$) !~* 'transfer|editor|verified_by|client_price|reason',
  'payment info holds no transfer references, editor data, verifier or reasons');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000012', 'aal1',
  $$ select public.client_get_payment_info() $$), 'ES403', 'revoked user: no payment info');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000002', 'aal1',
  $$ select public.client_get_payment_info() $$), 'ES403', 'editor B: no payment info');
select is(pg_temp.state_as(null, null,
  $$ select public.client_get_payment_info() $$), 'ES401', 'anon: no payment info');

select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal1',
  $$ select public.admin_set_bank_details('Bank: Test') $$), 'ES403', 'admin without MFA cannot set bank details');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.admin_set_bank_details('Bank: Test') $$), 'ES403', 'a client cannot set bank details');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000001', 'aal1',
  $$ select public.admin_set_bank_details('Bank: Test') $$), 'ES403', 'an editor cannot set bank details');
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_set_bank_details(repeat('a', 2001)) $$), 'ES422', 'over-long bank details are refused');
select is(pg_temp.do_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_set_bank_details(' Bank: Test Bank, account 000 ') $$), 'ok', 'admin sets the bank details');
select is(pg_temp.value_as('c1000000-0000-0000-0000-000000000021', 'aal1',
  $$ select public.client_get_payment_info() ->> 'bank_details' $$),
  'Bank: Test Bank, account 000', 'every client user sees the configured bank details');
select is(pg_temp.do_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_set_bank_details('   ') $$), 'ok', 'admin clears the bank details');
select is_empty($$ select key from public.app_settings where key = 'client_bank_details' $$,
  'clearing removes the setting (hidden again)');
select is_empty($$ select id from public.activity_logs where entity_id = 'client_bank_details' and details::text like '%Bank%' $$,
  'the bank details audit rows hold field names only');

-- ---------------------------------------------------------------------------
-- Admin: client updates
-- ---------------------------------------------------------------------------
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal1',
  $$ select public.admin_publish_client_update('c3000000-0000-0000-0000-000000000001', 'x') $$),
  'ES403', 'admin without MFA cannot publish');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.admin_publish_client_update('c3000000-0000-0000-0000-000000000001', 'x') $$),
  'ES403', 'a client cannot publish');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000001', 'aal1',
  $$ select public.admin_publish_client_update('c3000000-0000-0000-0000-000000000001', 'x') $$),
  'ES403', 'editor A cannot publish');
select is(pg_temp.state_as(null, null,
  $$ select public.admin_publish_client_update('c3000000-0000-0000-0000-000000000001', 'x') $$),
  'ES401', 'anon cannot publish');
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_publish_client_update('c3000000-0000-0000-0000-000000000001', '   ') $$),
  'ES422', 'an empty update is refused');
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_publish_client_update(gen_random_uuid(), 'x') $$),
  'ES422', 'an unknown project is refused');
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_publish_client_update('c3000000-0000-0000-0000-000000000003', 'x') $$),
  'ES409', 'an archived project cannot get updates');
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_withdraw_client_update((select id from ids where kind = 'oops')) $$),
  'ES409', 'withdrawing twice is refused');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.admin_withdraw_client_update((select id from ids where kind = 'oops')) $$),
  'ES403', 'a client cannot withdraw updates');
select is(pg_temp.value_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select (j ->> 'client_status') || ',' || (j ->> 'active_client_users') || ',' || jsonb_array_length(j -> 'updates')
     from (select public.admin_list_client_updates('c3000000-0000-0000-0000-000000000001') j) s $$),
  'in_production,2,2', 'admin sees the client-facing status, active client users and every update');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.admin_list_client_updates('c3000000-0000-0000-0000-000000000001') $$),
  'ES403', 'a client cannot list the admin view of updates');
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal1',
  $$ select public.admin_list_client_updates('c3000000-0000-0000-0000-000000000001') $$),
  'ES403', 'admin without MFA cannot list updates');
select throws_ok($$ update public.client_project_updates set body = 'Edited' where body = 'Rough cut is underway.' $$,
  'ES409', null, 'a published update cannot be edited (even by the table owner)');
select throws_ok($$ update public.client_project_updates set published = true, withdrawn_at = null, withdrawn_by = null
                    where id = (select id from ids where kind = 'oops') $$,
  'ES409', null, 'a withdrawn update cannot be republished');
select throws_ok($$ update public.client_project_updates set withdrawn_at = now() - interval '1 day'
                    where id = (select id from ids where kind = 'oops') $$,
  'ES409', null, 'a withdrawal time cannot be changed once set');
select throws_ok($$ update public.client_project_updates set withdrawn_by = 'c1000000-0000-0000-0000-000000000001'
                    where id = (select id from ids where kind = 'oops') $$,
  'ES409', null, 'a withdrawal author cannot be changed once set');
select is_empty($$ select id from public.activity_logs where action like 'client_update.%'
                   and (details::text like '%Rough%' or details::text like '%Oops%') $$,
  'update audit rows hold ids and field names only');

-- ---------------------------------------------------------------------------
-- Wider matrix: admin functions and client reads as anon, applicant, editor B, revoked user
-- ---------------------------------------------------------------------------
create temp table matrix (who uuid, label text);
grant select on matrix to authenticated, anon;
insert into matrix values (null, 'anon'), ('c1000000-0000-0000-0000-000000000003', 'applicant'),
  ('c1000000-0000-0000-0000-000000000002', 'editor B'), ('c1000000-0000-0000-0000-000000000012', 'revoked client user'),
  ('c1000000-0000-0000-0000-000000000011', 'client X user');
select is_empty($$ select m.label || ' ' || f.q from matrix m,
    (values ('select public.admin_withdraw_client_update((select id from ids where kind = ''oops''))'),
            ('select public.admin_list_client_updates(''c3000000-0000-0000-0000-000000000001'')'),
            ('select public.admin_set_bank_details(''x'')'),
            ('select public.admin_publish_client_update(''c3000000-0000-0000-0000-000000000001'', ''x'')'),
            ('select public.admin_invite_client_user(''c2000000-0000-0000-0000-000000000001'', ''ca-invitable@test.local'')'),
            ('select public.admin_revoke_client_user((select id from ids where kind = ''x1''))'),
            ('select * from public.admin_list_client_users(null)')) f(q)
  where pg_temp.state_as(m.who, 'aal1', f.q) not in ('ES401', 'ES403') $$,
  'anon, applicant, editor B, the revoked user and a client user are refused by every admin client-area function');
select is_empty($$ select m.label from matrix m
  where m.label <> 'client X user'
    and pg_temp.state_as(m.who, 'aal1', 'select public.client_get_payment_info()') not in ('ES401', 'ES403') $$,
  'anon, applicant, editor B and the revoked user get no payment info');

-- A client account cannot use editor or applicant functions.
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.save_editor_profile('Client X', null, null, null, null, null, null, null, null, '{}', '{}', '[]') $$),
  'ES403', 'a client user cannot save an editor profile');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.submit_editor_application('v1', 'v1') $$),
  'ES403', 'a client user cannot submit an editor application');
select throws_ok($$ insert into public.editor_applications (editor_id) values ('c1000000-0000-0000-0000-000000000011') $$,
  'ES409', null, 'no application row can be created for a client account, even directly');
select ok(pg_temp.state_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.respond_to_application_request(gen_random_uuid(), 'hello') $$) ~ '^ES4',
  'a client user cannot answer application requests');
select ok(pg_temp.state_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select * from public.editor_list_payments() $$) ~ '^ES4'
  or pg_temp.visible_as('c1000000-0000-0000-0000-000000000011', 'aal1', 'select * from public.editor_list_payments()') = 0,
  'a client user sees no editor payments');
select ok(pg_temp.state_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select * from public.editor_get_terms('c3000000-0000-0000-0000-000000000001') $$) ~ '^ES4'
  or pg_temp.visible_as('c1000000-0000-0000-0000-000000000011', 'aal1',
    $$ select * from public.editor_get_terms('c3000000-0000-0000-0000-000000000001') $$) = 0,
  'a client user cannot read editor terms of their own project');
select ok(pg_temp.state_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select * from public.get_assignment_gate(gen_random_uuid()) $$) ~ '^ES4'
  or pg_temp.visible_as('c1000000-0000-0000-0000-000000000011', 'aal1',
    'select * from public.get_assignment_gate(gen_random_uuid())') = 0,
  'a client user reads no assignment gate');
select ok(coalesce(pg_temp.value_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.editor_revision_gate(gen_random_uuid()) $$), 'ERR null') ~ '^ERR ES4|^ERR null$',
  'a client user reads no revision gate');
select ok(pg_temp.state_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.editor_get_payout_details() $$) ~ '^ES4',
  'a client user has no payout details');
insert into public.notifications (id, recipient_id, kind, entity_type, entity_id, title, body)
values ('c5000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'invitation', 'project',
        'c3000000-0000-0000-0000-000000000001', 'Editor A note', 'For editor A only');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.mark_notification_read('c5000000-0000-0000-0000-000000000001') $$),
  'ES422', 'a client user cannot mark another user''s notification read');
select is((select read_at from public.notifications where id = 'c5000000-0000-0000-0000-000000000001'), null,
  'and the notification stays unread');
select is(pg_temp.visible_as('c1000000-0000-0000-0000-000000000011', 'aal1', 'select 1 from public.notifications'), 0::bigint,
  'a client user reads no one else''s notifications');

-- ---------------------------------------------------------------------------
-- No table reads for client accounts (all reads go through the functions)
-- ---------------------------------------------------------------------------
create temp table probes (q text);
grant select on probes to authenticated, anon;
insert into probes values
  ('select 1 from public.projects'), ('select 1 from public.project_internal'), ('select 1 from public.clients'),
  ('select 1 from public.client_users'), ('select 1 from public.client_project_updates'),
  ('select 1 from public.client_milestones'), ('select 1 from public.project_deliverables'),
  ('select 1 from public.brief_versions'), ('select 1 from public.project_terms'),
  ('select 1 from public.assignments'), ('select 1 from public.negotiation_offers'),
  ('select 1 from public.project_notes'), ('select 1 from public.project_access'),
  ('select 1 from public.payments'), ('select 1 from public.project_assets'),
  ('select 1 from public.project_opportunities'), ('select 1 from public.opportunity_interests'),
  ('select 1 from public.submissions'), ('select 1 from public.app_settings'),
  ('select 1 from public.activity_logs'),
  ('select 1 from public.profiles where id <> (select auth.uid())'),
  ('select 1 from public.editor_profiles where user_id <> (select auth.uid())');

select is_empty($$ select q from probes where pg_temp.visible_as('c1000000-0000-0000-0000-000000000011', 'aal1', q) > 0 $$,
  'client X user reads no project, client, editor, assignment, pay, note, offer or opportunity rows directly');
select is_empty($$ select q from probes where pg_temp.visible_as('c1000000-0000-0000-0000-000000000021', 'aal1', q) > 0 $$,
  'client Y user reads none of those rows directly');
select is_empty($$ select q from probes where pg_temp.visible_as('c1000000-0000-0000-0000-000000000012', 'aal1', q) > 0 $$,
  'the revoked client user reads none of those rows directly');
select is(pg_temp.visible_as('c1000000-0000-0000-0000-000000000001', 'aal1', 'select 1 from public.client_users'), -1::bigint,
  'editor A cannot read client_users');
select is(pg_temp.visible_as('c1000000-0000-0000-0000-000000000002', 'aal1', 'select 1 from public.client_project_updates'), -1::bigint,
  'editor B cannot read client_project_updates');
select is(pg_temp.visible_as('c1000000-0000-0000-0000-00000000000a', 'aal2', 'select 1 from public.client_users'), -1::bigint,
  'even the admin reads client_users only through the admin functions');
select is(pg_temp.visible_as(null, null, 'select 1 from public.client_project_updates'), -1::bigint,
  'anon cannot read client_project_updates');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select * from public.editor_list_opportunities() $$), 'ES403', 'a client user cannot list editor opportunities');

-- ---------------------------------------------------------------------------
-- Client merge: active users follow their projects to the kept client
-- ---------------------------------------------------------------------------
select is(pg_temp.do_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_merge_clients('c2000000-0000-0000-0000-000000000002', 'c2000000-0000-0000-0000-000000000004') $$),
  'ok', 'admin merges client Y into client W');
select is((select client_id from public.client_users where user_id = 'c1000000-0000-0000-0000-000000000021' and revoked_at is null),
  'c2000000-0000-0000-0000-000000000004'::uuid, 'the client Y user now belongs to client W');
select is(pg_temp.value_as('c1000000-0000-0000-0000-000000000021', 'aal1',
  $$ select string_agg(id::text, ',') from public.client_list_projects() $$),
  'c3000000-0000-0000-0000-000000000004', 'and still sees the same project');

-- ---------------------------------------------------------------------------
-- Revocation applies at once, and the account can then be made an editor
-- ---------------------------------------------------------------------------
select is(pg_temp.do_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_revoke_client_user((select id from ids where kind = 'x1')) $$),
  'ok', 'admin revokes the client X user');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000011', 'aal1',
  $$ select public.client_get_project('c3000000-0000-0000-0000-000000000001') $$),
  'ES403', 'the same session is refused on its next call');
select is(pg_temp.value_as('c1000000-0000-0000-0000-000000000011', 'aal1', 'select public.my_client_status()'),
  'revoked', 'routing now reports the access as removed');

-- ---------------------------------------------------------------------------
-- Merged and archived clients
-- ---------------------------------------------------------------------------
select is(pg_temp.state_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_invite_client_user('c2000000-0000-0000-0000-000000000002', 'ca-client-x2@test.local') $$),
  'ES409', 'nobody can be invited to a merged client');
select is(pg_temp.do_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_update_client('c2000000-0000-0000-0000-000000000004', '{"archived": true}') $$),
  'ok', 'admin archives client W');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000021', 'aal1',
  $$ select * from public.client_list_projects() $$), 'ES403', 'users of an archived client lose access at once');
select is(pg_temp.state_as('c1000000-0000-0000-0000-000000000021', 'aal1',
  $$ select public.client_get_payment_info() $$), 'ES403', 'including payments');
select is(pg_temp.value_as('c1000000-0000-0000-0000-000000000021', 'aal1', 'select public.my_client_status()'),
  'revoked', 'routing reports the access as ended');
select is(pg_temp.do_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_update_client('c2000000-0000-0000-0000-000000000004', '{"archived": false}') $$),
  'ok', 'admin restores client W');
select is(pg_temp.value_as('c1000000-0000-0000-0000-000000000021', 'aal1',
  $$ select string_agg(id::text, ',') from public.client_list_projects() $$),
  'c3000000-0000-0000-0000-000000000004', 'restoring the client restores its users'' access');

-- ---------------------------------------------------------------------------
-- Re-inviting a revoked user (new row each time; history kept)
-- ---------------------------------------------------------------------------
select is(pg_temp.do_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_invite_client_user('c2000000-0000-0000-0000-000000000004', 'ca-client-x2@test.local') $$),
  'ok', 'a revoked user can be invited to a different client');
select is(pg_temp.value_as('c1000000-0000-0000-0000-000000000012', 'aal1',
  $$ select string_agg(id::text, ',') from public.client_list_projects() $$),
  'c3000000-0000-0000-0000-000000000004', 'and sees only that client''s projects');
select is(pg_temp.do_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_revoke_client_user((select id from public.admin_list_client_users(null)
     where user_id = 'c1000000-0000-0000-0000-000000000012' and revoked_at is null)) $$),
  'ok', 'admin removes that access again');
select is(pg_temp.do_as('c1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_invite_client_user('c2000000-0000-0000-0000-000000000001', 'ca-client-x2@test.local') $$),
  'ok', 'a revoked user can be re-invited to the same client');
select is((select count(*) from public.client_users where user_id = 'c1000000-0000-0000-0000-000000000012'),
  3::bigint, 'each invitation is its own row; earlier revocations stay on record');
select is(pg_temp.value_as('c1000000-0000-0000-0000-000000000012', 'aal1',
  $$ select string_agg(id::text, ',') from public.client_list_projects() $$),
  'c3000000-0000-0000-0000-000000000001', 'and sees client X''s project again');

-- ---------------------------------------------------------------------------
-- Function catalogue
-- ---------------------------------------------------------------------------
select is_empty($$ select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname in ('client_status_key', 'client_payment_status_key', 'require_client',
    'client_milestones_json', 'client_users_guard', 'refuse_client_as_editor', 'refuse_client_as_admin',
    'move_client_users_on_merge', 'client_project_updates_guard', 'refuse_client_application')
    and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
         or has_function_privilege('service_role', p.oid, 'execute')) $$,
  'the new private helpers are executable by no API role');
select ok((select bool_and(has_function_privilege('anon', f::regprocedure, 'execute')
                           and has_function_privilege('authenticated', f::regprocedure, 'execute'))
  from unnest(array['public.my_client_status()', 'public.client_list_projects()', 'public.client_get_project(uuid)',
    'public.client_get_payment_info()', 'public.admin_invite_client_user(uuid, text)',
    'public.admin_revoke_client_user(uuid)', 'public.admin_list_client_users(uuid)',
    'public.admin_publish_client_update(uuid, text)', 'public.admin_withdraw_client_update(uuid)',
    'public.admin_list_client_updates(uuid)', 'public.admin_set_bank_details(text)']) f),
  'all eleven new public functions exist and are executable by anon and authenticated');
select is_empty($$ select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and p.proname in ('my_client_status', 'client_list_projects',
    'client_get_project', 'client_get_payment_info', 'admin_invite_client_user', 'admin_revoke_client_user',
    'admin_list_client_users', 'admin_publish_client_update', 'admin_withdraw_client_update',
    'admin_list_client_updates', 'admin_set_bank_details', 'require_client', 'client_users_guard',
    'refuse_client_as_editor', 'refuse_client_as_admin', 'client_project_updates_guard')
    and pg_get_functiondef(p.oid) ~ '42501' $$,
  'no new function raises 42501');

select * from finish();

rollback;
