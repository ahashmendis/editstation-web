-- Phase 12B (3/3): asset access functions (KB7, KB7a). Spec §4.7 and §6.
-- Public functions authorise in their body, raise only ES401/ES403/ES409/ES422 and are executable
-- by anon and authenticated. Audit details hold ids and enum values only (never notes, links,
-- labels or emails). Notifications go through private.notify (Phase 10).

-- ---------------------------------------------------------------------------
-- Asset list input: adds description and access_instructions (replaces the Phase 5 parser).
-- access_status, verification and early_access are never read from the list.
-- ---------------------------------------------------------------------------
create or replace function private.parse_assets(p_items jsonb)
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
  v_description text;
  v_instructions text;
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
    v_description := private.jsonb_text(v_item, 'description', 'asset description');
    if char_length(v_description) > 2000 then
      raise exception 'Asset descriptions can be at most 2000 characters.' using errcode = 'ES422';
    end if;
    v_instructions := private.jsonb_text(v_item, 'access_instructions', 'access instructions');
    if char_length(v_instructions) > 2000 then
      raise exception 'Access instructions can be at most 2000 characters.' using errcode = 'ES422';
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'id', private.jsonb_uuid(v_item, 'id', 'asset'),
      'label', v_label,
      'url', v_url,
      'provider', v_provider,
      'kind', v_kind,
      'notes', v_notes,
      'description', v_description,
      'access_instructions', v_instructions,
      'sort_order', coalesce(private.jsonb_int(v_item, 'sort_order', 'asset order'), v_pos - 1)));
  end loop;
  return v_out;
end;
$$;

-- Same id-matching rule as Phase 5. A changed link or provider resets verification: the new link
-- has not been checked (a working URL is never proof of access). An asset with an unresolved
-- report stays `inaccessible` so the report is not hidden.
create or replace function private.sync_asset_rows(p_project_id uuid, p_items jsonb)
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
      kind text, notes text, description text, access_instructions text)
    join public.project_assets a on a.id = x.id
    where (a.label, a.url, a.provider, a.kind, a.notes, a.description, a.access_instructions)
      is distinct from (x.label, x.url, x.provider, x.kind, x.notes, x.description, x.access_instructions)) then
    v_changed := true;
  end if;

  update public.project_assets a
  set label = x.label, url = x.url, provider = x.provider, kind = x.kind, notes = x.notes,
      description = x.description, access_instructions = x.access_instructions,
      sort_order = x.sort_order,
      access_status = case
        when (a.url, a.provider) is not distinct from (x.url, x.provider) then a.access_status
        when exists (select 1 from public.asset_access_reports r where r.asset_id = a.id and r.resolved_at is null)
          then 'inaccessible'::public.asset_access_status
        else 'awaiting_access'::public.asset_access_status end,
      verified_by = case when (a.url, a.provider) is distinct from (x.url, x.provider) then null else a.verified_by end,
      verified_at = case when (a.url, a.provider) is distinct from (x.url, x.provider) then null else a.verified_at end,
      editor_confirmed_at = case when (a.url, a.provider) is distinct from (x.url, x.provider)
                                 then null else a.editor_confirmed_at end
  from jsonb_to_recordset(p_items) as x(id uuid, label text, url text, provider public.asset_provider,
    kind text, notes text, description text, access_instructions text, sort_order int)
  where a.id = x.id
    and (a.label, a.url, a.provider, a.kind, a.notes, a.description, a.access_instructions, a.sort_order)
      is distinct from (x.label, x.url, x.provider, x.kind, x.notes, x.description, x.access_instructions,
                        x.sort_order);

  insert into public.project_assets (project_id, label, url, provider, kind, notes, description,
    access_instructions, sort_order)
  select p_project_id, x.label, x.url, x.provider, x.kind, x.notes, x.description, x.access_instructions,
    x.sort_order
  from jsonb_to_recordset(p_items) as x(id uuid, label text, url text, provider public.asset_provider,
    kind text, notes text, description text, access_instructions text, sort_order int)
  where x.id is null;
  get diagnostics n = row_count;
  v_changed := v_changed or n > 0;

  return v_changed;
