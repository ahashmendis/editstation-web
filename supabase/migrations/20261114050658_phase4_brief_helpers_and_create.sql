-- Phase 4 (3/6): input helpers, brief helpers and admin_create_project.
-- Spec §7, §8, §10, §14. All helpers live in `private`, are security definer with an empty
-- search_path, and are executable by no API role; they run only inside the public.admin_*
-- functions (as their owner). Errors are ES422 with plain, user-safe messages.
-- Plan calls: at most 50 deliverables and 100 references per call.

-- ---------------------------------------------------------------------------
-- Typed readers for jsonb input. Missing key or JSON null -> SQL null. A value of the wrong
-- JSON type -> ES422. Text is trimmed (spaces, tabs, line breaks); empty text -> null.
-- ---------------------------------------------------------------------------
create function private.jsonb_text(p_obj jsonb, p_key text, p_label text)
returns text
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v jsonb := p_obj -> p_key;
begin
  if v is null or jsonb_typeof(v) = 'null' then
    return null;
  end if;
  if jsonb_typeof(v) <> 'string' then
    raise exception 'Please check the % value.', p_label using errcode = 'ES422';
  end if;
  return nullif(btrim(v #>> '{}', E' \t\r\n'), '');
end;
$$;

-- Whole number >= 0.
create function private.jsonb_int(p_obj jsonb, p_key text, p_label text)
returns int
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v jsonb := p_obj -> p_key;
  n numeric;
begin
  if v is null or jsonb_typeof(v) = 'null' then
    return null;
  end if;
  if jsonb_typeof(v) <> 'number' then
    raise exception 'Please check the % value: it must be a whole number.', p_label using errcode = 'ES422';
  end if;
  n := (v #>> '{}')::numeric;
  if n <> trunc(n) or n < 0 or n > 2147483647 then
    raise exception 'Please check the % value: it must be a whole number of zero or more.', p_label
      using errcode = 'ES422';
  end if;
  return n::int;
end;
$$;

-- Money amount >= 0 that fits numeric(12,2).
create function private.jsonb_amount(p_obj jsonb, p_key text, p_label text)
returns numeric
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v jsonb := p_obj -> p_key;
  n numeric;
begin
  if v is null or jsonb_typeof(v) = 'null' then
    return null;
  end if;
  if jsonb_typeof(v) <> 'number' then
    raise exception 'Please check the % amount.', p_label using errcode = 'ES422';
  end if;
  -- Check after rounding: 9999999999.995 rounds to 10000000000.00, which overflows numeric(12,2).
  n := round((v #>> '{}')::numeric, 2);
  if n < 0 or n > 9999999999.99 then
    raise exception 'Please check the % amount: it must be zero or more and below 10,000,000,000.', p_label
      using errcode = 'ES422';
  end if;
  return n;
end;
$$;

create function private.jsonb_bool(p_obj jsonb, p_key text, p_label text)
returns boolean
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v jsonb := p_obj -> p_key;
begin
  if v is null or jsonb_typeof(v) = 'null' then
    return null;
  end if;
  if jsonb_typeof(v) <> 'boolean' then
    raise exception 'Please check the % value.', p_label using errcode = 'ES422';
  end if;
  return (v #>> '{}')::boolean;
end;
$$;

-- Date as YYYY-MM-DD. Past dates are accepted.
create function private.jsonb_date(p_obj jsonb, p_key text, p_label text)
returns date
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v text := private.jsonb_text(p_obj, p_key, p_label);
begin
  if v is null then
    return null;
  end if;
  if v !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception 'Please give the % as a date (YYYY-MM-DD).', p_label using errcode = 'ES422';
  end if;
  begin
    return v::date;
  exception
    when others then
      raise exception 'Please give the % as a valid date.', p_label using errcode = 'ES422';
  end;
end;
$$;

create function private.jsonb_uuid(p_obj jsonb, p_key text, p_label text)
returns uuid
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v text := private.jsonb_text(p_obj, p_key, p_label);
begin
  if v is null then
    return null;
  end if;
  if v !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'Please check the % reference.', p_label using errcode = 'ES422';
  end if;
  return v::uuid;
end;
$$;

-- Three-letter currency code; missing -> LKR (the stored default, decision H stays open).
create function private.jsonb_currency(p_obj jsonb, p_key text, p_label text)
returns char(3)
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v text := upper(private.jsonb_text(p_obj, p_key, p_label));
begin
  if v is null then
    return 'LKR';
  end if;
  if v !~ '^[A-Z]{3}$' then
    raise exception 'Please give the % as a three-letter code such as LKR.', p_label using errcode = 'ES422';
  end if;
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- Brief input parsers: validate and normalise, return clean jsonb.
-- ---------------------------------------------------------------------------
create function private.parse_brief(p_brief jsonb)
returns jsonb
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v jsonb := coalesce(p_brief, 'null'::jsonb);
begin
  if jsonb_typeof(v) = 'null' then
    v := '{}'::jsonb;
  elsif jsonb_typeof(v) <> 'object' then
    raise exception 'The brief details are not valid.' using errcode = 'ES422';
  end if;
  return jsonb_build_object(
    'instructions', private.jsonb_text(v, 'instructions', 'instructions'),
    'desired_outcome', private.jsonb_text(v, 'desired_outcome', 'desired outcome'),
    'audience', private.jsonb_text(v, 'audience', 'audience'),
    'core_message', private.jsonb_text(v, 'core_message', 'core message'),
    'brand_constraints', private.jsonb_text(v, 'brand_constraints', 'brand constraints'),
    'mandatory_content', private.jsonb_text(v, 'mandatory_content', 'mandatory content'),
    'prohibited_content', private.jsonb_text(v, 'prohibited_content', 'prohibited content'));
end;
$$;

-- Deliverables: up to 50. Items keep an optional id; sort_order defaults to list position.
create function private.parse_deliverables(p_items jsonb)
returns jsonb
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v_item jsonb;
  v_pos bigint;
  v_name text;
  v_out jsonb := '[]'::jsonb;
begin
  if p_items is null or jsonb_typeof(p_items) = 'null' then
    return v_out;
  end if;
  if jsonb_typeof(p_items) <> 'array' then
    raise exception 'The deliverables list is not valid.' using errcode = 'ES422';
  end if;
  if jsonb_array_length(p_items) > 50 then
    raise exception 'You can add up to 50 deliverables.' using errcode = 'ES422';
  end if;

  for v_item, v_pos in select e.value, e.ordinality from jsonb_array_elements(p_items) with ordinality e loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'A deliverable in the list is not valid.' using errcode = 'ES422';
    end if;
    v_name := private.jsonb_text(v_item, 'name', 'deliverable name');
    if v_name is null then
      raise exception 'Each deliverable needs a name.' using errcode = 'ES422';
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'id', private.jsonb_uuid(v_item, 'id', 'deliverable'),
      'name', v_name,
      'format', private.jsonb_text(v_item, 'format', 'deliverable format'),
      'resolution', private.jsonb_text(v_item, 'resolution', 'deliverable resolution'),
      'aspect_ratio', private.jsonb_text(v_item, 'aspect_ratio', 'deliverable aspect ratio'),
      'duration_seconds', private.jsonb_int(v_item, 'duration_seconds', 'deliverable duration'),
      'notes', private.jsonb_text(v_item, 'notes', 'deliverable notes'),
      'sort_order', coalesce(private.jsonb_int(v_item, 'sort_order', 'deliverable order'), v_pos - 1)));
  end loop;
  return v_out;
end;
$$;

-- References (KB §4.2): up to 100, https links only, timecodes in whole seconds, end >= start.
create function private.parse_references(p_items jsonb)
returns jsonb
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v_item jsonb;
  v_pos bigint;
  v_url text;
  v_priority text;
  v_start int;
  v_end int;
  v_out jsonb := '[]'::jsonb;
begin
  if p_items is null or jsonb_typeof(p_items) = 'null' then
    return v_out;
  end if;
  if jsonb_typeof(p_items) <> 'array' then
    raise exception 'The references list is not valid.' using errcode = 'ES422';
  end if;
  if jsonb_array_length(p_items) > 100 then
    raise exception 'You can add up to 100 references.' using errcode = 'ES422';
  end if;

  for v_item, v_pos in select e.value, e.ordinality from jsonb_array_elements(p_items) with ordinality e loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'A reference in the list is not valid.' using errcode = 'ES422';
    end if;
    v_url := private.jsonb_text(v_item, 'url', 'reference link');
    if v_url is null then
      raise exception 'Each reference needs a link.' using errcode = 'ES422';
    end if;
    if v_url !~ '^https://[^\s]+$' or char_length(v_url) > 2048 then
      raise exception 'Reference links must start with https:// and be at most 2048 characters.'
        using errcode = 'ES422';
    end if;
    v_priority := coalesce(private.jsonb_text(v_item, 'priority', 'reference priority'), 'optional');
    if v_priority not in ('essential', 'optional') then
      raise exception 'A reference priority must be essential or optional.' using errcode = 'ES422';
    end if;
    v_start := private.jsonb_int(v_item, 'start_seconds', 'reference start time');
    v_end := private.jsonb_int(v_item, 'end_seconds', 'reference end time');
    if v_start is not null and v_end is not null and v_end < v_start then
      raise exception 'A reference cannot end before it starts.' using errcode = 'ES422';
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'id', private.jsonb_uuid(v_item, 'id', 'reference'),
      'title', private.jsonb_text(v_item, 'title', 'reference title'),
      'url', v_url,
      'start_seconds', v_start,
      'end_seconds', v_end,
      'observation_notes', private.jsonb_text(v_item, 'observation_notes', 'reference notes'),
      'priority', v_priority,
      'category', private.jsonb_text(v_item, 'category', 'reference category'),
      'access_notes', private.jsonb_text(v_item, 'access_notes', 'reference access notes'),
      'sort_order', coalesce(private.jsonb_int(v_item, 'sort_order', 'reference order'), v_pos - 1)));
  end loop;
  return v_out;
end;
$$;

-- ---------------------------------------------------------------------------
-- Live rows <-> parsed input (§14): items with an id are updated in place, items without one
-- are inserted, existing items missing from the input are deleted. Returns true if any field
-- value changed or an item was added or removed. sort_order alone is not a change; inputs are
-- already trimmed by the parsers, so whitespace-only edits are not changes either.
-- ---------------------------------------------------------------------------
create function private.sync_brief_rows(p_project_id uuid, p_deliverables jsonb, p_references jsonb)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changed boolean := false;
  n int;
begin
  -- Deliverables -------------------------------------------------------------
  if exists (
    select 1 from jsonb_to_recordset(p_deliverables) as x(id uuid)
    where x.id is not null
      and not exists (select 1 from public.project_deliverables d
                      where d.id = x.id and d.project_id = p_project_id)) then
    raise exception 'A deliverable in the list does not belong to this project.' using errcode = 'ES422';
  end if;
  if (select count(x.id) <> count(distinct x.id) from jsonb_to_recordset(p_deliverables) as x(id uuid)) then
    raise exception 'A deliverable appears twice in the list.' using errcode = 'ES422';
  end if;

  delete from public.project_deliverables d
  where d.project_id = p_project_id
    and not exists (select 1 from jsonb_to_recordset(p_deliverables) as x(id uuid) where x.id = d.id);
  get diagnostics n = row_count;
  v_changed := v_changed or n > 0;

  if exists (
    select 1
    from jsonb_to_recordset(p_deliverables) as x(id uuid, name text, format text, resolution text,
      aspect_ratio text, duration_seconds int, notes text)
    join public.project_deliverables d on d.id = x.id
    where (d.name, d.format, d.resolution, d.aspect_ratio, d.duration_seconds, d.notes)
      is distinct from (x.name, x.format, x.resolution, x.aspect_ratio, x.duration_seconds, x.notes)) then
    v_changed := true;
  end if;

  update public.project_deliverables d
  set name = x.name, format = x.format, resolution = x.resolution, aspect_ratio = x.aspect_ratio,
      duration_seconds = x.duration_seconds, notes = x.notes, sort_order = x.sort_order
  from jsonb_to_recordset(p_deliverables) as x(id uuid, name text, format text, resolution text,
    aspect_ratio text, duration_seconds int, notes text, sort_order int)
  where d.id = x.id
    and (d.name, d.format, d.resolution, d.aspect_ratio, d.duration_seconds, d.notes, d.sort_order)
      is distinct from (x.name, x.format, x.resolution, x.aspect_ratio, x.duration_seconds, x.notes, x.sort_order);

  insert into public.project_deliverables (project_id, name, format, resolution, aspect_ratio,
    duration_seconds, notes, sort_order)
  select p_project_id, x.name, x.format, x.resolution, x.aspect_ratio, x.duration_seconds, x.notes, x.sort_order
  from jsonb_to_recordset(p_deliverables) as x(id uuid, name text, format text, resolution text,
    aspect_ratio text, duration_seconds int, notes text, sort_order int)
  where x.id is null;
  get diagnostics n = row_count;
  v_changed := v_changed or n > 0;

  -- References ---------------------------------------------------------------
  if exists (
    select 1 from jsonb_to_recordset(p_references) as x(id uuid)
    where x.id is not null
      and not exists (select 1 from public.project_references r
                      where r.id = x.id and r.project_id = p_project_id)) then
    raise exception 'A reference in the list does not belong to this project.' using errcode = 'ES422';
  end if;
  if (select count(x.id) <> count(distinct x.id) from jsonb_to_recordset(p_references) as x(id uuid)) then
    raise exception 'A reference appears twice in the list.' using errcode = 'ES422';
  end if;

  delete from public.project_references r
  where r.project_id = p_project_id
    and not exists (select 1 from jsonb_to_recordset(p_references) as x(id uuid) where x.id = r.id);
  get diagnostics n = row_count;
  v_changed := v_changed or n > 0;

  if exists (
    select 1
    from jsonb_to_recordset(p_references) as x(id uuid, title text, url text, start_seconds int,
      end_seconds int, observation_notes text, priority public.reference_priority, category text,
      access_notes text)
    join public.project_references r on r.id = x.id
    where (r.title, r.url, r.start_seconds, r.end_seconds, r.observation_notes, r.priority, r.category,
           r.access_notes)
      is distinct from (x.title, x.url, x.start_seconds, x.end_seconds, x.observation_notes, x.priority,
           x.category, x.access_notes)) then
    v_changed := true;
  end if;

  update public.project_references r
  set title = x.title, url = x.url, start_seconds = x.start_seconds, end_seconds = x.end_seconds,
      observation_notes = x.observation_notes, priority = x.priority, category = x.category,
      access_notes = x.access_notes, sort_order = x.sort_order
  from jsonb_to_recordset(p_references) as x(id uuid, title text, url text, start_seconds int,
    end_seconds int, observation_notes text, priority public.reference_priority, category text,
    access_notes text, sort_order int)
  where r.id = x.id
    and (r.title, r.url, r.start_seconds, r.end_seconds, r.observation_notes, r.priority, r.category,
         r.access_notes, r.sort_order)
      is distinct from (x.title, x.url, x.start_seconds, x.end_seconds, x.observation_notes, x.priority,
         x.category, x.access_notes, x.sort_order);

  insert into public.project_references (project_id, title, url, start_seconds, end_seconds,
    observation_notes, priority, category, access_notes, sort_order)
  select p_project_id, x.title, x.url, x.start_seconds, x.end_seconds, x.observation_notes, x.priority,
    x.category, x.access_notes, x.sort_order
  from jsonb_to_recordset(p_references) as x(id uuid, title text, url text, start_seconds int,
    end_seconds int, observation_notes text, priority public.reference_priority, category text,
    access_notes text, sort_order int)
  where x.id is null;
  get diagnostics n = row_count;
  v_changed := v_changed or n > 0;

  return v_changed;
end;
$$;

-- Snapshot of the live deliverables and references, as stored in brief_versions.
create function private.brief_snapshot(p_project_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'deliverables', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'name', d.name, 'format', d.format, 'resolution', d.resolution,
        'aspect_ratio', d.aspect_ratio, 'duration_seconds', d.duration_seconds, 'notes', d.notes,
        'sort_order', d.sort_order) order by d.sort_order, d.id)
      from public.project_deliverables d where d.project_id = p_project_id), '[]'::jsonb),
    'references', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'title', r.title, 'url', r.url, 'start_seconds', r.start_seconds,
        'end_seconds', r.end_seconds, 'observation_notes', r.observation_notes,
        'priority', r.priority, 'category', r.category, 'access_notes', r.access_notes,
        'sort_order', r.sort_order) order by r.sort_order, r.id)
      from public.project_references r where r.project_id = p_project_id), '[]'::jsonb));
