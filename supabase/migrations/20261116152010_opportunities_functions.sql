-- Open opportunities (3/3): functions. Spec docs/superpowers/specs/2026-11-16-open-opportunities-design.md
-- §4, owner approval 2026-11-16 with every recommended §7 call:
--   1 shown pay chosen per opportunity (default hidden)   2 all active editors
--   3 at most 10 live interests per editor; none on a project the editor was declined or not
--     selected for                                          4 the proposed rate is only a signal
--   5 closes on selection, admin close, or (for new interest) an optional closing date
--   6 bell notifications                                    8 direct invitations stay
-- Choosing an editor calls public.admin_make_offer, so pay, terms and every later gate are the
-- existing flow, unchanged.
-- Lock order: the projects row first (as everywhere), then the opportunity row, then (selection)
-- the chosen interest row, then assignments (inside admin_make_offer, which re-locks the already
-- held project row first), then the other interest rows. Editors never lock project rows: registering holds the
-- opportunity row for share (so a concurrent selection either waits for it or is seen as closed)
-- and a per-editor advisory lock for the limit; withdrawing locks only the editor's own row.
-- Audit rows hold ids and field names only (never amounts, notes or summary text).

-- ---------------------------------------------------------------------------
-- Helpers (private, no API grants)
-- ---------------------------------------------------------------------------

-- Locks the project, then the opportunity. ES422 when it does not exist.
create function private.lock_opportunity(p_opportunity_id uuid)
returns public.project_opportunities
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_project uuid;
  v public.project_opportunities;
begin
  select project_id into v_project from public.project_opportunities where id = p_opportunity_id;
  if v_project is null then
    raise exception 'Opportunity not found.' using errcode = 'ES422';
  end if;
  perform 1 from public.projects where id = v_project for update;
  select * into v from public.project_opportunities where id = p_opportunity_id for update;
  return v;
end;
$$;

-- True when the opportunity takes new interest now.
create function private.opportunity_accepting(p_opportunity public.project_opportunities)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_opportunity.status = 'open'
    and (p_opportunity.closes_at is null or p_opportunity.closes_at > now())
    and exists (select 1 from public.projects p
                where p.id = p_opportunity.project_id and p.status = 'open' and p.archived_at is null);
$$;

-- Validates and cleans the admin-written summary. Returns a row with only those fields set.
create function private.clean_opportunity(p_title text, p_deliverables_summary text, p_service_type_code text,
  p_deadline date, p_format_notes text, p_shown_pay_amount numeric, p_shown_pay_currency text,
  p_closes_at timestamptz)
returns public.project_opportunities
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v public.project_opportunities;
begin
  v.title := private.clean_text(p_title, 120, 'title');
  if v.title is null then
    raise exception 'Please give the opportunity a title.' using errcode = 'ES422';
  end if;
  v.deliverables_summary := private.clean_text(p_deliverables_summary, 1000, 'deliverables summary');
  if v.deliverables_summary is null then
    raise exception 'Please summarise the deliverables.' using errcode = 'ES422';
  end if;
  v.format_notes := private.clean_text(p_format_notes, 1000, 'format notes');
  v.service_type_code := nullif(btrim(p_service_type_code), '');
  if v.service_type_code is not null
     and not exists (select 1 from public.service_types s where s.code = v.service_type_code and s.active) then
    raise exception 'Choose a service type from the list.' using errcode = 'ES422';
  end if;
  if p_deadline is not null and p_deadline < (now() at time zone 'Asia/Colombo')::date then
    raise exception 'The deadline cannot be in the past.' using errcode = 'ES422';
  end if;
  v.deadline := p_deadline;
  if p_shown_pay_amount is not null then
    v.shown_pay_amount := private.check_amount(p_shown_pay_amount, 'pay shown to editors');
    v.shown_pay_currency := private.check_currency(p_shown_pay_currency, 'LKR');
  end if;
  if p_closes_at is not null and p_closes_at <= now() then
    raise exception 'The closing date must be in the future.' using errcode = 'ES422';
  end if;
  v.closes_at := p_closes_at;
  return v;
end;
$$;

