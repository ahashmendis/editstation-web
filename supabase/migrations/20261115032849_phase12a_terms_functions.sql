-- Phase 12A (2/2): terms functions, the confirm gate and earlier-phase changes. Spec §4.1, §5,
-- calls 6, 9, 10. Lock order: the projects row first (as everywhere), then terms rows.
-- Audit rows hold ids, version and field names only (never amounts, percentages or reasons).

-- ---------------------------------------------------------------------------
-- Helpers (private, security definer, no API grants)
-- ---------------------------------------------------------------------------

-- Work has begun on the project: an assignment is (or was) in progress, or work was submitted.
create function private.project_work_started(p_project_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.assignments a where a.project_id = p_project_id and a.status = 'in_progress')
    or exists (select 1 from public.submissions s where s.project_id = p_project_id)
    or exists (select 1 from public.activity_logs l
               join public.assignments a on l.entity_type = 'assignment' and l.entity_id = a.id::text
               where a.project_id = p_project_id and l.action = 'assignment.in_progress');
$$;

-- An editor has accepted, is confirmed or is working: editor pay already rests on the agreed terms.
create function private.project_has_live_editor(p_project_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.assignments a
                 where a.project_id = p_project_id and a.status in ('accepted', 'confirmed', 'in_progress'));
$$;

-- Agreed terms with a valid editor milestone split (the confirm gate, §5).
create function private.terms_ready(p_project_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.project_terms t
                 where t.project_id = p_project_id and t.status = 'agreed'
                   and private.terms_shares_valid(t.editor_milestone_shares));
$$;

-- Day count 0..365 from jsonb.
create function private.jsonb_days(p_obj jsonb, p_key text, p_label text)
returns smallint
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v int := private.jsonb_int(p_obj, p_key, p_label);
begin
  if v is null or v > 365 then
    raise exception 'The % must be a whole number of days from 0 to 365.', p_label using errcode = 'ES422';
  end if;
  return v::smallint;
end;
$$;

-- Editor milestone shares from a jsonb array of whole percentages (validated for 100 at agree).
create function private.parse_terms_shares(p_value jsonb)
returns smallint[]
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v_out smallint[] := '{}';
  e jsonb;
  n numeric;
begin
  if p_value is null or jsonb_typeof(p_value) <> 'array'
     or jsonb_array_length(p_value) not between 1 and 10 then
    raise exception 'Please give 1 to 10 editor pay milestones.' using errcode = 'ES422';
  end if;
  for e in select x from jsonb_array_elements(p_value) x loop
    if jsonb_typeof(e) <> 'number' then
      raise exception 'Each editor pay milestone must be a whole percentage.' using errcode = 'ES422';
    end if;
    n := (e #>> '{}')::numeric;
    if n <> trunc(n) or n < 1 or n > 100 then
      raise exception 'Each editor pay milestone must be a whole percentage from 1 to 100.' using errcode = 'ES422';
    end if;
    v_out := v_out || n::smallint;
  end loop;
  return v_out;
end;
$$;

-- Cancellation stages from a jsonb array of {stage, editor_earned_percent, client_charge_percent}.
-- Returns a clean array; each stage at most once.
create function private.parse_terms_stages(p_value jsonb)
returns jsonb
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v_out jsonb := '[]';
  e jsonb;
  v_stage text;
  v_editor numeric;
  v_client numeric;
begin
  if p_value is null or jsonb_typeof(p_value) = 'null' then
    return v_out;
  end if;
  if jsonb_typeof(p_value) <> 'array' or jsonb_array_length(p_value) > 4 then
    raise exception 'Please check the cancellation schedule.' using errcode = 'ES422';
  end if;
  for e in select x from jsonb_array_elements(p_value) x loop
    if jsonb_typeof(e) <> 'object' then
      raise exception 'Please check the cancellation schedule.' using errcode = 'ES422';
    end if;
    v_stage := private.jsonb_text(e, 'stage', 'cancellation stage');
    if v_stage is null or v_stage not in (select unnest(enum_range(null::public.terms_stage))::text) then
      raise exception 'Please choose a valid cancellation stage.' using errcode = 'ES422';
    end if;
    if v_out @> jsonb_build_array(jsonb_build_object('stage', v_stage)) then
      raise exception 'Each cancellation stage can be listed only once.' using errcode = 'ES422';
    end if;
    v_editor := private.jsonb_amount(e, 'editor_earned_percent', 'editor earned percentage');
    v_client := private.jsonb_amount(e, 'client_charge_percent', 'client charge percentage');
    if v_editor is null or v_client is null or v_editor > 100 or v_client > 100 then
      raise exception 'Cancellation percentages must be from 0 to 100.' using errcode = 'ES422';
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('stage', v_stage,
      'editor_earned_percent', v_editor, 'client_charge_percent', v_client));
  end loop;
  return v_out;
