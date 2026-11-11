-- Phase 1: accounts, admin model, editor access gate, audit log.
-- Decisions: A (one admin at launch, TOTP MFA required, multi-admin capable),
--            L (editor access status none/active/suspended/revoked),
--            R (email verification required; configured in supabase/config.toml).
-- See docs/DATABASE_SCHEMA.md and docs/SECURITY_AND_PRIVACY.md.

-- ---------------------------------------------------------------------------
-- Secure-by-default privileges: nothing new in `public` is reachable by the
-- API roles unless a migration grants it explicitly.
-- ---------------------------------------------------------------------------
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;

-- Internal helpers live in a schema the Data API does not expose.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;
alter default privileges for role postgres in schema private
  revoke execute on functions from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------
create type public.editor_access_status as enum ('none', 'active', 'suspended', 'revoked');

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  full_name text check (char_length(full_name) between 1 and 200),
  phone text check (char_length(phone) between 1 and 40),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.profiles is
  'One row per account. Holds no role: admin status is in admin_users, editor access in editor_profiles.';

create table public.admin_users (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  granted_by uuid references public.profiles (id) on delete set null,
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_by uuid references public.profiles (id) on delete set null,
  note text check (char_length(note) <= 500)
);
create index admin_users_granted_by_idx on public.admin_users (granted_by);
create index admin_users_revoked_by_idx on public.admin_users (revoked_by);
comment on table public.admin_users is
  'Admin grants. Never written by sign-up. Bootstrap with private.grant_admin_by_email() as postgres.';

create table public.editor_profiles (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  access_status public.editor_access_status not null default 'none',
  access_changed_at timestamptz,
  access_changed_by uuid references public.profiles (id) on delete set null,
  access_change_reason text check (char_length(access_change_reason) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index editor_profiles_access_changed_by_idx on public.editor_profiles (access_changed_by);
-- Small partial index for the hot path: "is this user an active editor?"
create index editor_profiles_active_idx on public.editor_profiles (user_id)
  where access_status = 'active';
comment on column public.editor_profiles.access_status is
  'The only switch that grants editor access. Changed only by admin functions (Phase 2) or postgres.';

create table public.activity_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles (id) on delete set null,
  action text not null check (char_length(action) between 1 and 100),
  entity_type text not null check (char_length(entity_type) between 1 and 100),
  entity_id text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index activity_logs_entity_idx on public.activity_logs (entity_type, entity_id);
create index activity_logs_actor_idx on public.activity_logs (actor_id);
create index activity_logs_created_at_idx on public.activity_logs (created_at desc);
comment on table public.activity_logs is 'Append-only audit trail. Written only by triggers/functions.';

-- ---------------------------------------------------------------------------
-- RLS: enable on every table (default deny)
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.admin_users enable row level security;
alter table public.editor_profiles enable row level security;
alter table public.activity_logs enable row level security;

-- ---------------------------------------------------------------------------
-- Access helpers (security definer: they read tables the caller may not see)
-- ---------------------------------------------------------------------------

-- Admin account exists and is not revoked. Ignores MFA. Used for routing only;
-- authorisation must use private.is_admin().
create function private.is_admin_account()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.admin_users
    where user_id = (select auth.uid()) and revoked_at is null
  );
$$;

-- Admin with an MFA-verified session (decision A). This is the authorisation check.
create function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select auth.jwt() ->> 'aal'), '') = 'aal2'
    and exists (
      select 1 from public.admin_users
      where user_id = (select auth.uid()) and revoked_at is null
    );
$$;

-- Editor access is granted only by access_status = 'active' (decision L).
create function private.is_active_editor()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.editor_profiles
    where user_id = (select auth.uid()) and access_status = 'active'
  );
$$;

grant execute on function private.is_admin_account() to authenticated;
grant execute on function private.is_admin() to authenticated;
grant execute on function private.is_active_editor() to authenticated;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------
create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function private.set_updated_at();
create trigger editor_profiles_set_updated_at
  before update on public.editor_profiles
  for each row execute function private.set_updated_at();

