-- Phase 4 (6/6): clients and atomic inquiry conversion. Spec §5, §7, §9, §14. Decision T.
-- Client matching key is lower(btrim(email)) among unmerged clients (archived included).
-- Conversion is one transaction: any error rolls back the client insert, the project and the
-- inquiry status together. Client price is never copied from the inquiry's budget label.

-- ---------------------------------------------------------------------------
-- Client input helper: normalised email, ES422 if missing or malformed.
-- ---------------------------------------------------------------------------
create function private.normalise_client_email(p_email text)
returns text
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v text := lower(btrim(p_email, E' \t\r\n'));
begin
  if v is null or v = '' or char_length(v) > 254 or v !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Please give a valid email address for the client.' using errcode = 'ES422';
  end if;
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_create_client
-- ---------------------------------------------------------------------------
create function public.admin_create_client(p_input jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_name text;
  v_email text;
  v_id uuid;
begin
  if p_input is null or jsonb_typeof(p_input) <> 'object' then
    raise exception 'The client details are not valid.' using errcode = 'ES422';
  end if;
  v_name := private.jsonb_text(p_input, 'name', 'name');
  if v_name is null then
    raise exception 'Please give the client''s name.' using errcode = 'ES422';
  end if;
  v_email := private.normalise_client_email(private.jsonb_text(p_input, 'email', 'email'));

  begin
    insert into public.clients (name, company, email, phone, notes, created_by)
    values (v_name, private.jsonb_text(p_input, 'company', 'company'), v_email,
            private.jsonb_text(p_input, 'phone', 'phone'), private.jsonb_text(p_input, 'notes', 'notes'),
            v_admin)
    on conflict (email) where merged_into_id is null do nothing
    returning id into v_id;
  exception
    when check_violation then
      raise exception 'Please check the client details: fields must not be too long.' using errcode = 'ES422';
  end;

  if v_id is null then
    raise exception 'A client with this email already exists.' using errcode = 'ES409';
  end if;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_update_client: absent keys keep their value; "archived" archives or restores.
-- A merged client is history and cannot be edited.
-- ---------------------------------------------------------------------------
create function public.admin_update_client(p_client_id uuid, p_input jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_client public.clients%rowtype;
  v_name text;
  v_email text;
  v_archived boolean;
begin
  if p_input is null or jsonb_typeof(p_input) <> 'object' then
    raise exception 'The client details are not valid.' using errcode = 'ES422';
  end if;

  select * into v_client from public.clients where id = p_client_id for update;
  if v_client.id is null then
    raise exception 'Client not found.' using errcode = 'ES422';
  end if;
  if v_client.merged_into_id is not null then
    raise exception 'This client was merged into another client and cannot be edited.' using errcode = 'ES409';
  end if;

  v_name := v_client.name;
  if p_input ? 'name' then
    v_name := private.jsonb_text(p_input, 'name', 'name');
    if v_name is null then
      raise exception 'Please give the client''s name.' using errcode = 'ES422';
    end if;
  end if;
  v_email := v_client.email;
  if p_input ? 'email' then
    v_email := private.normalise_client_email(private.jsonb_text(p_input, 'email', 'email'));
  end if;
  v_archived := private.jsonb_bool(p_input, 'archived', 'archived');

  begin
    update public.clients set
      name = v_name,
      email = v_email,
      company = case when p_input ? 'company' then private.jsonb_text(p_input, 'company', 'company') else company end,
      phone = case when p_input ? 'phone' then private.jsonb_text(p_input, 'phone', 'phone') else phone end,
      notes = case when p_input ? 'notes' then private.jsonb_text(p_input, 'notes', 'notes') else notes end,
      archived_at = case
        when v_archived is null then archived_at
        when v_archived then coalesce(archived_at, now())
        else null end
    where id = p_client_id;
  exception
    when unique_violation then
      raise exception 'A client with this email already exists.' using errcode = 'ES409';
    when check_violation then
      raise exception 'Please check the client details: fields must not be too long.' using errcode = 'ES422';
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_merge_clients: repoint projects to the target, mark the source merged, never delete.
-- Target must be unmerged and un-archived; the source may be archived; source <> target. So
-- chains and cycles cannot form.
-- ---------------------------------------------------------------------------
create function public.admin_merge_clients(p_source uuid, p_target uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_source public.clients%rowtype;
  v_target public.clients%rowtype;
  v_moved int;
begin
  if p_source is null or p_target is null or p_source = p_target then
    raise exception 'Choose two different clients to merge.' using errcode = 'ES422';
  end if;

  -- Lock both rows in a fixed order to avoid deadlocks between concurrent merges.
  perform 1 from public.clients where id in (p_source, p_target) order by id for update;
  select * into v_source from public.clients where id = p_source;
  select * into v_target from public.clients where id = p_target;
  if v_source.id is null or v_target.id is null then
    raise exception 'Client not found.' using errcode = 'ES422';
  end if;
  if v_source.merged_into_id is not null then
    raise exception 'This client has already been merged.' using errcode = 'ES409';
  end if;
  if v_target.merged_into_id is not null or v_target.archived_at is not null then
    raise exception 'The client to merge into must be active (not archived or merged).' using errcode = 'ES409';
  end if;

  update public.project_internal set client_id = p_target where client_id = p_source;
  get diagnostics v_moved = row_count;
  update public.clients set merged_into_id = p_target where id = p_source;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'client.merged', 'client', p_source::text,
          jsonb_build_object('source_id', p_source, 'target_id', p_target, 'projects_moved', v_moved));
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_convert_inquiry (§9). Input: the admin_create_project keys, all optional, defaulted
-- from the inquiry (service type, deadline, description -> summary, title), plus an optional
-- client_id to use instead of email matching. brief_type has no default and is required.
-- ---------------------------------------------------------------------------
create function public.admin_convert_inquiry(p_inquiry_id uuid, p_input jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_input jsonb := coalesce(p_input, '{}'::jsonb);
  v_inquiry public.client_inquiries%rowtype;
  v_email text;
  v_client uuid;
  v_client_archived timestamptz;
  v_defaults jsonb;
  v_project uuid;
begin
  if jsonb_typeof(v_input) <> 'object' then
    raise exception 'The project details are not valid.' using errcode = 'ES422';
  end if;

  -- 1. Serialise concurrent conversions of the same inquiry (double clicks, two admins).
  select * into v_inquiry from public.client_inquiries where id = p_inquiry_id for update;

  -- 2. State.
  if v_inquiry.id is null then
    raise exception 'Inquiry not found.' using errcode = 'ES422';
  end if;
  if v_inquiry.status = 'converted' then
    raise exception 'This inquiry has already been converted to a project.' using errcode = 'ES409';
  end if;
  if v_inquiry.status not in ('new', 'reviewing', 'contacted', 'in_discussion') then
    raise exception 'This inquiry is %. Reopen it first.', v_inquiry.status using errcode = 'ES409';
  end if;

  begin
    -- 3. Client: the one given, or the unmerged client with the same normalised email, or a new one.
    v_client := private.jsonb_uuid(v_input, 'client_id', 'client');
    if v_client is not null then
      perform private.check_linkable_client(v_client);
    else
      v_email := lower(btrim(v_inquiry.email));
      select id, archived_at into v_client, v_client_archived
      from public.clients where email = v_email and merged_into_id is null;
      if v_client is null then
        insert into public.clients (name, company, email, phone, created_by)
        values (v_inquiry.contact_name, v_inquiry.company, v_email, v_inquiry.phone, v_admin)
        on conflict (email) where merged_into_id is null do nothing
        returning id into v_client;
        if v_client is null then
          -- Lost a race with a concurrent insert: use the winner's row.
          select id, archived_at into v_client, v_client_archived
          from public.clients where email = v_email and merged_into_id is null;
        end if;
      end if;
      if v_client_archived is not null then
        raise exception 'This client is archived. Restore it first.' using errcode = 'ES409';
      end if;
    end if;

    -- 4. Project, internal record, brief v1, deliverables, references.
    v_defaults := jsonb_strip_nulls(jsonb_build_object(
      -- Service type only: projects.title becomes editor-visible, so no client name/company.
      'title', left(v_inquiry.service_type_label, 200),
      'service_type_code', v_inquiry.service_type_code,
      'deadline', v_inquiry.expected_deadline::text,
      'summary', v_inquiry.description));
    v_project := private.insert_project(
      v_admin,
      v_defaults || (v_input - 'client_id') || jsonb_build_object('client_id', v_client),
      p_inquiry_id);

    -- 5. Inquiry converted and linked (the status trigger writes inquiry.converted).
    update public.client_inquiries
    set status = 'converted', converted_project_id = v_project,
        status_changed_at = now(), status_changed_by = v_admin
    where id = p_inquiry_id;
  exception
    when unique_violation then
      raise exception 'This inquiry has already been converted to a project.' using errcode = 'ES409';
    when check_violation then
      raise exception 'Please check your entries: some values are invalid or too long.'
        using errcode = 'ES422';
  end;

  return v_project;
end;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges
-- ---------------------------------------------------------------------------
revoke all on function private.normalise_client_email(text) from public, anon, authenticated;

revoke all on function
  public.admin_create_client(jsonb),
  public.admin_update_client(uuid, jsonb),
  public.admin_merge_clients(uuid, uuid),
  public.admin_convert_inquiry(uuid, jsonb)
from public, anon, authenticated;
grant execute on function
  public.admin_create_client(jsonb),
  public.admin_update_client(uuid, jsonb),
  public.admin_merge_clients(uuid, uuid),
  public.admin_convert_inquiry(uuid, jsonb)
to anon, authenticated;
