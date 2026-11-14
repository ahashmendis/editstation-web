-- Phase 5 (2/2): asset sync, early-access setters, folder-share log and the revoke checklist.
-- Spec §7 (Phase 5). Plan calls 2, 7, 8, 9 (docs/superpowers/plans/2026-11-14-phase5-6-database.md).
-- Helpers live in `private` (security definer, empty search_path, no API grants). Public
-- functions call private.require_admin() first and raise only ES401/ES403/ES409/ES422.
-- Audit details hold ids and enum/boolean values only: never emails, links, labels or reasons.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Locks a project for a content write; refuses cancelled and archived projects.
create function private.lock_writable_project(p_project_id uuid)
returns public.projects
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.projects;
begin
  select * into v from public.projects where id = p_project_id for update;
  if v.id is null then
    raise exception 'Project not found.' using errcode = 'ES422';
  end if;
  if v.status = 'cancelled' or v.archived_at is not null then
    raise exception 'This project is cancelled or archived and cannot be edited.' using errcode = 'ES409';
  end if;
  return v;
end;
$$;

-- Trims spaces, tabs and line breaks; empty -> null; longer than p_max -> ES422.
create function private.clean_text(p_value text, p_max int, p_label text)
returns text
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v text := nullif(btrim(p_value, E' \t\r\n'), '');
begin
  if v is not null and char_length(v) > p_max then
    raise exception 'The % can be at most % characters.', p_label, p_max using errcode = 'ES422';
  end if;
  return v;
end;
$$;

-- Same rule as clients.email: stored as lower(btrim(email)).
create function private.normalise_email(p_email text)
returns text
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v text := lower(btrim(p_email));
begin
  if v is null or char_length(v) > 254 or v !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Please enter a valid email address.' using errcode = 'ES422';
  end if;
  return v;
end;
$$;

-- Asset list input: up to 100 items; keys id, label, url, provider, kind, notes, sort_order
-- (others ignored). early_access is never read here (plan call 7).
create function private.parse_assets(p_items jsonb)
returns jsonb
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v_item jsonb;
  v_pos bigint;
  v_label text;
  v_url text;
  v_provider text;
  v_kind text;
  v_notes text;
  v_out jsonb := '[]'::jsonb;
begin
  if p_items is null or jsonb_typeof(p_items) = 'null' then
    return v_out;
  end if;
  if jsonb_typeof(p_items) <> 'array' then
    raise exception 'The assets list is not valid.' using errcode = 'ES422';
  end if;
  if jsonb_array_length(p_items) > 100 then
    raise exception 'You can add up to 100 assets.' using errcode = 'ES422';
  end if;

  for v_item, v_pos in select e.value, e.ordinality from jsonb_array_elements(p_items) with ordinality e loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'An asset in the list is not valid.' using errcode = 'ES422';
    end if;
    v_label := private.jsonb_text(v_item, 'label', 'asset label');
    if v_label is null then
      raise exception 'Each asset needs a label.' using errcode = 'ES422';
    end if;
    if char_length(v_label) > 200 then
      raise exception 'Asset labels can be at most 200 characters.' using errcode = 'ES422';
    end if;
    v_url := private.jsonb_text(v_item, 'url', 'asset link');
    if v_url is null then
      raise exception 'Each asset needs a link.' using errcode = 'ES422';
    end if;
    if v_url !~ '^https://[^\s]+$' or char_length(v_url) > 2048 then
      raise exception 'Asset links must start with https:// and be at most 2048 characters.'
        using errcode = 'ES422';
    end if;
    v_provider := coalesce(private.jsonb_text(v_item, 'provider', 'asset provider'), 'other');
    if v_provider not in (select unnest(enum_range(null::public.asset_provider))::text) then
      raise exception 'An asset provider must be Google Drive, Dropbox or other.' using errcode = 'ES422';
    end if;
    v_kind := private.jsonb_text(v_item, 'kind', 'asset kind');
    if char_length(v_kind) > 40 then
      raise exception 'Asset kinds can be at most 40 characters.' using errcode = 'ES422';
    end if;
    v_notes := private.jsonb_text(v_item, 'notes', 'asset notes');
    if char_length(v_notes) > 2000 then
      raise exception 'Asset notes can be at most 2000 characters.' using errcode = 'ES422';
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'id', private.jsonb_uuid(v_item, 'id', 'asset'),
      'label', v_label,
      'url', v_url,
      'provider', v_provider,
      'kind', v_kind,
      'notes', v_notes,
      'sort_order', coalesce(private.jsonb_int(v_item, 'sort_order', 'asset order'), v_pos - 1)));
  end loop;
  return v_out;
end;
$$;

-- Live asset rows <-> parsed input, same id-matching rule as private.sync_brief_rows. Never
-- touches early_access. Returns true if a field other than sort_order changed or a row was
-- added or removed.
create function private.sync_asset_rows(p_project_id uuid, p_items jsonb)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changed boolean := false;
  n int;
