-- Profile pictures (spec docs/superpowers/specs/2026-11-17-notification-emails-and-avatars-design.md
-- section B, owner-approved 2026-11-17).
--   * Any signed-in account (admin, applicant, editor) may set one optional picture.
--   * Visible only to its owner and to admins (MFA). Never clients, other editors or the public.
--   * Private Storage bucket `avatars` (2 MB, jpeg/png/webp). Object path `<user_id>/avatar.<ext>`.
--   * profiles.avatar_path is written only by public.set_my_avatar / public.clear_my_avatar (no
--     column grant). Audit rows hold ids and field names only.
-- The `storage` schema exists on hosted Supabase and in the local stack's initial schema (the CLI
-- applies Storage's schema even when the storage-api container is excluded), so no guard is used.

-- ---------------------------------------------------------------------------
-- Column (read through the existing profiles policy: own row or admin)
-- ---------------------------------------------------------------------------
alter table public.profiles add column avatar_path text;
comment on column public.profiles.avatar_path is
  'Object name in the private avatars bucket (<user_id>/avatar.<ext>). Written only by set_my_avatar/clear_my_avatar.';

-- ---------------------------------------------------------------------------
-- Bucket: private, 2 MB, three image types. Lifecycle columns stay null.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------------------------
-- storage.objects policies for the avatars bucket (authenticated only; anon gets nothing).
-- Writes: only the owner's own folder, and only the one allowed object name per extension.
-- Reads: the owner, or an admin with an MFA session.
-- Each policy is dropped first so the migration can be re-run against a project where the bucket
-- and policies already exist (storage.objects is shared with any future bucket).
-- ---------------------------------------------------------------------------
drop policy if exists avatars_select_own_or_admin on storage.objects;
create policy avatars_select_own_or_admin on storage.objects
  for select to authenticated
  using (
    bucket_id = 'avatars'
    and ((storage.foldername(name))[1] = (select auth.uid())::text or (select private.is_admin()))
  );

drop policy if exists avatars_insert_own on storage.objects;
create policy avatars_insert_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and name ~ '^[0-9a-f-]{36}/avatar\.(jpg|png|webp)$'
  );

drop policy if exists avatars_update_own on storage.objects;
create policy avatars_update_own on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and name ~ '^[0-9a-f-]{36}/avatar\.(jpg|png|webp)$'
  );

drop policy if exists avatars_delete_own on storage.objects;
create policy avatars_delete_own on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- ---------------------------------------------------------------------------
-- set_my_avatar: point the caller's profile at an object they already uploaded.
-- ---------------------------------------------------------------------------
create function public.set_my_avatar(p_path text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
begin
  if p_path is null
     or p_path !~ ('^' || v_uid::text || '/avatar\.(jpg|png|webp)$') then
    raise exception 'That picture cannot be used. Upload a JPEG, PNG or WebP image.' using errcode = 'ES422';
  end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'avatars' and o.name = p_path) then
    raise exception 'The picture upload did not finish. Please try again.' using errcode = 'ES422';
  end if;
  update public.profiles set avatar_path = p_path, updated_at = now() where id = v_uid;
  if not found then
    raise exception 'Please sign in.' using errcode = 'ES401';
  end if;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_uid, 'profile.avatar_set', 'profile', v_uid::text,
    jsonb_build_object('fields', jsonb_build_array('avatar_path')));
end;
$$;

-- ---------------------------------------------------------------------------
-- clear_my_avatar: remove the caller's picture reference (the server action deletes the object).
-- ---------------------------------------------------------------------------
create function public.clear_my_avatar()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
begin
  update public.profiles set avatar_path = null, updated_at = now()
  where id = v_uid and avatar_path is not null;
  if found then
    insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
    values (v_uid, 'profile.avatar_cleared', 'profile', v_uid::text,
      jsonb_build_object('fields', jsonb_build_array('avatar_path')));
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges: API roles execute and the body authorises (guardrails 000 and 046).
-- ---------------------------------------------------------------------------
revoke all on function public.set_my_avatar(text), public.clear_my_avatar() from public, anon, authenticated;
grant execute on function public.set_my_avatar(text), public.clear_my_avatar() to anon, authenticated;
