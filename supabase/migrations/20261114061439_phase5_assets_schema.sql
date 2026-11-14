-- Phase 5 (1/2): assets schema. Spec docs/superpowers/specs/2026-11-14-phase5-6-editor-access-design.md §5.
-- Decisions B (early access), K (manual folder shares, logged), KB7 open (provider stored per row).
-- Admin-read-only through the API: no insert/update/delete grants or policies; all writes go
-- through public.admin_* security definer functions. Editor read policies arrive in Phase 6.

create type public.asset_provider as enum ('google_drive', 'dropbox', 'other');

-- ---------------------------------------------------------------------------
-- Project assets: links to footage and material (never the media itself)
-- ---------------------------------------------------------------------------
create table public.project_assets (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  label text not null check (char_length(label) between 1 and 200),
  url text not null check (url ~ '^https://[^\s]+$' and char_length(url) <= 2048),
  provider public.asset_provider not null default 'other',
  kind text check (char_length(kind) between 1 and 40),
  notes text check (char_length(notes) between 1 and 2000),
  -- Decision B: shown in the opportunity summary before confirmation.
  early_access boolean not null default false,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index project_assets_project_idx on public.project_assets (project_id, sort_order);
create trigger project_assets_set_updated_at
  before update on public.project_assets
  for each row execute function private.set_updated_at();

-- Decision B for references. Not part of the brief snapshot (toggling never creates a version).
alter table public.project_references add column early_access boolean not null default false;

-- ---------------------------------------------------------------------------
-- Folder shares made by hand in Drive/Dropbox (decision K). Admin-only.
-- ---------------------------------------------------------------------------
create table public.asset_access_grants (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  editor_id uuid not null references public.editor_profiles (user_id) on delete restrict,
  shared_with_email text not null check (
    shared_with_email = lower(btrim(shared_with_email))
    and char_length(shared_with_email) <= 254
    and shared_with_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  provider public.asset_provider not null,
  folder_url text check (folder_url ~ '^https://[^\s]+$' and char_length(folder_url) <= 2048),
  shared_by uuid references public.profiles (id) on delete set null,
  shared_at timestamptz not null default now(),
  revoked_by uuid references public.profiles (id) on delete set null,
  revoked_at timestamptz,
  revoke_reason text check (char_length(revoke_reason) between 1 and 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint asset_access_grants_revoke_chk check (
    revoked_at is not null or (revoked_by is null and revoke_reason is null))
);
create unique index asset_access_grants_live_key
  on public.asset_access_grants (project_id, editor_id, shared_with_email) where revoked_at is null;
create index asset_access_grants_editor_idx on public.asset_access_grants (editor_id);
create index asset_access_grants_shared_by_idx on public.asset_access_grants (shared_by);
create index asset_access_grants_revoked_by_idx on public.asset_access_grants (revoked_by);
create trigger asset_access_grants_set_updated_at
  before update on public.asset_access_grants
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS and privileges: admin select only
-- ---------------------------------------------------------------------------
alter table public.project_assets enable row level security;
alter table public.asset_access_grants enable row level security;

revoke all on public.project_assets, public.asset_access_grants from anon, authenticated;
grant select on public.project_assets, public.asset_access_grants to authenticated;

create policy project_assets_select_admin on public.project_assets
  for select to authenticated using ((select private.is_admin()));
create policy asset_access_grants_select_admin on public.asset_access_grants
  for select to authenticated using ((select private.is_admin()));
