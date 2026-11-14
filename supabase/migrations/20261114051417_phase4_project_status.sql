-- Phase 4 (5/6): project details, status transitions and archive. Spec §7, §10, §14.
-- Every write refuses cancelled and archived projects (ES409); on_hold allows edits.
-- Plan call: brief_type is frozen once the project has been opened (it would change what a
-- version means).

-- ---------------------------------------------------------------------------
-- Transition table (Phase 4 subset, admin-driven). Later phases add their own functions.
-- ---------------------------------------------------------------------------
create function private.project_transition_allowed(
  p_from public.project_status, p_to public.project_status, p_before_hold public.project_status)
returns boolean
language sql
immutable
security definer
set search_path = ''
as $$
  select case
    when p_from = 'draft' then p_to in ('open', 'cancelled', 'on_hold')
    when p_from = 'open' then p_to in ('draft', 'cancelled', 'on_hold')
    when p_from = 'on_hold' then p_before_hold is not null and p_to = p_before_hold
    else false
  end;
$$;

-- ---------------------------------------------------------------------------
-- admin_update_project: details only, never a brief version. Absent keys keep their value;
-- a key given as null clears it (title and brief_type cannot be cleared).
-- ---------------------------------------------------------------------------
create function public.admin_update_project(p_project_id uuid, p_input jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_project public.projects%rowtype;
  v_internal public.project_internal%rowtype;
  v_title text;
  v_type_text text;
  v_type public.brief_type;
  v_service text;
  v_client uuid;
  v_allowance int;
  v_proposed_amount numeric;
  v_proposed_currency char(3);
  v_client_price numeric;
  v_client_price_currency char(3);
  v_pricing_fields text[] := '{}';
begin
  if p_input is null or jsonb_typeof(p_input) <> 'object' then
    raise exception 'The project details are not valid.' using errcode = 'ES422';
  end if;

  select * into v_project from public.projects where id = p_project_id for update;
  if v_project.id is null then
    raise exception 'Project not found.' using errcode = 'ES422';
  end if;
  if v_project.status = 'cancelled' or v_project.archived_at is not null then
    raise exception 'This project is cancelled or archived and cannot be edited.' using errcode = 'ES409';
  end if;
  select * into v_internal from public.project_internal where project_id = p_project_id for update;

  v_title := v_project.title;
  if p_input ? 'title' then
    v_title := private.jsonb_text(p_input, 'title', 'title');
    if v_title is null then
      raise exception 'Please give the project a title.' using errcode = 'ES422';
    end if;
  end if;

  v_type := v_project.brief_type;
  if p_input ? 'brief_type' then
    v_type_text := private.jsonb_text(p_input, 'brief_type', 'brief type');
    if v_type_text is null
       or v_type_text not in (select unnest(enum_range(null::public.brief_type))::text) then
      raise exception 'Please choose a brief type.' using errcode = 'ES422';
    end if;
    v_type := v_type_text::public.brief_type;
    if v_type <> v_project.brief_type and v_project.first_opened_at is not null then
      raise exception 'The brief type cannot change after the project has been opened.' using errcode = 'ES409';
    end if;
  end if;

  v_service := v_project.service_type_code;
  if p_input ? 'service_type_code' then
    v_service := private.jsonb_text(p_input, 'service_type_code', 'service type');
    if v_service is distinct from v_project.service_type_code and v_service is not null
       and not exists (select 1 from public.service_types where code = v_service) then
      raise exception 'Please choose a valid type of service.' using errcode = 'ES422';
    end if;
  end if;

  v_client := v_internal.client_id;
  if p_input ? 'client_id' then
    v_client := private.jsonb_uuid(p_input, 'client_id', 'client');
    if v_client is distinct from v_internal.client_id and v_client is not null then
      perform private.check_linkable_client(v_client);
    end if;
  end if;

  v_allowance := v_project.revision_allowance;
  if p_input ? 'revision_allowance' then
    v_allowance := private.jsonb_int(p_input, 'revision_allowance', 'revision allowance');
    if v_allowance is null or v_allowance > 20 then
      raise exception 'The revision allowance must be between 0 and 20.' using errcode = 'ES422';
    end if;
  end if;

  -- Pricing: resolved up front so actual changes can be audited (field names only).
  v_proposed_amount := case when p_input ? 'proposed_amount'
    then private.jsonb_amount(p_input, 'proposed_amount', 'proposed pay') else v_project.proposed_amount end;
  v_proposed_currency := case when p_input ? 'proposed_currency'
    then private.jsonb_currency(p_input, 'proposed_currency', 'proposed pay currency')
    else v_project.proposed_currency end;
  v_client_price := case when p_input ? 'client_price'
    then private.jsonb_amount(p_input, 'client_price', 'client price') else v_internal.client_price end;
  v_client_price_currency := case when p_input ? 'client_price_currency'
    then private.jsonb_currency(p_input, 'client_price_currency', 'client price currency')
    else v_internal.client_price_currency end;
  if v_proposed_amount is distinct from v_project.proposed_amount then
    v_pricing_fields := v_pricing_fields || 'proposed_amount'::text;
  end if;
  if v_proposed_currency is distinct from v_project.proposed_currency then
    v_pricing_fields := v_pricing_fields || 'proposed_currency'::text;
  end if;
  if v_client_price is distinct from v_internal.client_price then
    v_pricing_fields := v_pricing_fields || 'client_price'::text;
  end if;
  if v_client_price_currency is distinct from v_internal.client_price_currency then
    v_pricing_fields := v_pricing_fields || 'client_price_currency'::text;
  end if;

  begin
    update public.projects set
      title = v_title,
      brief_type = v_type,
      service_type_code = v_service,
      revision_allowance = v_allowance,
      summary = case when p_input ? 'summary'
        then private.jsonb_text(p_input, 'summary', 'summary') else summary end,
      deadline = case when p_input ? 'deadline'
        then private.jsonb_date(p_input, 'deadline', 'deadline') else deadline end,
      requires_interpretation = case when p_input ? 'requires_interpretation'
        then coalesce(private.jsonb_bool(p_input, 'requires_interpretation', 'requires interpretation'),
                      v_type <> 'fully_instructed')
        else requires_interpretation end,
      proposed_amount = v_proposed_amount,
      proposed_currency = v_proposed_currency
    where id = p_project_id;

    update public.project_internal set
      client_id = v_client,
      client_price = v_client_price,
      client_price_currency = v_client_price_currency,
      internal_notes = case when p_input ? 'internal_notes'
        then private.jsonb_text(p_input, 'internal_notes', 'internal notes') else internal_notes end
    where project_id = p_project_id;
  exception
    when check_violation then
      raise exception 'Please check your entries: some values are invalid or too long.' using errcode = 'ES422';
  end;

  if cardinality(v_pricing_fields) > 0 then
    insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
    values (v_admin, 'project.pricing_changed', 'project', p_project_id::text,
            jsonb_build_object('project_id', p_project_id, 'fields', to_jsonb(v_pricing_fields)));
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_set_project_status. Opening always requires readiness (§10); the first opening sets
-- first_opened_at. The audit row (ids and status names only) is written by the projects_audit
-- trigger. p_note is accepted for API stability but discarded: notes are not stored in Phase 4.
-- ---------------------------------------------------------------------------
create function public.admin_set_project_status(
  p_project_id uuid, p_status public.project_status, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_project public.projects%rowtype;
begin
  if p_status is null then
    raise exception 'Please choose a status.' using errcode = 'ES422';
  end if;

  select * into v_project from public.projects where id = p_project_id for update;
  if v_project.id is null then
    raise exception 'Project not found.' using errcode = 'ES422';
  end if;
  if v_project.archived_at is not null then
    raise exception 'This project is archived. Restore it first.' using errcode = 'ES409';
  end if;
  if not private.project_transition_allowed(v_project.status, p_status, v_project.status_before_hold) then
    raise exception 'A project cannot move from % to % here.',
      replace(v_project.status::text, '_', ' '), replace(p_status::text, '_', ' ')
      using errcode = 'ES409';
  end if;

  if p_status = 'open' then
    perform private.check_ready_to_open(p_project_id);
  end if;

  update public.projects set
    status = p_status,
    status_before_hold = case when p_status = 'on_hold' then v_project.status end,
    first_opened_at = case when p_status = 'open' then coalesce(first_opened_at, now()) else first_opened_at end
  where id = p_project_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_archive_project: archive or restore. Archived projects refuse all other writes.
-- ---------------------------------------------------------------------------
create function public.admin_archive_project(p_project_id uuid, p_archive boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_archived_at timestamptz;
  v_found boolean;
begin
  if p_archive is null then
    raise exception 'Please choose whether to archive or restore the project.' using errcode = 'ES422';
  end if;

  select true, archived_at into v_found, v_archived_at
  from public.projects where id = p_project_id for update;
  if v_found is null then
    raise exception 'Project not found.' using errcode = 'ES422';
  end if;
  if p_archive and v_archived_at is not null then
    raise exception 'This project is already archived.' using errcode = 'ES409';
  end if;
  if not p_archive and v_archived_at is null then
    raise exception 'This project is not archived.' using errcode = 'ES409';
  end if;

  update public.projects set archived_at = case when p_archive then now() end where id = p_project_id;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, case when p_archive then 'project.archived' else 'project.restored' end,
          'project', p_project_id::text, jsonb_build_object('project_id', p_project_id));
end;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges
-- ---------------------------------------------------------------------------
revoke all on function
  private.project_transition_allowed(public.project_status, public.project_status, public.project_status)
from public, anon, authenticated;

revoke all on function
  public.admin_update_project(uuid, jsonb),
  public.admin_set_project_status(uuid, public.project_status, text),
  public.admin_archive_project(uuid, boolean)
from public, anon, authenticated;
grant execute on function
  public.admin_update_project(uuid, jsonb),
  public.admin_set_project_status(uuid, public.project_status, text),
  public.admin_archive_project(uuid, boolean)
to anon, authenticated;
