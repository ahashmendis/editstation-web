-- Phase 10: notifications schema, RLS (recipient only) and the mark-read functions.
begin;

create extension if not exists pgtap with schema extensions;

select plan(22);

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
  ('90000000-0000-0000-0000-00000000000a', 'p10n-admin@test.local', '{}', '{}'),
  ('90000000-0000-0000-0000-000000000001', 'p10n-editor-a@test.local', '{}', '{}'),
  ('90000000-0000-0000-0000-000000000002', 'p10n-editor-b@test.local', '{}', '{}'),
  ('90000000-0000-0000-0000-000000000003', 'p10n-applicant@test.local', '{}', '{}');
select private.grant_admin_by_email('p10n-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('90000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000002');

-- Schema
select has_table('public', 'notifications', 'notifications table exists');
select ok((select relrowsecurity from pg_class where oid = 'public.notifications'::regclass), 'RLS is on');
select has_table('private', 'notification_outbox', 'private outbox table exists');
select ok(not has_table_privilege('authenticated', 'public.notifications', 'insert')
      and not has_table_privilege('authenticated', 'public.notifications', 'update')
      and not has_table_privilege('authenticated', 'public.notifications', 'delete')
      and not has_table_privilege('anon', 'public.notifications', 'select'),
  'no direct writes; anon cannot read');
select ok(not has_table_privilege('authenticated', 'private.notification_outbox', 'select')
      and not has_table_privilege('anon', 'private.notification_outbox', 'select'),
  'the outbox is not readable through the API');

insert into public.notifications (id, recipient_id, kind, entity_type, entity_id, title, body) values
  ('90000000-0000-0000-0000-0000000000e1', '90000000-0000-0000-0000-000000000001', 'invitation', 'project', gen_random_uuid(), 't', 'b'),
  ('90000000-0000-0000-0000-0000000000e2', '90000000-0000-0000-0000-000000000001', 'payment_paid', 'payment', gen_random_uuid(), 't', 'b'),
  ('90000000-0000-0000-0000-0000000000e3', '90000000-0000-0000-0000-000000000002', 'invitation', 'project', gen_random_uuid(), 't', 'b'),
  ('90000000-0000-0000-0000-0000000000e4', '90000000-0000-0000-0000-000000000003', 'application_request', 'editor_application', gen_random_uuid(), 't', 'b'),
  ('90000000-0000-0000-0000-0000000000e5', '90000000-0000-0000-0000-00000000000a', 'inquiry_new', 'client_inquiry', gen_random_uuid(), 't', 'b');

-- RLS: each account sees only its own rows
select pg_temp.as_user('90000000-0000-0000-0000-000000000001');
select is((select count(*)::int from public.notifications), 2, 'editor A sees own two');
select pg_temp.as_user('90000000-0000-0000-0000-000000000002');
select is((select count(*)::int from public.notifications), 1, 'editor B sees own one');
select pg_temp.as_user('90000000-0000-0000-0000-000000000003');
select is((select count(*)::int from public.notifications), 1, 'pending applicant sees own one');
select pg_temp.as_user('90000000-0000-0000-0000-00000000000a', 'aal2');
select is((select count(*)::int from public.notifications), 1, 'admin sees own only (not editors'' rows)');
reset role;

-- mark_notification_read
select is(pg_temp.state_as(null, null, $$ select public.mark_notification_read('90000000-0000-0000-0000-0000000000e1') $$),
  'ES401', 'anon cannot mark read');
select is(pg_temp.state_as('90000000-0000-0000-0000-000000000002', 'aal1',
  $$ select public.mark_notification_read('90000000-0000-0000-0000-0000000000e1') $$),
  'ES422', 'editor B cannot mark editor A''s notification');
select is(pg_temp.state_as('90000000-0000-0000-0000-000000000003', 'aal1',
  $$ select public.mark_notification_read('90000000-0000-0000-0000-0000000000e1') $$),
  'ES422', 'an applicant cannot mark an editor''s notification');
select is((select read_at from public.notifications where id = '90000000-0000-0000-0000-0000000000e1'), null,
  'refused calls changed nothing');
select pg_temp.as_user('90000000-0000-0000-0000-000000000001');
select lives_ok($$ select public.mark_notification_read('90000000-0000-0000-0000-0000000000e1') $$,
  'editor A marks own notification read');
reset role;
select isnt((select read_at from public.notifications where id = '90000000-0000-0000-0000-0000000000e1'), null,
  'read_at is set');
select pg_temp.as_user('90000000-0000-0000-0000-000000000001');
select lives_ok($$ select public.mark_notification_read('90000000-0000-0000-0000-0000000000e1') $$,
  'marking an already-read notification is a no-op');

-- mark_all_notifications_read
select is(public.mark_all_notifications_read(), 1, 'mark all marks the one remaining unread');
reset role;
select is((select count(*)::int from public.notifications
  where recipient_id = '90000000-0000-0000-0000-000000000001' and read_at is null), 0, 'editor A has none unread');
select is((select count(*)::int from public.notifications
  where recipient_id <> '90000000-0000-0000-0000-000000000001' and read_at is null), 3, 'others are untouched');
select is(pg_temp.state_as(null, null, $$ select public.mark_all_notifications_read() $$), 'ES401',
  'anon cannot mark all');
select ok(has_function_privilege('anon', 'public.mark_notification_read(uuid)', 'execute')
      and has_function_privilege('authenticated', 'public.mark_all_notifications_read()', 'execute'),
  'functions follow the public-function rule');
select pg_temp.as_user('90000000-0000-0000-0000-000000000002');
select is(public.mark_all_notifications_read(), 1, 'editor B marks only own');

select * from finish();
rollback;