end;
$$;

-- ---------------------------------------------------------------------------
-- Helper: the asset row for an editor action. The caller must be the confirmed (or working)
-- editor of the asset's project; anything else, an unknown asset included, is ES403.
-- ---------------------------------------------------------------------------
create function private.lock_asset_for_editor(p_asset_id uuid)
returns public.project_assets
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.project_assets;
begin
  select * into v from public.project_assets where id = p_asset_id;
  if v.id is null or private.editor_project_stage(v.project_id) <> 'assigned' then
    raise exception 'You can only do this for assets on a project you are assigned to.' using errcode = 'ES403';
  end if;
  -- Lock order: the project first (as everywhere), then the asset. Re-check after the lock: a
  -- concurrent reassignment or cancellation may have ended the stage while we waited.
  perform 1 from public.projects where id = v.project_id for update;
  if private.editor_project_stage(v.project_id) <> 'assigned' then
    raise exception 'You can only do this for assets on a project you are assigned to.' using errcode = 'ES403';
  end if;
  select * into v from public.project_assets where id = p_asset_id for update;
  if v.id is null then
    raise exception 'Asset not found.' using errcode = 'ES422';
  end if;
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- Editor: "I cannot open this". Marks the asset inaccessible and notifies every active admin.
-- ---------------------------------------------------------------------------
create function public.editor_report_asset_inaccessible(p_asset_id uuid, p_note text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_editor();
  v_asset public.project_assets;
  v_note text;
  v_id uuid;
begin
  v_asset := private.lock_asset_for_editor(p_asset_id);
  v_note := private.clean_text(p_note, 1000, 'note');
  if v_note is null then
    raise exception 'Please say what happens when you try to open it.' using errcode = 'ES422';
  end if;
  if exists (select 1 from public.asset_access_reports
             where asset_id = p_asset_id and editor_id = v_uid and resolved_at is null) then
    raise exception 'You already reported this asset. The studio is looking into it.' using errcode = 'ES409';
  end if;

  insert into public.asset_access_reports (project_id, asset_id, editor_id, note)
  values (v_asset.project_id, p_asset_id, v_uid, v_note)
  returning id into v_id;

  update public.project_assets
  set access_status = 'inaccessible', verified_by = null, verified_at = null, editor_confirmed_at = null
  where id = p_asset_id;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_uid, 'asset.reported_inaccessible', 'project', v_asset.project_id::text,
          jsonb_build_object('project_id', v_asset.project_id, 'asset_id', p_asset_id, 'report_id', v_id));

  perform private.notify(private.active_admin_ids(), 'asset_inaccessible', 'project', v_asset.project_id,
    'Asset reported inaccessible',
    format('An editor cannot open an asset on "%s".', private.project_title(v_asset.project_id)));
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Editor: "I can open this". Recorded for the admin; never verifies the asset.
-- ---------------------------------------------------------------------------
create function public.editor_confirm_asset_access(p_asset_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_editor();
  v_asset public.project_assets;
  v_since timestamptz;
begin
  v_asset := private.lock_asset_for_editor(p_asset_id);
  if exists (select 1 from public.asset_access_reports
             where asset_id = p_asset_id and editor_id = v_uid and resolved_at is null) then
    raise exception 'You reported this asset as inaccessible. The studio will close your report first.'
      using errcode = 'ES409';
  end if;
  -- Already confirmed during this editor's current assignment: nothing to do. An older timestamp
  -- belongs to an earlier assignment and is stale.
  select max(a.confirmed_at) into v_since from public.assignments a
  where a.project_id = v_asset.project_id and a.editor_id = v_uid and a.status in ('confirmed', 'in_progress');
  if v_asset.editor_confirmed_at is not null and v_asset.editor_confirmed_at >= coalesce(v_since, '-infinity') then
    return;
  end if;
  update public.project_assets set editor_confirmed_at = now()
  where id = p_asset_id;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_uid, 'asset.editor_can_open', 'project', v_asset.project_id::text,
          jsonb_build_object('project_id', v_asset.project_id, 'asset_id', p_asset_id));
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin: verify an asset (the only way to reach `verified`).
-- ---------------------------------------------------------------------------
create function public.admin_verify_asset(p_asset_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_project uuid;
  v_status public.asset_access_status;
begin
  select project_id into v_project from public.project_assets where id = p_asset_id;
  if v_project is null then
    raise exception 'Asset not found.' using errcode = 'ES422';
  end if;
  perform private.lock_writable_project(v_project);
  select access_status into v_status from public.project_assets where id = p_asset_id for update;
  if v_status is null then
    raise exception 'Asset not found.' using errcode = 'ES422';
  end if;
  if v_status = 'verified' then
    raise exception 'This asset is already verified.' using errcode = 'ES409';
  end if;
  if exists (select 1 from public.asset_access_reports where asset_id = p_asset_id and resolved_at is null) then
    raise exception 'Resolve the open inaccessible reports for this asset first.' using errcode = 'ES409';
  end if;
  update public.project_assets set access_status = 'verified', verified_by = v_admin, verified_at = now()
  where id = p_asset_id;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'asset.verified', 'project', v_project::text,
          jsonb_build_object('project_id', v_project, 'asset_id', p_asset_id));
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin: resolve a report. When no report stays open on an inaccessible asset, it goes back to
-- awaiting_access (the admin still verifies it). Allowed on closed projects.
-- ---------------------------------------------------------------------------
create function public.admin_resolve_asset_report(p_report_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_report public.asset_access_reports;
begin
  select * into v_report from public.asset_access_reports where id = p_report_id;
  if v_report.id is null then
    raise exception 'Report not found.' using errcode = 'ES422';
  end if;
  perform 1 from public.projects where id = v_report.project_id for update;
  select * into v_report from public.asset_access_reports where id = p_report_id for update;
  if v_report.resolved_at is not null then
    raise exception 'This report is already resolved.' using errcode = 'ES409';
  end if;
  update public.asset_access_reports set resolved_by = v_admin, resolved_at = now() where id = p_report_id;

  if v_report.asset_id is not null
     and not exists (select 1 from public.asset_access_reports
                     where asset_id = v_report.asset_id and resolved_at is null) then
    update public.project_assets set access_status = 'awaiting_access'
    where id = v_report.asset_id and access_status = 'inaccessible';
  end if;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'asset_report.resolved', 'project', v_report.project_id::text,
          jsonb_build_object('project_id', v_report.project_id, 'asset_id', v_report.asset_id,
                             'report_id', p_report_id));