end;
$$;

-- Stage rows of a terms version as {stage: [editor, client]} for comparison.
create function private.terms_stage_map(p_terms_id uuid, p_editor_only boolean)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(s.stage::text,
    case when p_editor_only then to_jsonb(s.editor_earned_percent)
         else jsonb_build_array(s.editor_earned_percent, s.client_charge_percent) end), '{}'::jsonb)
  from public.project_terms_stages s where s.terms_id = p_terms_id;
$$;

-- ---------------------------------------------------------------------------
-- admin_save_terms_draft: edits the project's draft, or starts version n+1 as a copy of the
-- latest version. Absent keys keep their value; `stages` replaces the whole schedule.
-- Returns the draft's id.
-- ---------------------------------------------------------------------------
create function public.admin_save_terms_draft(p_project_id uuid, p_input jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_draft public.project_terms;
  v_latest public.project_terms;
  v_rounds int;
  v_charge numeric;
  v_currency char(3);
  v_stages jsonb;
  v_fields text[] := '{}';
  k text;
begin
  if p_input is null or jsonb_typeof(p_input) <> 'object' then
    raise exception 'The terms are not valid.' using errcode = 'ES422';
  end if;
  for k in select jsonb_object_keys(p_input) loop
    if k not in ('included_rounds', 'extra_round_charge', 'charge_currency', 'deposit_days', 'balance_days',
                 'editor_pay_days', 'late_balance_days', 'editor_milestone_shares', 'stages', 'change_reason') then
      raise exception 'The terms are not valid.' using errcode = 'ES422';
    end if;
    v_fields := v_fields || k;
  end loop;

  perform private.lock_writable_project(p_project_id);

  select * into v_draft from public.project_terms
  where project_id = p_project_id and status = 'draft' for update;
  if v_draft.id is null then
    select * into v_latest from public.project_terms
    where project_id = p_project_id order by version desc limit 1;
    insert into public.project_terms (project_id, version, status, included_rounds, extra_round_charge,
      charge_currency, deposit_days, balance_days, editor_pay_days, late_balance_days, editor_milestone_shares,
      created_by)
    values (p_project_id, coalesce(v_latest.version, 0) + 1, 'draft', coalesce(v_latest.included_rounds, 3),
      v_latest.extra_round_charge, v_latest.charge_currency, coalesce(v_latest.deposit_days, 14),
      coalesce(v_latest.balance_days, 7), coalesce(v_latest.editor_pay_days, 7),
      coalesce(v_latest.late_balance_days, 14), coalesce(v_latest.editor_milestone_shares, '{50,50}'), v_admin)
    returning * into v_draft;
    if v_latest.id is not null then
      insert into public.project_terms_stages (terms_id, stage, editor_earned_percent, client_charge_percent)
      select v_draft.id, s.stage, s.editor_earned_percent, s.client_charge_percent
      from public.project_terms_stages s where s.terms_id = v_latest.id;
    end if;
  end if;

  if p_input ? 'included_rounds' then
    v_rounds := private.jsonb_int(p_input, 'included_rounds', 'included revision rounds');
    if v_rounds is null or v_rounds > 20 then
      raise exception 'Included revision rounds must be from 0 to 20.' using errcode = 'ES422';
    end if;
  end if;
  v_charge := case when p_input ? 'extra_round_charge'
    then private.jsonb_amount(p_input, 'extra_round_charge', 'extra round charge') else v_draft.extra_round_charge end;
  v_currency := case when v_charge is null then null
    when p_input ? 'charge_currency' then private.jsonb_currency(p_input, 'charge_currency', 'charge currency')
    else coalesce(v_draft.charge_currency, 'LKR') end;
  if p_input ? 'stages' then
    v_stages := private.parse_terms_stages(p_input -> 'stages');
  end if;

  begin
    update public.project_terms set
      included_rounds = coalesce(v_rounds, included_rounds),
      extra_round_charge = v_charge,
      charge_currency = v_currency,
      deposit_days = case when p_input ? 'deposit_days'
        then private.jsonb_days(p_input, 'deposit_days', 'deposit due days') else deposit_days end,
      balance_days = case when p_input ? 'balance_days'
        then private.jsonb_days(p_input, 'balance_days', 'balance due days') else balance_days end,
      editor_pay_days = case when p_input ? 'editor_pay_days'
        then private.jsonb_days(p_input, 'editor_pay_days', 'editor pay days') else editor_pay_days end,
      late_balance_days = case when p_input ? 'late_balance_days'
        then private.jsonb_days(p_input, 'late_balance_days', 'late balance days') else late_balance_days end,
      editor_milestone_shares = case when p_input ? 'editor_milestone_shares'
        then private.parse_terms_shares(p_input -> 'editor_milestone_shares') else editor_milestone_shares end,
      change_reason = case when p_input ? 'change_reason'
        then private.clean_text(private.jsonb_text(p_input, 'change_reason', 'reason for the change'), 2000,
                                'reason for the change')
        else change_reason end
    where id = v_draft.id;

    if v_stages is not null then
      delete from public.project_terms_stages where terms_id = v_draft.id;
      insert into public.project_terms_stages (terms_id, stage, editor_earned_percent, client_charge_percent)
      select v_draft.id, (e ->> 'stage')::public.terms_stage, (e ->> 'editor_earned_percent')::numeric,
        (e ->> 'client_charge_percent')::numeric
      from jsonb_array_elements(v_stages) e;
    end if;
  exception
    when check_violation then
      raise exception 'Please check the terms: some values are invalid.' using errcode = 'ES422';
  end;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'project_terms.draft_saved', 'project', p_project_id::text,
    jsonb_build_object('project_id', p_project_id, 'terms_id', v_draft.id, 'version', v_draft.version,
      'fields', to_jsonb(v_fields)));
  return v_draft.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_agree_terms: agrees the draft with this version number. Race-safe: the project row is