-- Closes an open opportunity (the caller holds the project and opportunity locks). Every live
-- interest except p_except_interest becomes not_selected and its editor is notified.
-- p_project_fields: for a close caused by a project change, the project field names that changed.
create function private.close_opportunity(p_opportunity_id uuid, p_status public.opportunity_status,
  p_reason text, p_actor uuid, p_except_interest uuid default null, p_project_fields text[] default null)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.project_opportunities;
  r record;
  n int := 0;
begin
  select * into v from public.project_opportunities where id = p_opportunity_id for update;
  if v.id is null or v.status <> 'open' then
    return 0;
  end if;
  update public.project_opportunities
  set status = p_status, close_reason = p_reason, closed_at = now(), closed_by = p_actor
  where id = v.id;
  for r in
    select i.id, i.editor_id from public.opportunity_interests i
    where i.opportunity_id = v.id and i.status = 'interested'
      and (p_except_interest is null or i.id <> p_except_interest)
    order by i.id
    for update
  loop
    update public.opportunity_interests set status = 'not_selected', decided_at = now() where id = r.id;
    insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
    values (p_actor, 'opportunity_interest.not_selected', 'opportunity_interest', r.id::text,
      jsonb_build_object('opportunity_id', v.id, 'project_id', v.project_id, 'editor_id', r.editor_id));
    perform private.notify(array[r.editor_id], 'opportunity_not_selected', 'project_opportunity', v.id,
      'Not selected',
      case when p_reason = 'selected'
        then format('Another editor was chosen for "%s". Thank you for your interest.', v.title)
        else format('"%s" has closed. Thank you for your interest.', v.title) end);
    n := n + 1;
  end loop;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (p_actor, 'opportunity.closed', 'project_opportunity', v.id::text,
    jsonb_build_object('opportunity_id', v.id, 'project_id', v.project_id, 'status', p_status,
      'reason', p_reason, 'not_selected', n)
    || case when p_project_fields is null then '{}'::jsonb
         else jsonb_build_object('closed_by_project_change', true, 'project_fields', to_jsonb(p_project_fields)) end);
  return n;
end;
$$;

-- A project that leaves the open stage for good (an editor confirmed directly, cancelled,
-- completed, archived) closes its open opportunity. Draft and on hold only hide it.
create function private.close_opportunity_on_project_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_fields text[] := '{}';
begin
  if (new.status is distinct from old.status or new.archived_at is distinct from old.archived_at)
     and (new.status not in ('draft', 'open', 'on_hold') or new.archived_at is not null) then
    select id into v_id from public.project_opportunities where project_id = new.id and status = 'open';
    if v_id is not null then
      if new.status is distinct from old.status then v_fields := array_append(v_fields, 'status'); end if;
      if new.archived_at is distinct from old.archived_at then v_fields := array_append(v_fields, 'archived_at'); end if;
      perform private.close_opportunity(v_id, 'closed', 'project_closed', (select auth.uid()), null, v_fields);
    end if;
  end if;
  return null;
end;
$$;

create trigger projects_close_opportunity
  after update of status, archived_at on public.projects
  for each row execute function private.close_opportunity_on_project_change();