-- New account: profile + editor_profiles with NO access. Deliberately ignores
-- raw_user_meta_data, which the user controls at sign-up.
create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email) values (new.id, new.email);
  insert into public.editor_profiles (user_id) values (new.id);
  insert into public.activity_logs (actor_id, action, entity_type, entity_id)
    values (null, 'account.registered', 'profile', new.id::text);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- Keep profiles.email in step with the verified auth email.
create function private.handle_user_email_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles set email = new.email where id = new.id;
  return new;
end;
$$;

create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row when (old.email is distinct from new.email)
  execute function private.handle_user_email_change();

-- Audit: admin grants and revocations.
create function private.audit_admin_users()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (
    (select auth.uid()),
    case
      when tg_op = 'INSERT' then 'admin.granted'
      when tg_op = 'DELETE' then 'admin.deleted'
      when new.revoked_at is not null and old.revoked_at is null then 'admin.revoked'
      when new.revoked_at is null and old.revoked_at is not null then 'admin.restored'
      else 'admin.updated'
    end,
    'admin_user',
    coalesce(new.user_id, old.user_id)::text,
    case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end
  );
  return coalesce(new, old);
end;
$$;

create trigger admin_users_audit
  after insert or update or delete on public.admin_users
  for each row execute function private.audit_admin_users();

-- Audit: every editor access status change.
create function private.audit_editor_access()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (
    (select auth.uid()),
    'editor.access_changed',
    'editor_profile',
    new.user_id::text,
    jsonb_build_object(
      'from', old.access_status,
      'to', new.access_status,
      'reason', new.access_change_reason
    )
  );
  return new;
end;
$$;

create trigger editor_profiles_audit_access
  after update of access_status on public.editor_profiles
  for each row when (old.access_status is distinct from new.access_status)
  execute function private.audit_editor_access();

-- Append-only audit log, even for roles that bypass RLS.
create function private.prevent_activity_log_changes()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'activity_logs is append-only' using errcode = '42501';
end;
$$;

create trigger activity_logs_append_only
  before update or delete on public.activity_logs
  for each row execute function private.prevent_activity_log_changes();

-- ---------------------------------------------------------------------------
-- Admin bootstrap (decision A). Callable only by postgres (SQL editor / psql).
-- ---------------------------------------------------------------------------
create function private.grant_admin_by_email(p_email text, p_note text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
begin
  select id into v_user_id from public.profiles where lower(email) = lower(p_email);
  if v_user_id is null then
    raise exception 'No account with email %', p_email;
  end if;

  insert into public.admin_users (user_id, granted_by, note)
  values (v_user_id, (select auth.uid()), p_note)
  on conflict (user_id) do update
    set revoked_at = null, revoked_by = null, note = excluded.note;

  return v_user_id;
end;
$$;

revoke execute on function private.grant_admin_by_email(text, text) from public, anon, authenticated, service_role;
revoke execute on function private.handle_new_user() from public, anon, authenticated;
revoke execute on function private.handle_user_email_change() from public, anon, authenticated;
revoke execute on function private.audit_admin_users() from public, anon, authenticated;
revoke execute on function private.audit_editor_access() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Table privileges (explicit; RLS then limits rows)
-- ---------------------------------------------------------------------------
revoke all on public.profiles, public.admin_users, public.editor_profiles, public.activity_logs
  from anon, authenticated;

grant select on public.profiles to authenticated;
grant update (full_name, phone) on public.profiles to authenticated;
grant select on public.admin_users to authenticated;
grant select on public.editor_profiles to authenticated;
grant select on public.activity_logs to authenticated;
-- anon: no table privileges at all in Phase 1.

-- ---------------------------------------------------------------------------
-- Policies
-- ---------------------------------------------------------------------------
create policy profiles_select_own_or_admin on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or (select private.is_admin()));

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create policy admin_users_select_own_or_admin on public.admin_users
  for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()));

create policy editor_profiles_select_own_or_admin on public.editor_profiles
  for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()));

create policy activity_logs_select_admin on public.activity_logs
  for select to authenticated
  using ((select private.is_admin()));