-- locked, and only the current draft (the highest version) can be agreed, so a second agree of
-- the same version is refused. Call 6: once work has begun, version >= 2 needs a reason; once an
-- editor is confirmed, editor pay terms cannot change (that needs the editor's acceptance, which
-- arrives with adjustments in 12D); day counts are fixed once work has begun.
-- ---------------------------------------------------------------------------
create function public.admin_agree_terms(p_project_id uuid, p_version int, p_change_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_draft public.project_terms;
  v_prev public.project_terms;
  v_reason text := private.clean_text(p_change_reason, 2000, 'reason for the change');
  v_fields text[] := '{}';
  v_started boolean;
begin
  perform private.lock_writable_project(p_project_id);

  select * into v_draft from public.project_terms
  where project_id = p_project_id and version = p_version for update;
  if v_draft.id is null then
    raise exception 'These terms were not found.' using errcode = 'ES422';
  end if;
  if v_draft.status <> 'draft' then
    raise exception 'This version has already been agreed or replaced. Refresh to see the latest terms.'
      using errcode = 'ES409';
  end if;
  if not private.terms_shares_valid(v_draft.editor_milestone_shares) then
    raise exception 'The editor pay milestones must add up to 100%%.' using errcode = 'ES422';
  end if;

  select * into v_prev from public.project_terms
  where project_id = p_project_id and status = 'agreed' for update;
  v_reason := coalesce(v_reason, v_draft.change_reason);
  v_started := private.project_work_started(p_project_id);

  if v_prev.id is not null then
    if v_draft.included_rounds <> v_prev.included_rounds then v_fields := v_fields || 'included_rounds'::text; end if;
    if (v_draft.extra_round_charge, v_draft.charge_currency) is distinct from (v_prev.extra_round_charge, v_prev.charge_currency) then
      v_fields := v_fields || 'extra_round_charge'::text;
    end if;
    if (v_draft.deposit_days, v_draft.balance_days, v_draft.editor_pay_days, v_draft.late_balance_days)
       is distinct from (v_prev.deposit_days, v_prev.balance_days, v_prev.editor_pay_days, v_prev.late_balance_days) then
      v_fields := v_fields || 'day_counts'::text;
    end if;
    if v_draft.editor_milestone_shares <> v_prev.editor_milestone_shares then
      v_fields := v_fields || 'editor_milestone_shares'::text;
    end if;
    if private.terms_stage_map(v_draft.id, false) <> private.terms_stage_map(v_prev.id, false) then
      v_fields := v_fields || 'stages'::text;
    end if;

    if private.project_has_live_editor(p_project_id)
       and (v_draft.editor_milestone_shares <> v_prev.editor_milestone_shares
            or private.terms_stage_map(v_draft.id, true) <> private.terms_stage_map(v_prev.id, true)) then
      raise exception 'Editor pay terms cannot change after an editor has accepted: that needs the editor''s agreement.'
        using errcode = 'ES409';
    end if;
    if v_started and 'day_counts' = any (v_fields) then
      raise exception 'Payment day counts cannot change after work has begun.' using errcode = 'ES409';
    end if;
  end if;

  if v_draft.version >= 2 and v_started and v_reason is null then
    raise exception 'Please give a reason for changing the terms after work has begun.' using errcode = 'ES422';
  end if;

  if v_prev.id is not null then
    update public.project_terms set status = 'superseded', superseded_at = now() where id = v_prev.id;
  end if;
  update public.project_terms
  set status = 'agreed', agreed_by = v_admin, agreed_at = now(), change_reason = v_reason
  where id = v_draft.id;

  -- Refresh the Phase 8 cache and the beyond-allowance flags.
  update public.projects set revision_allowance = v_draft.included_rounds
  where id = p_project_id and revision_allowance is distinct from v_draft.included_rounds;
  perform private.renumber_client_rounds(p_project_id);

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'project_terms.agreed', 'project', p_project_id::text,
    jsonb_build_object('project_id', p_project_id, 'terms_id', v_draft.id, 'version', v_draft.version,
      'superseded_id', v_prev.id, 'fields', to_jsonb(v_fields)));
