-- Phase 12B (2/3): asset access schema (KB7, KB7a). Spec
-- docs/superpowers/specs/2026-11-15-phase12-commercial-terms-design.md §4.7.
-- Assets are client-provided Google Drive / Dropbox links. A working URL is never proof of access:
-- only an admin marks an asset verified. Editors report links they cannot open; the report is
-- append-only. Folder shares are made by the client, so the revoke checklist records a removal
-- request and its confirmation; ending an assignment never marks access as removed.

create type public.asset_access_status as enum ('awaiting_access', 'verified', 'inaccessible');
create type public.asset_access_type as enum ('editor_account', 'anyone_with_link');

-- ---------------------------------------------------------------------------
-- project_assets: description, access instructions, verification state
-- (editor-readable: no client identity or pricing columns)
-- ---------------------------------------------------------------------------
alter table public.project_assets
  add column description text check (char_length(description) between 1 and 2000),
  add column access_instructions text check (char_length(access_instructions) between 1 and 2000),
  add column access_status public.asset_access_status not null default 'awaiting_access',
  add column verified_by uuid references public.profiles (id) on delete set null,
  add column verified_at timestamptz,
  -- The confirmed editor says they can open it: a hint for the admin, never a verification. No
  -- editor id is stored (editors read this table); it is stale when older than the current
  -- assignment's confirmed_at.
  add column editor_confirmed_at timestamptz,
  add constraint project_assets_verified_chk check (
    (access_status = 'verified') = (verified_at is not null)
    and (verified_at is not null or verified_by is null));
create index project_assets_verified_by_idx on public.project_assets (verified_by);

-- ---------------------------------------------------------------------------
-- asset_access_grants: access type and the removal request / confirmation (admin-only table)
-- ---------------------------------------------------------------------------
alter table public.asset_access_grants
  add column access_type public.asset_access_type not null default 'editor_account',
  add column removal_requested_at timestamptz,
  add column removal_requested_by uuid references public.profiles (id) on delete set null,
  add column removal_confirmed_at timestamptz,
  add column removal_confirmed_by uuid references public.profiles (id) on delete set null,
  add constraint asset_access_grants_removal_chk check (
    (removal_requested_at is not null or removal_requested_by is null)
    and (removal_confirmed_at is not null or removal_confirmed_by is null)
    and (removal_confirmed_at is null or removal_requested_at is not null));
create index asset_access_grants_removal_requested_by_idx on public.asset_access_grants (removal_requested_by);
create index asset_access_grants_removal_confirmed_by_idx on public.asset_access_grants (removal_confirmed_by);

-- ---------------------------------------------------------------------------
-- asset_access_reports: append-only "I cannot open this" reports
-- ---------------------------------------------------------------------------
create table public.asset_access_reports (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  -- Null once the admin removes the asset from the list; the report itself stays.
  asset_id uuid references public.project_assets (id) on delete set null,
  editor_id uuid not null references public.editor_profiles (user_id) on delete restrict,
  note text not null check (char_length(note) between 1 and 1000),
  created_at timestamptz not null default now(),
  resolved_by uuid references public.profiles (id) on delete set null,
  resolved_at timestamptz,
  constraint asset_access_reports_resolved_chk check (resolved_at is not null or resolved_by is null)
);
create index asset_access_reports_project_idx on public.asset_access_reports (project_id, created_at desc);
create index asset_access_reports_asset_idx on public.asset_access_reports (asset_id) where resolved_at is null;
create index asset_access_reports_editor_idx on public.asset_access_reports (editor_id);
create index asset_access_reports_resolved_by_idx on public.asset_access_reports (resolved_by);
comment on table public.asset_access_reports is
  'Append-only editor reports that an asset link cannot be opened. Written only by public.editor_report_asset_inaccessible; resolved only by public.admin_resolve_asset_report.';

-- Append-only: no delete; the only changes are resolving once, and the foreign keys going null
-- when an asset or account is removed.
create function private.guard_asset_access_reports()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'This history cannot be deleted.' using errcode = 'ES409';
  end if;
  if (to_jsonb(new) - array['asset_id', 'resolved_by', 'resolved_at'])
       = (to_jsonb(old) - array['asset_id', 'resolved_by', 'resolved_at'])
     and (new.asset_id is not distinct from old.asset_id or new.asset_id is null)
     and (new.resolved_at is not distinct from old.resolved_at
          or (old.resolved_at is null and new.resolved_at is not null))
     and (new.resolved_by is not distinct from old.resolved_by
          or new.resolved_by is null
          or (old.resolved_at is null and new.resolved_at is not null)) then
    return new;
  end if;
  raise exception 'This history cannot be changed.' using errcode = 'ES409';
end;
$$;
revoke all on function private.guard_asset_access_reports() from public, anon, authenticated;

create trigger asset_access_reports_append_only
  before update or delete on public.asset_access_reports
  for each row execute function private.guard_asset_access_reports();

-- RLS: admin reads all; an active editor reads only their own reports. No write grants.
alter table public.asset_access_reports enable row level security;
revoke all on public.asset_access_reports from anon, authenticated;
grant select on public.asset_access_reports to authenticated;
create policy asset_access_reports_select on public.asset_access_reports
  for select to authenticated
  using ((select private.is_admin())
         or (editor_id = (select auth.uid()) and (select private.is_active_editor())));