end;
$$;

-- ---------------------------------------------------------------------------
-- Folder shares: access type on record; removal requested, then confirmed (KB7a-2).
-- ---------------------------------------------------------------------------
drop function public.admin_record_asset_grant(uuid, uuid, text, public.asset_provider, text);

create function public.admin_record_asset_grant(
  p_project_id uuid, p_editor_id uuid, p_email text, p_provider public.asset_provider,
  p_folder_url text default null, p_access_type public.asset_access_type default 'editor_account')
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
  if p_access_type is null then
    raise exception 'Please choose how the folder is shared.' using errcode = 'ES422';
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
      shared_by, access_type)
    values (p_project_id, p_editor_id, v_email, p_provider, v_url, v_admin, p_access_type)
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

-- Allowed on cancelled and archived projects: clean-up must always be possible.
create function public.admin_request_access_removal(p_grant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_grant public.asset_access_grants;
begin
  select * into v_grant from public.asset_access_grants where id = p_grant_id for update;
  if v_grant.id is null then
    raise exception 'Share not found.' using errcode = 'ES422';
  end if;
  if v_grant.revoked_at is not null then
    raise exception 'This share is already closed.' using errcode = 'ES409';
  end if;
  if v_grant.removal_requested_at is not null then
    raise exception 'Removal was already requested from the client.' using errcode = 'ES409';
  end if;
  update public.asset_access_grants set removal_requested_at = now(), removal_requested_by = v_admin
  where id = p_grant_id;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'asset_grant.removal_requested', 'asset_grant', p_grant_id::text,
          jsonb_build_object('grant_id', p_grant_id, 'project_id', v_grant.project_id,
                             'editor_id', v_grant.editor_id));