$$;

-- §10: what a project needs before it can be opened. Names every missing item.
create function private.check_ready_to_open(p_project_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_project public.projects%rowtype;
  v_brief public.brief_versions%rowtype;
  v_missing text[] := '{}';
begin
  select * into v_project from public.projects where id = p_project_id;
  if v_project.id is null then
    raise exception 'Project not found.' using errcode = 'ES422';
  end if;
  select * into v_brief from public.brief_versions
  where project_id = p_project_id and version = v_project.current_brief_version;

  if nullif(btrim(v_project.title), '') is null then
    v_missing := v_missing || 'a title'::text;
  end if;
  if v_project.brief_type is null then
    v_missing := v_missing || 'a brief type'::text;
  end if;
  if not exists (select 1 from public.project_deliverables where project_id = p_project_id) then
    v_missing := v_missing || 'at least one deliverable'::text;
  end if;
  if v_project.deadline is null then
    v_missing := v_missing || 'a deadline'::text;
  end if;
  if v_project.brief_type = 'fully_instructed' and v_brief.instructions is null then
    v_missing := v_missing || 'instructions'::text;
  end if;
  if v_project.brief_type = 'reference_based'
     and not exists (select 1 from public.project_references where project_id = p_project_id) then
    v_missing := v_missing || 'at least one reference'::text;
  end if;
  if v_project.brief_type = 'creative_led' and v_brief.desired_outcome is null then
    v_missing := v_missing || 'a desired outcome'::text;
  end if;

  if cardinality(v_missing) > 0 then
    raise exception 'Before opening this project, add %.', array_to_string(v_missing, ', ')
      using errcode = 'ES422';
  end if;
end;
$$;

-- A client that a project may link to: exists, not merged, not archived.
create function private.check_linkable_client(p_client_id uuid)
returns void
language plpgsql
volatile -- row locks (for share) are not allowed in stable functions
security definer
set search_path = ''
as $$
begin
  -- for share: a concurrent merge or archive of this client waits until the link is written.
  perform 1 from public.clients
  where id = p_client_id and merged_into_id is null and archived_at is null
  for share;
  if not found then
    raise exception 'Please choose an active client (not archived or merged).' using errcode = 'ES422';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Shared project creation (used by admin_create_project and admin_convert_inquiry).
-- Inserts the draft project, its internal record, live deliverables/references and brief v1
-- with a snapshot. The project.created audit row is written by the projects_audit trigger.
-- ---------------------------------------------------------------------------
create function private.insert_project(p_actor uuid, p_input jsonb, p_source_inquiry_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_title text;
  v_type_text text;
  v_type public.brief_type;
  v_service text;
  v_client uuid;
  v_allowance int;
  v_brief jsonb;
  v_deliverables jsonb;
  v_references jsonb;
  v_snapshot jsonb;
begin
  if p_input is null or jsonb_typeof(p_input) <> 'object' then
    raise exception 'The project details are not valid.' using errcode = 'ES422';
  end if;

  v_title := private.jsonb_text(p_input, 'title', 'title');
  if v_title is null then
    raise exception 'Please give the project a title.' using errcode = 'ES422';
  end if;

  v_type_text := private.jsonb_text(p_input, 'brief_type', 'brief type');
  if v_type_text is null
     or v_type_text not in (select unnest(enum_range(null::public.brief_type))::text) then
    raise exception 'Please choose a brief type.' using errcode = 'ES422';
  end if;
  v_type := v_type_text::public.brief_type;

  v_service := private.jsonb_text(p_input, 'service_type_code', 'service type');
  if v_service is not null and not exists (select 1 from public.service_types where code = v_service) then
    raise exception 'Please choose a valid type of service.' using errcode = 'ES422';
  end if;

  v_client := private.jsonb_uuid(p_input, 'client_id', 'client');
  if v_client is not null then
    perform private.check_linkable_client(v_client);
  end if;

  v_allowance := coalesce(private.jsonb_int(p_input, 'revision_allowance', 'revision allowance'), 3);
  if v_allowance > 20 then
    raise exception 'The revision allowance must be between 0 and 20.' using errcode = 'ES422';
  end if;

  v_brief := private.parse_brief(p_input -> 'brief');
  v_deliverables := private.parse_deliverables(p_input -> 'deliverables');
  v_references := private.parse_references(p_input -> 'references');

  begin
    insert into public.projects (title, brief_type, service_type_code, summary, deadline,
      requires_interpretation, proposed_amount, proposed_currency, revision_allowance,
      current_brief_version, created_by)
    values (
      v_title, v_type, v_service,
      private.jsonb_text(p_input, 'summary', 'summary'),
      private.jsonb_date(p_input, 'deadline', 'deadline'),
      coalesce(private.jsonb_bool(p_input, 'requires_interpretation', 'requires interpretation'),
               v_type <> 'fully_instructed'),
      private.jsonb_amount(p_input, 'proposed_amount', 'proposed pay'),
      private.jsonb_currency(p_input, 'proposed_currency', 'proposed pay currency'),
      v_allowance, 1, p_actor)
    returning id into v_id;

    insert into public.project_internal (project_id, client_id, source_inquiry_id, client_price,
      client_price_currency, internal_notes)
    values (
      v_id, v_client, p_source_inquiry_id,
      private.jsonb_amount(p_input, 'client_price', 'client price'),
      private.jsonb_currency(p_input, 'client_price_currency', 'client price currency'),
      private.jsonb_text(p_input, 'internal_notes', 'internal notes'));

    perform private.sync_brief_rows(v_id, v_deliverables, v_references);
    v_snapshot := private.brief_snapshot(v_id);

    insert into public.brief_versions (project_id, version, created_by, instructions, desired_outcome,
      audience, core_message, brand_constraints, mandatory_content, prohibited_content,
      requires_reacknowledgement, deliverables, "references")
    values (
      v_id, 1, p_actor,
      v_brief ->> 'instructions', v_brief ->> 'desired_outcome', v_brief ->> 'audience',
      v_brief ->> 'core_message', v_brief ->> 'brand_constraints', v_brief ->> 'mandatory_content',
      v_brief ->> 'prohibited_content',
      false, v_snapshot -> 'deliverables', v_snapshot -> 'references');
  exception
    when check_violation then
      raise exception 'Please check your entries: some values are invalid or too long.'
        using errcode = 'ES422';
  end;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
create function public.admin_create_project(p_input jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
begin
  return private.insert_project(v_admin, p_input, null);
end;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges
-- ---------------------------------------------------------------------------
revoke all on function
  private.jsonb_text(jsonb, text, text), private.jsonb_int(jsonb, text, text),
  private.jsonb_amount(jsonb, text, text), private.jsonb_bool(jsonb, text, text),
  private.jsonb_date(jsonb, text, text), private.jsonb_uuid(jsonb, text, text),
  private.jsonb_currency(jsonb, text, text), private.parse_brief(jsonb),
  private.parse_deliverables(jsonb), private.parse_references(jsonb),
  private.sync_brief_rows(uuid, jsonb, jsonb), private.brief_snapshot(uuid),
  private.check_ready_to_open(uuid), private.check_linkable_client(uuid),
  private.insert_project(uuid, jsonb, uuid)
from public, anon, authenticated;

revoke all on function public.admin_create_project(jsonb) from public, anon, authenticated;
grant execute on function public.admin_create_project(jsonb) to anon, authenticated;
