-- Profile pictures: the avatars bucket, its storage.objects policies and the two writer functions,
-- as admin (MFA and without), editor A, editor B, pending applicant and anon.
-- Storage rows are inserted straight into storage.objects (the policies are what the Storage API
-- enforces with the caller's JWT). The upload path through storage-api itself is not covered here.
-- The bucket's 2 MB size limit and JPEG/PNG/WebP MIME limit are enforced by storage-api, not by
-- Postgres, so they are covered by the storage-api smoke script (see docs/CHANGELOG.md), not pgTAP;
-- this file only checks the bucket row's configuration.
begin;

create extension if not exists pgtap with schema extensions;

select plan(50);

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

-- Runs p_sql as the given caller (null = anon) and returns 'ok' or the SQLSTATE. Rolls back.
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

-- Runs p_sql as the given caller (null = anon) and keeps its effect. Returns 'ok' or the SQLSTATE.
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

-- Counts the rows a query returns for the given caller (null = anon).
create function pg_temp.count_as(p_uid uuid, p_aal text, p_sql text)
returns bigint language plpgsql as $$
declare
  v bigint;
begin
  if p_uid is null then perform pg_temp.as_anon(); else perform pg_temp.as_user(p_uid, p_aal); end if;
  execute 'with q as (' || p_sql || ') select count(*) from q' into v;
  reset role;
  return v;
end;
$$;

-- ids: admin ...0a, editor A ...01, editor B ...02, pending applicant ...03
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('d1000000-0000-0000-0000-00000000000a', 'av-admin@test.local', '{}', '{}'),
  ('d1000000-0000-0000-0000-000000000001', 'av-editor-a@test.local', '{}', '{}'),
  ('d1000000-0000-0000-0000-000000000002', 'av-editor-b@test.local', '{}', '{}'),
  ('d1000000-0000-0000-0000-000000000003', 'av-applicant@test.local', '{}', '{}');
select private.grant_admin_by_email('av-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('d1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000002');

-- ---------------------------------------------------------------------------
-- Schema and bucket
-- ---------------------------------------------------------------------------
select has_column('public', 'profiles', 'avatar_path', 'profiles.avatar_path exists');
select ok(not has_column_privilege('authenticated', 'public.profiles', 'avatar_path', 'UPDATE')
      and not has_column_privilege('anon', 'public.profiles', 'avatar_path', 'UPDATE')
      and not has_column_privilege('authenticated', 'public.profiles', 'avatar_path', 'INSERT'),
  'no API role can write profiles.avatar_path directly');
select results_eq(
  $$ select public, file_size_limit, allowed_mime_types from storage.buckets where id = 'avatars' $$,
  $$ values (false, 2097152::bigint, array['image/jpeg', 'image/png', 'image/webp']) $$,
  'the avatars bucket is private, 2 MB, jpeg/png/webp only');
select ok((select relrowsecurity from pg_class where oid = 'storage.objects'::regclass),
  'storage.objects has RLS enabled');
select set_eq(
  $$ select polname::text from pg_policy where polrelid = 'storage.objects'::regclass and polname like 'avatars_%' $$,
  array['avatars_select_own_or_admin', 'avatars_insert_own', 'avatars_update_own', 'avatars_delete_own'],
  'the four avatars policies exist');
select is_empty(
  $$ select polname from pg_policy where polrelid = 'storage.objects'::regclass and polname like 'avatars_%'
     and not (polroles = array['authenticated'::regrole::oid]) $$,
  'avatars policies apply to authenticated only (anon has none)');

-- ---------------------------------------------------------------------------
-- Writes to storage.objects
-- ---------------------------------------------------------------------------
select is(pg_temp.do_as('d1000000-0000-0000-0000-000000000001', 'aal1',
  $$ insert into storage.objects (bucket_id, name) values ('avatars', 'd1000000-0000-0000-0000-000000000001/avatar.png') $$),
  'ok', 'editor A can upload into their own folder');
select is(pg_temp.do_as('d1000000-0000-0000-0000-000000000002', 'aal1',
  $$ insert into storage.objects (bucket_id, name) values ('avatars', 'd1000000-0000-0000-0000-000000000002/avatar.jpg') $$),
  'ok', 'editor B can upload into their own folder');
select is(pg_temp.do_as('d1000000-0000-0000-0000-000000000003', 'aal1',
  $$ insert into storage.objects (bucket_id, name) values ('avatars', 'd1000000-0000-0000-0000-000000000003/avatar.webp') $$),
  'ok', 'a pending applicant can upload into their own folder');
select is(pg_temp.do_as('d1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ insert into storage.objects (bucket_id, name) values ('avatars', 'd1000000-0000-0000-0000-00000000000a/avatar.png') $$),
  'ok', 'an admin can upload into their own folder');

select is(pg_temp.state_as('d1000000-0000-0000-0000-000000000002', 'aal1',
  $$ insert into storage.objects (bucket_id, name) values ('avatars', 'd1000000-0000-0000-0000-000000000001/avatar.webp') $$),
  '42501', 'editor B cannot upload into editor A''s folder');
select is(pg_temp.state_as('d1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ insert into storage.objects (bucket_id, name) values ('avatars', 'd1000000-0000-0000-0000-000000000001/avatar.webp') $$),
  '42501', 'not even an admin can upload into another user''s folder');
select is(pg_temp.state_as(null, null,
  $$ insert into storage.objects (bucket_id, name) values ('avatars', 'd1000000-0000-0000-0000-000000000001/avatar.webp') $$),
  '42501', 'anon cannot upload');
select is(pg_temp.state_as('d1000000-0000-0000-0000-000000000001', 'aal1',
  $$ insert into storage.objects (bucket_id, name) values ('avatars', 'd1000000-0000-0000-0000-000000000001/other.png') $$),
  '42501', 'the owner cannot upload under another object name');
select is(pg_temp.state_as('d1000000-0000-0000-0000-000000000001', 'aal1',
  $$ insert into storage.objects (bucket_id, name) values ('avatars', 'd1000000-0000-0000-0000-000000000001/x/avatar.png') $$),
  '42501', 'the owner cannot upload into a sub-folder');

select is(pg_temp.count_as('d1000000-0000-0000-0000-000000000002', 'aal1',
  $$ update storage.objects set metadata = '{"x":1}' where bucket_id = 'avatars'
     and name like 'd1000000-0000-0000-0000-000000000001/%' returning 1 $$),
  0::bigint, 'editor B cannot overwrite editor A''s picture');
select is(pg_temp.count_as(null, null,
  $$ update storage.objects set metadata = '{"x":1}' where bucket_id = 'avatars' returning 1 $$),
  0::bigint, 'anon cannot overwrite any picture');
select is(pg_temp.state_as('d1000000-0000-0000-0000-000000000001', 'aal1',
  $$ update storage.objects set name = 'd1000000-0000-0000-0000-000000000002/avatar.png'
     where name = 'd1000000-0000-0000-0000-000000000001/avatar.png' $$),
  '42501', 'the owner cannot move their picture into another user''s folder');
select is(pg_temp.count_as('d1000000-0000-0000-0000-000000000001', 'aal1',
  $$ update storage.objects set metadata = '{"mimetype":"image/png"}'
     where bucket_id = 'avatars' and name = 'd1000000-0000-0000-0000-000000000001/avatar.png' returning 1 $$),
  1::bigint, 'the owner can update their own picture (the upsert path)');
select is(pg_temp.state_as('d1000000-0000-0000-0000-000000000001', 'aal1',
  $$ update storage.objects set name = 'd1000000-0000-0000-0000-000000000001/other.png'
     where name = 'd1000000-0000-0000-0000-000000000001/avatar.png' $$),
  '42501', 'the owner cannot rename their picture to another object name');

-- Direct deletes need the storage escape hatch; the policies still decide which rows go.
select set_config('storage.allow_delete_query', 'true', true);
select is(pg_temp.count_as(null, null,
  $$ delete from storage.objects where bucket_id = 'avatars' returning 1 $$),
  0::bigint, 'anon cannot delete any picture');
select is(pg_temp.count_as('d1000000-0000-0000-0000-000000000002', 'aal1',
  $$ delete from storage.objects where bucket_id = 'avatars'
     and name like 'd1000000-0000-0000-0000-000000000001/%' returning 1 $$),
  0::bigint, 'editor B cannot delete editor A''s picture');
select is(pg_temp.count_as('d1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ delete from storage.objects where bucket_id = 'avatars'
     and name like 'd1000000-0000-0000-0000-000000000001/%' returning 1 $$),
  0::bigint, 'an admin cannot delete another user''s picture');
select is(pg_temp.count_as('d1000000-0000-0000-0000-000000000001', 'aal1',
  $$ delete from storage.objects where bucket_id = 'avatars'
     and name = 'd1000000-0000-0000-0000-000000000001/avatar.png' returning 1 $$),
  1::bigint, 'the owner can delete their own picture');
select is(pg_temp.do_as('d1000000-0000-0000-0000-000000000001', 'aal1',
  $$ insert into storage.objects (bucket_id, name) values ('avatars', 'd1000000-0000-0000-0000-000000000001/avatar.png') $$),
  'ok', 'the owner can upload a replacement');

-- ---------------------------------------------------------------------------
-- Reads of storage.objects
-- ---------------------------------------------------------------------------
create temp view av_objects with (security_invoker = true) as
  select name from storage.objects where bucket_id = 'avatars' and name like 'd1000000-%';
grant select on av_objects to anon, authenticated;

select is(pg_temp.count_as('d1000000-0000-0000-0000-000000000001', 'aal1', 'select * from av_objects'),
  1::bigint, 'editor A sees only their own picture');
select is(pg_temp.count_as('d1000000-0000-0000-0000-000000000002', 'aal1',
  $$ select * from av_objects where name like 'd1000000-0000-0000-0000-000000000001/%' $$),
  0::bigint, 'editor B cannot see editor A''s picture');
select is(pg_temp.count_as('d1000000-0000-0000-0000-000000000003', 'aal1', 'select * from av_objects'),
  1::bigint, 'the applicant sees only their own picture');
select is(pg_temp.count_as(null, null, 'select * from av_objects'), 0::bigint, 'anon sees no pictures');
select is(pg_temp.count_as('d1000000-0000-0000-0000-00000000000a', 'aal2', 'select * from av_objects'),
  4::bigint, 'an admin with MFA sees every picture');
select is(pg_temp.count_as('d1000000-0000-0000-0000-00000000000a', 'aal1', 'select * from av_objects'),
  1::bigint, 'an admin without MFA sees only their own picture');

-- ---------------------------------------------------------------------------
-- set_my_avatar / clear_my_avatar
-- ---------------------------------------------------------------------------
select is(pg_temp.do_as('d1000000-0000-0000-0000-000000000001', 'aal1',
  $$ select public.set_my_avatar('d1000000-0000-0000-0000-000000000001/avatar.png') $$),
  'ok', 'editor A can point their profile at their own uploaded picture');
select is((select avatar_path from public.profiles where id = 'd1000000-0000-0000-0000-000000000001'),
  'd1000000-0000-0000-0000-000000000001/avatar.png', 'editor A''s avatar_path is set');
select is(pg_temp.do_as('d1000000-0000-0000-0000-000000000002', 'aal1',
  $$ select public.set_my_avatar('d1000000-0000-0000-0000-000000000002/avatar.jpg') $$),
  'ok', 'editor B can set their own picture');
select is(pg_temp.do_as('d1000000-0000-0000-0000-000000000003', 'aal1',
  $$ select public.set_my_avatar('d1000000-0000-0000-0000-000000000003/avatar.webp') $$),
  'ok', 'a pending applicant can set their own picture');
select is(pg_temp.do_as('d1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.set_my_avatar('d1000000-0000-0000-0000-00000000000a/avatar.png') $$),
  'ok', 'an admin can set their own picture');
select is(pg_temp.state_as('d1000000-0000-0000-0000-000000000002', 'aal1',
  $$ select public.set_my_avatar('d1000000-0000-0000-0000-000000000001/avatar.png') $$),
  'ES422', 'set_my_avatar rejects another user''s path');
select is(pg_temp.state_as('d1000000-0000-0000-0000-000000000001', 'aal1',
  $$ select public.set_my_avatar('d1000000-0000-0000-0000-000000000001/avatar.gif') $$),
  'ES422', 'set_my_avatar rejects a bad extension');
select is(pg_temp.state_as('d1000000-0000-0000-0000-000000000001', 'aal1',
  $$ select public.set_my_avatar('d1000000-0000-0000-0000-000000000001/avatar.webp') $$),
  'ES422', 'set_my_avatar rejects a path that was never uploaded');
select is(pg_temp.state_as(null, null,
  $$ select public.set_my_avatar('d1000000-0000-0000-0000-000000000001/avatar.png') $$),
  'ES401', 'anon cannot call set_my_avatar');
select is(pg_temp.state_as(null, null, $$ select public.clear_my_avatar() $$),
  'ES401', 'anon cannot call clear_my_avatar');

select is(pg_temp.count_as('d1000000-0000-0000-0000-000000000002', 'aal1',
  $$ select avatar_path from public.profiles where id = 'd1000000-0000-0000-0000-000000000001' $$),
  0::bigint, 'editor B cannot read editor A''s avatar_path');
select ok(not has_table_privilege('anon', 'public.profiles', 'select'),
  'anon cannot read profiles at all (so no avatar_path)');
select is(pg_temp.count_as('d1000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select 1 from public.profiles where id = 'd1000000-0000-0000-0000-000000000001'
     and avatar_path = 'd1000000-0000-0000-0000-000000000001/avatar.png' $$),
  1::bigint, 'an admin with MFA reads editor A''s avatar_path');
select is(pg_temp.count_as('d1000000-0000-0000-0000-00000000000a', 'aal1',
  $$ select avatar_path from public.profiles where id = 'd1000000-0000-0000-0000-000000000001' $$),
  0::bigint, 'an admin without MFA cannot read another user''s avatar_path');

select is(pg_temp.do_as('d1000000-0000-0000-0000-000000000002', 'aal1', $$ select public.clear_my_avatar() $$),
  'ok', 'editor B clears their picture');
select ok((select avatar_path is null from public.profiles where id = 'd1000000-0000-0000-0000-000000000002')
      and (select avatar_path is not null from public.profiles where id = 'd1000000-0000-0000-0000-000000000001'),
  'clear_my_avatar clears only the caller''s own picture');

-- ---------------------------------------------------------------------------
-- Audit and function security
-- ---------------------------------------------------------------------------
select is((select count(*) from public.activity_logs
  where action in ('profile.avatar_set', 'profile.avatar_cleared')
    and entity_id in ('d1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000002')),
  3::bigint, 'set and clear each wrote one audit row');
select is_empty($$ select id from public.activity_logs
  where action in ('profile.avatar_set', 'profile.avatar_cleared')
    and (details <> '{"fields": ["avatar_path"]}'::jsonb or details::text like '%avatar.%') $$,
  'avatar audit rows hold the field name only (no path)');
select ok((select bool_and(p.prosecdef and 'search_path=""' = any (p.proconfig)
                           and has_function_privilege('anon', p.oid, 'execute')
                           and has_function_privilege('authenticated', p.oid, 'execute')
                           and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0))
           from pg_proc p where p.oid in ('public.set_my_avatar(text)'::regprocedure,
                                          'public.clear_my_avatar()'::regprocedure)),
  'both avatar functions are security definer, empty search_path, anon + authenticated, no PUBLIC');

select * from finish();

rollback;