begin
  if exists (
    select 1 from jsonb_to_recordset(p_items) as x(id uuid)
    where x.id is not null
      and not exists (select 1 from public.project_assets a
                      where a.id = x.id and a.project_id = p_project_id)) then
    raise exception 'An asset in the list does not belong to this project.' using errcode = 'ES422';
  end if;
  if (select count(x.id) <> count(distinct x.id) from jsonb_to_recordset(p_items) as x(id uuid)) then
    raise exception 'An asset appears twice in the list.' using errcode = 'ES422';
  end if;

  delete from public.project_assets a
  where a.project_id = p_project_id
    and not exists (select 1 from jsonb_to_recordset(p_items) as x(id uuid) where x.id = a.id);
  get diagnostics n = row_count;
  v_changed := v_changed or n > 0;

  if exists (
    select 1
    from jsonb_to_recordset(p_items) as x(id uuid, label text, url text, provider public.asset_provider,
      kind text, notes text)
    join public.project_assets a on a.id = x.id
    where (a.label, a.url, a.provider, a.kind, a.notes)
      is distinct from (x.label, x.url, x.provider, x.kind, x.notes)) then
    v_changed := true;
  end if;

  update public.project_assets a
  set label = x.label, url = x.url, provider = x.provider, kind = x.kind, notes = x.notes,
      sort_order = x.sort_order
  from jsonb_to_recordset(p_items) as x(id uuid, label text, url text, provider public.asset_provider,
    kind text, notes text, sort_order int)
  where a.id = x.id
    and (a.label, a.url, a.provider, a.kind, a.notes, a.sort_order)
      is distinct from (x.label, x.url, x.provider, x.kind, x.notes, x.sort_order);

  insert into public.project_assets (project_id, label, url, provider, kind, notes, sort_order)
  select p_project_id, x.label, x.url, x.provider, x.kind, x.notes, x.sort_order
  from jsonb_to_recordset(p_items) as x(id uuid, label text, url text, provider public.asset_provider,
    kind text, notes text, sort_order int)
  where x.id is null;
  get diagnostics n = row_count;
  v_changed := v_changed or n > 0;

  return v_changed;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_save_assets: never touches brief_versions or current_brief_version (spec §7).