end;
$$;

-- ---------------------------------------------------------------------------
-- editor_get_terms: the editor-safe projection of the agreed terms for an editor who can see the
-- project (opportunity or assigned stage). Never client charges, client percentages or client
-- milestones. No row when nothing is agreed yet.
-- ---------------------------------------------------------------------------
create function public.editor_get_terms(p_project_id uuid)
returns table (version int, agreed_at timestamptz, included_rounds smallint, editor_milestone_shares smallint[],
  editor_kill_fee jsonb)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_active_editor();
  if private.editor_project_stage(p_project_id) not in ('opportunity', 'assigned') then
    raise exception 'Project not found.' using errcode = 'ES422';
  end if;
  return query
  select t.version, t.agreed_at, t.included_rounds, t.editor_milestone_shares,
    coalesce((select jsonb_agg(jsonb_build_object('stage', s.stage, 'editor_earned_percent', s.editor_earned_percent)
                               order by s.stage)
              from public.project_terms_stages s where s.terms_id = t.id), '[]'::jsonb)
  from public.project_terms t
  where t.project_id = p_project_id and t.status = 'agreed';
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_confirm_assignment (Phase 6) + the confirm gate (§5): agreed terms with a valid editor
-- milestone split. Otherwise unchanged.
-- ---------------------------------------------------------------------------
create or replace function public.admin_confirm_assignment(p_assignment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v public.assignments;
  v_project public.projects;
begin
  v := private.lock_assignment(p_assignment_id);
  -- Already locked by lock_assignment (project first); read it under the same lock.
  select * into v_project from public.projects where id = v.project_id for update;
  if v.status <> 'accepted' or v.agreed_amount is null then
    raise exception 'Only an accepted offer can be confirmed.' using errcode = 'ES409';
  end if;
  if v_project.status <> 'open' or v_project.archived_at is not null then
    raise exception 'An editor can be confirmed only while the project is open.' using errcode = 'ES409';
  end if;
  if not exists (select 1 from public.editor_profiles where user_id = v.editor_id and access_status = 'active') then
    raise exception 'This editor''s access is not active, so they cannot be confirmed.' using errcode = 'ES409';
  end if;
  if not private.terms_ready(v.project_id) then
    raise exception 'Agree the project terms (with editor pay milestones adding up to 100%%) before confirming an editor.'
      using errcode = 'ES409';
  end if;

  begin
    update public.assignments
    set status = 'confirmed', confirmed_by = v_admin, confirmed_at = now()
    where id = v.id;
  exception
    when unique_violation then
      raise exception 'Another editor is already confirmed for this project.' using errcode = 'ES409';
  end;
  update public.projects set status = 'assigned' where id = v.project_id;
  perform private.close_live_assignments(v.project_id, 'not_selected', v_admin, null, v.id);
  perform private.revoke_live_access(v.project_id, v_admin, null, v.editor_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_update_project (Phase 4): no longer accepts revision_allowance (it is set by agreeing
-- terms). Otherwise unchanged.
-- ---------------------------------------------------------------------------
create or replace function public.admin_update_project(p_project_id uuid, p_input jsonb)
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
  v_proposed_amount numeric;
  v_proposed_currency char(3);
  v_client_price numeric;
  v_client_price_currency char(3);
  v_pricing_fields text[] := '{}';
begin
  if p_input is null or jsonb_typeof(p_input) <> 'object' then
    raise exception 'The project details are not valid.' using errcode = 'ES422';
  end if;
  if p_input ? 'revision_allowance' then
    raise exception 'Included revision rounds are changed in the project terms.' using errcode = 'ES422';
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
-- Function privileges: private helpers for no API role; public functions for anon and
-- authenticated (they authorise in the body), never PUBLIC.
-- ---------------------------------------------------------------------------
revoke all on function
  private.project_work_started(uuid), private.project_has_live_editor(uuid), private.terms_ready(uuid),
  private.jsonb_days(jsonb, text, text), private.parse_terms_shares(jsonb), private.parse_terms_stages(jsonb),
  private.terms_stage_map(uuid, boolean)
from public, anon, authenticated;

grant execute on function
  public.admin_save_terms_draft(uuid, jsonb), public.admin_agree_terms(uuid, int, text),
  public.editor_get_terms(uuid)
to anon, authenticated;
revoke execute on function
  public.admin_save_terms_draft(uuid, jsonb), public.admin_agree_terms(uuid, int, text),
  public.editor_get_terms(uuid)
from public;