end;
$$;

-- The client confirmed the editor's access is removed: the share is closed.
create function public.admin_confirm_access_removal(p_grant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_grant public.asset_access_grants;
begin
  select * into v_grant from public.asset_access_grants where id = p_grant_id for update;
  if v_grant.id is null then
    raise exception 'Share not found.' using errcode = 'ES422';
  end if;
  if v_grant.removal_confirmed_at is not null or v_grant.revoked_at is not null then
    raise exception 'This share is already closed.' using errcode = 'ES409';
  end if;
  if v_grant.removal_requested_at is null then
    raise exception 'Ask the client to remove the access first.' using errcode = 'ES409';
  end if;
  update public.asset_access_grants
  set removal_confirmed_at = now(), removal_confirmed_by = v_admin, revoked_at = now(), revoked_by = v_admin
  where id = p_grant_id;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'asset_grant.removal_confirmed', 'asset_grant', p_grant_id::text,
          jsonb_build_object('grant_id', p_grant_id, 'project_id', v_grant.project_id,
                             'editor_id', v_grant.editor_id));
end;
$$;

-- Revoke checklist v3: adds the access type and the removal request state (rules unchanged).
drop function public.admin_pending_revocations();

create function public.admin_pending_revocations()
returns table (grant_id uuid, project_id uuid, editor_id uuid, shared_with_email text,
  provider public.asset_provider, folder_url text, shared_at timestamptz, reason text,
  access_type public.asset_access_type, removal_requested_at timestamptz)
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
  select x.id, x.project_id, x.editor_id, x.shared_with_email, x.provider, x.folder_url, x.shared_at, x.reason,
    x.access_type, x.removal_requested_at
  from (
    select g.id, g.project_id, g.editor_id, g.shared_with_email, g.provider, g.folder_url, g.shared_at,
      g.access_type, g.removal_requested_at,
      case
        when ep.access_status is distinct from 'active' then 'editor_not_active'
        when p.status in ('cancelled', 'completed') or p.archived_at is not null then 'project_closed'
        when not exists (
          select 1 from public.assignments a
          where a.project_id = g.project_id and a.editor_id = g.editor_id
            and a.status in ('offered', 'counteroffer_pending', 'accepted', 'confirmed', 'in_progress'))
          then 'no_active_assignment'
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
  private.parse_assets(jsonb), private.sync_asset_rows(uuid, jsonb), private.lock_asset_for_editor(uuid)
from public, anon, authenticated;

revoke all on function
  public.editor_report_asset_inaccessible(uuid, text),
  public.editor_confirm_asset_access(uuid),
  public.admin_verify_asset(uuid),
  public.admin_resolve_asset_report(uuid),
  public.admin_record_asset_grant(uuid, uuid, text, public.asset_provider, text, public.asset_access_type),
  public.admin_request_access_removal(uuid),
  public.admin_confirm_access_removal(uuid),
  public.admin_pending_revocations()
from public, anon, authenticated;
grant execute on function
  public.editor_report_asset_inaccessible(uuid, text),
  public.editor_confirm_asset_access(uuid),
  public.admin_verify_asset(uuid),
  public.admin_resolve_asset_report(uuid),
  public.admin_record_asset_grant(uuid, uuid, text, public.asset_provider, text, public.asset_access_type),
  public.admin_request_access_removal(uuid),
  public.admin_confirm_access_removal(uuid),
  public.admin_pending_revocations()
to anon, authenticated;