-- ---------------------------------------------------------------------------
create function public.admin_save_assets(p_project_id uuid, p_items jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_items jsonb;
  v_changed boolean;
begin
  perform private.lock_writable_project(p_project_id);
  v_items := private.parse_assets(p_items);
  begin
    v_changed := private.sync_asset_rows(p_project_id, v_items);
  exception
    when check_violation then
      raise exception 'Please check your entries: some values are invalid or too long.' using errcode = 'ES422';
  end;
  if v_changed then
    insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
    values (v_admin, 'project.assets_changed', 'project', p_project_id::text,
            jsonb_build_object('project_id', p_project_id));
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Early-access setters (decision B). No-op without audit when the value is unchanged.
-- ---------------------------------------------------------------------------
create function public.admin_set_reference_early_access(p_reference_id uuid, p_value boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_project uuid;
  v_old boolean;
begin
  if p_value is null then
    raise exception 'Please choose whether editors can see this before confirmation.' using errcode = 'ES422';
  end if;
  select project_id into v_project from public.project_references where id = p_reference_id;
  if v_project is null then
    raise exception 'Reference not found.' using errcode = 'ES422';
  end if;
  perform private.lock_writable_project(v_project);
  select early_access into v_old from public.project_references where id = p_reference_id for update;
  if v_old is null then
    raise exception 'Reference not found.' using errcode = 'ES422';
  end if;
  if v_old = p_value then
    return;
  end if;
  update public.project_references set early_access = p_value where id = p_reference_id;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'project.early_access_changed', 'project', v_project::text,
          jsonb_build_object('project_id', v_project, 'reference_id', p_reference_id, 'early_access', p_value));
end;
$$;

create function public.admin_set_asset_early_access(p_asset_id uuid, p_value boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_project uuid;
  v_old boolean;
begin
  if p_value is null then
    raise exception 'Please choose whether editors can see this before confirmation.' using errcode = 'ES422';
  end if;
  select project_id into v_project from public.project_assets where id = p_asset_id;
  if v_project is null then
    raise exception 'Asset not found.' using errcode = 'ES422';
  end if;
  perform private.lock_writable_project(v_project);
  select early_access into v_old from public.project_assets where id = p_asset_id for update;
  if v_old is null then
    raise exception 'Asset not found.' using errcode = 'ES422';
  end if;
  if v_old = p_value then
    return;
  end if;
  update public.project_assets set early_access = p_value where id = p_asset_id;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'project.early_access_changed', 'project', v_project::text,
          jsonb_build_object('project_id', v_project, 'asset_id', p_asset_id, 'early_access', p_value));
end;
$$;

-- ---------------------------------------------------------------------------
-- Folder shares (decision K): recorded after the admin shares the folder by hand.
-- ---------------------------------------------------------------------------
create function public.admin_record_asset_grant(
  p_project_id uuid, p_editor_id uuid, p_email text, p_provider public.asset_provider,
  p_folder_url text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_email text;
  v_url text;
  v_id uuid;
begin
  perform private.lock_writable_project(p_project_id);
  if not exists (select 1 from public.editor_profiles
                 where user_id = p_editor_id and access_status = 'active') then
    raise exception 'Choose an active editor.' using errcode = 'ES422';
  end if;
  if p_provider is null then
    raise exception 'Please choose where the folder is shared from.' using errcode = 'ES422';
  end if;
  v_email := private.normalise_email(p_email);
  v_url := private.clean_text(p_folder_url, 2048, 'folder link');
  if v_url is not null and v_url !~ '^https://[^\s]+$' then
    raise exception 'Folder links must start with https://.' using errcode = 'ES422';
  end if;
  if exists (select 1 from public.asset_access_grants
             where project_id = p_project_id and editor_id = p_editor_id
               and shared_with_email = v_email and revoked_at is null) then
    raise exception 'This share is already recorded.' using errcode = 'ES409';
  end if;

  begin
    insert into public.asset_access_grants (project_id, editor_id, shared_with_email, provider, folder_url,
      shared_by)
    values (p_project_id, p_editor_id, v_email, p_provider, v_url, v_admin)
    returning id into v_id;
  exception
    when unique_violation then
      raise exception 'This share is already recorded.' using errcode = 'ES409';
  end;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'asset_grant.recorded', 'asset_grant', v_id::text,
          jsonb_build_object('grant_id', v_id, 'project_id', p_project_id, 'editor_id', p_editor_id));
  return v_id;
end;
$$;

-- Allowed on cancelled and archived projects (plan call 9): revoking must always be possible.
create function public.admin_revoke_asset_grant(p_grant_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_grant public.asset_access_grants;
  v_reason text;
begin
  select * into v_grant from public.asset_access_grants where id = p_grant_id for update;
  if v_grant.id is null then
    raise exception 'Share not found.' using errcode = 'ES422';
  end if;
  if v_grant.revoked_at is not null then
    raise exception 'This share is already revoked.' using errcode = 'ES409';
  end if;
  v_reason := private.clean_text(p_reason, 500, 'reason');

  update public.asset_access_grants
  set revoked_at = now(), revoked_by = v_admin, revoke_reason = v_reason
  where id = p_grant_id;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'asset_grant.revoked', 'asset_grant', p_grant_id::text,
          jsonb_build_object('grant_id', p_grant_id, 'project_id', v_grant.project_id,
                             'editor_id', v_grant.editor_id));
end;
$$;

-- Revoke checklist (v1). Phase 6 replaces it to add no_active_assignment (plan call 2).
create function public.admin_pending_revocations()
returns table (grant_id uuid, project_id uuid, editor_id uuid, shared_with_email text,
  provider public.asset_provider, folder_url text, shared_at timestamptz, reason text)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_admin uuid := private.require_admin();
begin
  return query
  select x.id, x.project_id, x.editor_id, x.shared_with_email, x.provider, x.folder_url, x.shared_at, x.reason
  from (
    select g.id, g.project_id, g.editor_id, g.shared_with_email, g.provider, g.folder_url, g.shared_at,
      case
        when ep.access_status is distinct from 'active' then 'editor_not_active'
        when p.status in ('cancelled', 'completed') or p.archived_at is not null then 'project_closed'
      end as reason
    from public.asset_access_grants g
    join public.projects p on p.id = g.project_id
    left join public.editor_profiles ep on ep.user_id = g.editor_id
    where g.revoked_at is null
  ) x
  where x.reason is not null
  order by x.shared_at, x.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges
-- ---------------------------------------------------------------------------
revoke all on function
  private.lock_writable_project(uuid), private.clean_text(text, int, text), private.normalise_email(text),
  private.parse_assets(jsonb), private.sync_asset_rows(uuid, jsonb)
from public, anon, authenticated;

revoke all on function
  public.admin_save_assets(uuid, jsonb),
  public.admin_set_reference_early_access(uuid, boolean),
  public.admin_set_asset_early_access(uuid, boolean),
  public.admin_record_asset_grant(uuid, uuid, text, public.asset_provider, text),
  public.admin_revoke_asset_grant(uuid, text),
  public.admin_pending_revocations()
from public, anon, authenticated;
grant execute on function
  public.admin_save_assets(uuid, jsonb),
  public.admin_set_reference_early_access(uuid, boolean),
  public.admin_set_asset_early_access(uuid, boolean),
  public.admin_record_asset_grant(uuid, uuid, text, public.asset_provider, text),
  public.admin_revoke_asset_grant(uuid, text),
  public.admin_pending_revocations()
to anon, authenticated;