-- ---------------------------------------------------------------------------
-- admin_publish_opportunity: publishes an open project's summary (or reopens a closed one with
-- the new summary). Admins can still invite editors directly without publishing (call 8).
-- ---------------------------------------------------------------------------
create function public.admin_publish_opportunity(
  p_project_id uuid, p_title text, p_deliverables_summary text, p_service_type_code text default null,
  p_deadline date default null, p_format_notes text default null, p_shown_pay_amount numeric default null,
  p_shown_pay_currency text default null, p_closes_at timestamptz default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_project public.projects;
  v_old public.project_opportunities;
  c public.project_opportunities;
  v_id uuid;
begin
  select * into v_project from public.projects where id = p_project_id for update;
  if v_project.id is null then
    raise exception 'Project not found.' using errcode = 'ES422';
  end if;
  if v_project.status <> 'open' or v_project.archived_at is not null then
    raise exception 'Only an open project without a confirmed editor can be published as an opportunity.'
      using errcode = 'ES409';
  end if;
  c := private.clean_opportunity(p_title, p_deliverables_summary, p_service_type_code, p_deadline,
    p_format_notes, p_shown_pay_amount, p_shown_pay_currency, p_closes_at);

  select * into v_old from public.project_opportunities where project_id = p_project_id for update;
  if v_old.id is not null and v_old.status = 'open' then
    raise exception 'This project is already published as an opportunity. Edit it instead.' using errcode = 'ES409';
  end if;
  if v_old.id is not null then
    update public.project_opportunities
    set title = c.title, service_type_code = c.service_type_code, deliverables_summary = c.deliverables_summary,
        deadline = c.deadline, format_notes = c.format_notes, shown_pay_amount = c.shown_pay_amount,
        shown_pay_currency = c.shown_pay_currency, closes_at = c.closes_at, status = 'open',
        close_reason = null, closed_at = null, closed_by = null, published_by = v_admin, published_at = now()
    where id = v_old.id;
    v_id := v_old.id;
  else
    insert into public.project_opportunities (project_id, title, service_type_code, deliverables_summary, deadline,
      format_notes, shown_pay_amount, shown_pay_currency, closes_at, published_by)
    values (p_project_id, c.title, c.service_type_code, c.deliverables_summary, c.deadline, c.format_notes,
      c.shown_pay_amount, c.shown_pay_currency, c.closes_at, v_admin)
    returning id into v_id;
  end if;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'opportunity.published', 'project_opportunity', v_id::text,
    jsonb_build_object('opportunity_id', v_id, 'project_id', p_project_id, 'reopened', v_old.id is not null,
      'shows_pay', c.shown_pay_amount is not null));
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_update_opportunity: edits the summary of an open opportunity.
-- ---------------------------------------------------------------------------
create function public.admin_update_opportunity(
  p_opportunity_id uuid, p_title text, p_deliverables_summary text, p_service_type_code text default null,
  p_deadline date default null, p_format_notes text default null, p_shown_pay_amount numeric default null,
  p_shown_pay_currency text default null, p_closes_at timestamptz default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v public.project_opportunities;
  c public.project_opportunities;
  v_fields text[] := '{}';
begin
  v := private.lock_opportunity(p_opportunity_id);
  if v.status <> 'open' then
    raise exception 'This opportunity is closed. Publish it again to reopen it.' using errcode = 'ES409';
  end if;
  c := private.clean_opportunity(p_title, p_deliverables_summary, p_service_type_code, p_deadline,
    p_format_notes, p_shown_pay_amount, p_shown_pay_currency, p_closes_at);
  if v.title is distinct from c.title then v_fields := array_append(v_fields, 'title'); end if;
  if v.deliverables_summary is distinct from c.deliverables_summary then
    v_fields := array_append(v_fields, 'deliverables_summary'); end if;
  if v.service_type_code is distinct from c.service_type_code then
    v_fields := array_append(v_fields, 'service_type_code'); end if;
  if v.deadline is distinct from c.deadline then v_fields := array_append(v_fields, 'deadline'); end if;
  if v.format_notes is distinct from c.format_notes then v_fields := array_append(v_fields, 'format_notes'); end if;
  if (v.shown_pay_amount, v.shown_pay_currency) is distinct from (c.shown_pay_amount, c.shown_pay_currency) then
    v_fields := array_append(v_fields, 'shown_pay'); end if;
  if v.closes_at is distinct from c.closes_at then v_fields := array_append(v_fields, 'closes_at'); end if;
  if cardinality(v_fields) = 0 then
    return;
  end if;
  update public.project_opportunities
  set title = c.title, service_type_code = c.service_type_code, deliverables_summary = c.deliverables_summary,
      deadline = c.deadline, format_notes = c.format_notes, shown_pay_amount = c.shown_pay_amount,
      shown_pay_currency = c.shown_pay_currency, closes_at = c.closes_at
  where id = v.id;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'opportunity.updated', 'project_opportunity', v.id::text,
    jsonb_build_object('opportunity_id', v.id, 'project_id', v.project_id, 'fields', to_jsonb(v_fields)));
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_close_opportunity: every interested editor becomes not selected (and is notified).
-- ---------------------------------------------------------------------------
create function public.admin_close_opportunity(p_opportunity_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v public.project_opportunities;
begin
  v := private.lock_opportunity(p_opportunity_id);
  if v.status <> 'open' then
    raise exception 'This opportunity is already closed.' using errcode = 'ES409';
  end if;
  perform private.close_opportunity(v.id, 'closed', 'admin', v_admin);
end;
$$;

-- ---------------------------------------------------------------------------
-- editor_list_opportunities: the summary projection (an allow-list of columns) for active
-- editors: every opportunity taking interest now, plus any the caller has an interest on, with
-- the caller's latest interest. The project id is returned only once the caller was selected.
-- ---------------------------------------------------------------------------
create function public.editor_list_opportunities()
returns table (
  opportunity_id uuid, title text, service_type text, deliverables_summary text, deadline date,
  format_notes text, shown_pay_amount numeric, shown_pay_currency text, closes_at timestamptz,
  published_at timestamptz, accepting_interest boolean, interest_id uuid,
  interest_status public.opportunity_interest_status, proposed_amount numeric, proposed_currency text,
  note text, selected_project_id uuid)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := private.require_active_editor();
begin
  return query
  select o.id, o.title, s.label, o.deliverables_summary, o.deadline, o.format_notes, o.shown_pay_amount,
    o.shown_pay_currency::text, o.closes_at, o.published_at, private.opportunity_accepting(o),
    i.id, i.status, i.proposed_amount, i.proposed_currency::text, i.note,
    case when i.status = 'selected' then o.project_id end
  from public.project_opportunities o
  left join public.service_types s on s.code = o.service_type_code
  left join lateral (
    select x.* from public.opportunity_interests x
    where x.opportunity_id = o.id and x.editor_id = v_uid
    order by x.created_at desc, x.id desc limit 1) i on true
  where private.opportunity_accepting(o) or i.id is not null
  order by private.opportunity_accepting(o) desc, o.published_at desc, o.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- editor_register_interest (calls 3, 4)
-- ---------------------------------------------------------------------------
create function public.editor_register_interest(p_opportunity_id uuid, p_proposed_amount numeric default null,
  p_proposed_currency text default null, p_note text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_editor();
  v public.project_opportunities;
  v_amount numeric;
  v_currency char(3);
  v_note text;
  v_id uuid;
begin
  select * into v from public.project_opportunities where id = p_opportunity_id for share;
  if v.id is null then
    raise exception 'Opportunity not found.' using errcode = 'ES422';
  end if;
  if not private.opportunity_accepting(v) then
    raise exception 'This opportunity is no longer taking interest.' using errcode = 'ES409';
  end if;
  if p_proposed_amount is not null then
    v_amount := private.check_amount(p_proposed_amount, 'proposed rate');
    v_currency := private.check_currency(p_proposed_currency, coalesce(v.shown_pay_currency, 'LKR'));
  end if;
  v_note := private.clean_text(p_note, 500, 'note');

  -- Serialises this editor's registrations so the limit holds under concurrency.
  perform pg_advisory_xact_lock(hashtextextended('opportunity_interest:' || v_uid::text, 0));
  if exists (select 1 from public.opportunity_interests
             where opportunity_id = v.id and editor_id = v_uid and status in ('interested', 'selected')) then
    raise exception 'You have already registered interest in this opportunity.' using errcode = 'ES409';
  end if;
  if exists (select 1 from public.opportunity_interests
             where opportunity_id = v.id and editor_id = v_uid and status = 'not_selected')
     or exists (select 1 from public.assignments
                where project_id = v.project_id and editor_id = v_uid and status in ('declined', 'not_selected')) then
    raise exception 'You cannot register interest in this project again.' using errcode = 'ES409';
  end if;
  if exists (select 1 from public.assignments
             where project_id = v.project_id and editor_id = v_uid
               and status in ('offered', 'counteroffer_pending', 'accepted', 'confirmed', 'in_progress')) then
    raise exception 'You already have an offer on this project. Answer it from your dashboard.' using errcode = 'ES409';
  end if;
  -- Only `interested` rows on opportunities still taking interest count: a stale row (closed,
  -- past its closing date, project on hold or back in draft) never blocks the editor.
  if (select count(*) from public.opportunity_interests i
      join public.project_opportunities o on o.id = i.opportunity_id
      where i.editor_id = v_uid and i.status = 'interested' and private.opportunity_accepting(o)) >= 10 then
    raise exception 'You can be interested in up to 10 opportunities at a time. Withdraw one first.'
      using errcode = 'ES409';
  end if;

  begin
    insert into public.opportunity_interests (opportunity_id, editor_id, proposed_amount, proposed_currency, note)
    values (v.id, v_uid, v_amount, v_currency, v_note)
    returning id into v_id;
  exception
    when unique_violation then
      raise exception 'You have already registered interest in this opportunity.' using errcode = 'ES409';
  end;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_uid, 'opportunity_interest.registered', 'opportunity_interest', v_id::text,
    jsonb_build_object('opportunity_id', v.id, 'project_id', v.project_id, 'editor_id', v_uid,
      'fields', to_jsonb(array_remove(array[
        case when v_amount is not null then 'proposed_amount' end,
        case when v_note is not null then 'note' end], null))));
  perform private.notify(private.active_admin_ids(), 'interest_registered', 'project', v.project_id,
    'New interest in an opportunity',
    format('An editor registered interest in "%s".', private.project_title(v.project_id)));
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- editor_withdraw_interest: own row, only while interested.
-- ---------------------------------------------------------------------------
create function public.editor_withdraw_interest(p_interest_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_editor();
  v public.opportunity_interests;
begin
  select * into v from public.opportunity_interests
  where id = p_interest_id and editor_id = v_uid for update;
  if v.id is null then
    raise exception 'Interest not found.' using errcode = 'ES422';
  end if;
  if v.status = 'selected' then
    raise exception 'You were already selected. Answer the offer on the project page instead.' using errcode = 'ES409';
  end if;
  if v.status <> 'interested' then
    raise exception 'This interest is already closed.' using errcode = 'ES409';
  end if;
  update public.opportunity_interests set status = 'withdrawn', decided_at = now() where id = v.id;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_uid, 'opportunity_interest.withdrawn', 'opportunity_interest', v.id::text,
    jsonb_build_object('opportunity_id', v.opportunity_id, 'editor_id', v_uid));
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_list_interests: every interest row on an opportunity, live ones first.
-- ---------------------------------------------------------------------------
create function public.admin_list_interests(p_opportunity_id uuid)
returns table (
  interest_id uuid, editor_id uuid, editor_name text, editor_access_status public.editor_access_status,
  status public.opportunity_interest_status, proposed_amount numeric, proposed_currency text, note text,
  created_at timestamptz, decided_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_admin uuid := private.require_admin();
begin
  if not exists (select 1 from public.project_opportunities where id = p_opportunity_id) then
    raise exception 'Opportunity not found.' using errcode = 'ES422';
  end if;
  return query
  select i.id, i.editor_id, private.admin_display_name(i.editor_id), e.access_status, i.status,
    i.proposed_amount, i.proposed_currency::text, i.note, i.created_at, i.decided_at
  from public.opportunity_interests i
  left join public.editor_profiles e on e.user_id = i.editor_id
  where i.opportunity_id = p_opportunity_id
  order by (i.status in ('interested', 'selected')) desc, i.created_at, i.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_get_opportunity: the project's opportunity (every column) and its interests in one round
-- trip for the admin project page. {"opportunity": null, "interests": []} when not published.
-- ---------------------------------------------------------------------------
create function public.admin_get_opportunity(p_project_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  o public.project_opportunities;
begin
  if not exists (select 1 from public.projects where id = p_project_id) then
    raise exception 'Project not found.' using errcode = 'ES422';
  end if;
  select * into o from public.project_opportunities where project_id = p_project_id;
  if o.id is null then
    return jsonb_build_object('opportunity', null, 'interests', '[]'::jsonb);
  end if;
  return jsonb_build_object(
    'opportunity', to_jsonb(o),
    'interests', coalesce((select jsonb_agg(to_jsonb(x)) from public.admin_list_interests(o.id) x), '[]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_select_editor: the admin chooses one interested editor. Makes the existing offer
-- (public.admin_make_offer: the admin's amount, never the proposed rate), marks the interest
-- selected, every other live interest not_selected, and fills the opportunity.
-- ---------------------------------------------------------------------------
create function public.admin_select_editor(p_interest_id uuid, p_amount numeric, p_currency text default null,
  p_message text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_opportunity uuid;
  o public.project_opportunities;
  p public.projects;
  i public.opportunity_interests;
  v_assignment uuid;
begin
  select opportunity_id into v_opportunity from public.opportunity_interests where id = p_interest_id;
  if v_opportunity is null then
    raise exception 'Interest not found.' using errcode = 'ES422';
  end if;
  o := private.lock_opportunity(v_opportunity);
  select * into p from public.projects where id = o.project_id;
  select * into i from public.opportunity_interests where id = p_interest_id for update;

  if o.status = 'filled' then
    raise exception 'An editor was already chosen for this opportunity.' using errcode = 'ES409';
  end if;
  if o.status <> 'open' then
    raise exception 'This opportunity is closed. Publish it again to choose an editor.' using errcode = 'ES409';
  end if;
  if p.status <> 'open' or p.archived_at is not null then
    raise exception 'The project is not open (it is %), so an editor cannot be chosen now.',
      replace(p.status::text, '_', ' ') using errcode = 'ES409';
  end if;
  if i.status = 'withdrawn' then
    raise exception 'This editor withdrew their interest.' using errcode = 'ES409';
  end if;
  if i.status <> 'interested' then
    raise exception 'This interest is already closed.' using errcode = 'ES409';
  end if;
  if not exists (select 1 from public.editor_profiles where user_id = i.editor_id and access_status = 'active') then
    raise exception 'This editor''s access is not active, so they cannot be chosen.' using errcode = 'ES409';
  end if;
  if exists (select 1 from public.assignments
             where project_id = o.project_id and editor_id = i.editor_id
               and status in ('offered', 'counteroffer_pending', 'accepted', 'confirmed', 'in_progress')) then
    raise exception 'This editor already has a live offer on this project. Continue it in the Editors card.'
      using errcode = 'ES409';
  end if;

  -- The existing offer path: same checks, access row, assignment and negotiation history.
  v_assignment := public.admin_make_offer(o.project_id, i.editor_id, p_amount, p_currency, p_message);

  update public.opportunity_interests set status = 'selected', decided_at = now() where id = i.id;
  perform private.close_opportunity(o.id, 'filled', 'selected', v_admin, i.id);
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'opportunity_interest.selected', 'opportunity_interest', i.id::text,
    jsonb_build_object('opportunity_id', o.id, 'project_id', o.project_id, 'editor_id', i.editor_id,
      'assignment_id', v_assignment));
  perform private.notify(array[i.editor_id], 'opportunity_selected', 'project', o.project_id,
    'You were chosen',
    format('You were chosen for "%s". Open the project to answer the offer.', o.title));
  return v_assignment;
end;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges
-- ---------------------------------------------------------------------------
revoke all on function
  private.lock_opportunity(uuid), private.opportunity_accepting(public.project_opportunities),
  private.clean_opportunity(text, text, text, date, text, numeric, text, timestamptz),
  private.close_opportunity(uuid, public.opportunity_status, text, uuid, uuid, text[]),
  private.close_opportunity_on_project_change()
from public, anon, authenticated;

revoke all on function
  public.admin_publish_opportunity(uuid, text, text, text, date, text, numeric, text, timestamptz),
  public.admin_update_opportunity(uuid, text, text, text, date, text, numeric, text, timestamptz),
  public.admin_close_opportunity(uuid), public.editor_list_opportunities(),
  public.editor_register_interest(uuid, numeric, text, text), public.editor_withdraw_interest(uuid),
  public.admin_list_interests(uuid), public.admin_get_opportunity(uuid),
  public.admin_select_editor(uuid, numeric, text, text)
from public, anon, authenticated;
grant execute on function
  public.admin_publish_opportunity(uuid, text, text, text, date, text, numeric, text, timestamptz),
  public.admin_update_opportunity(uuid, text, text, text, date, text, numeric, text, timestamptz),
  public.admin_close_opportunity(uuid), public.editor_list_opportunities(),
  public.editor_register_interest(uuid, numeric, text, text), public.editor_withdraw_interest(uuid),
  public.admin_list_interests(uuid), public.admin_get_opportunity(uuid),
  public.admin_select_editor(uuid, numeric, text, text)
to anon, authenticated;
