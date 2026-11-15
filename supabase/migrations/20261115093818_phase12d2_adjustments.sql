-- Phase 12D part 2 (4/5): extra pay offers (compensation adjustments), the revision gate, scope
-- quotes and extra-round client charges. Spec §4.4, §6, calls 5, 6, 8; decisions F, F2 (a, b, d).
-- Lock order: project, then assignment, then the revision request / quote / offer, then payments.
-- Audit rows hold ids, enum names and field names only. Errors: ES401/ES403 from the helpers,
-- ES409 state, ES422 input. Every public function is executable by anon and authenticated and
-- authorises in its body.

-- ---------------------------------------------------------------------------
-- The revision gate (F2 a, b, d): may the editor begin this change request?
--   ok                          nothing to wait for
--   waiting_for_scope_approval  a scope change whose client quote is not accepted yet (checked
--                               first: the scope offer can only be made after acceptance)
--   needs_extra_pay             an extra pay offer must be accepted first (an extra round the admin
--                               marked adjustment_required, or a scope change with an accepted quote)
-- ---------------------------------------------------------------------------
create function private.revision_gate(p_revision_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when r.id is null then 'ok'
    when r.type = 'scope_change' and not exists (
      select 1 from public.scope_change_quotes q
      where q.revision_request_id = r.id and q.status = 'accepted') then 'waiting_for_scope_approval'
    when r.type = 'scope_change' and not exists (
      select 1 from public.compensation_adjustments c
      join public.scope_change_quotes q on q.id = c.scope_quote_id
      where q.revision_request_id = r.id and q.status = 'accepted' and c.status = 'accepted') then 'needs_extra_pay'
    when r.type = 'client_revision' and r.adjustment_required and not exists (
      select 1 from public.compensation_adjustments c
      where c.revision_request_id = r.id and c.status = 'accepted') then 'needs_extra_pay'
    else 'ok'
  end
  from (select 1) one
  left join public.revision_requests r on r.id = p_revision_id;
$$;

-- Revision guard (Phase 8 body, extended): the flag applies to client revisions only (cleared on
-- reclassification), and a request cannot be acknowledged, started or resubmitted while the gate
-- says wait. Enforced here so every path (acknowledge, start, submit) is covered.
create or replace function private.guard_revision_requests()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gate text;
begin
  if tg_op = 'DELETE' then
    raise exception 'This history cannot be deleted.' using errcode = 'ES409';
  end if;
  if (new.id, new.project_id, new.assignment_id, new.submission_id, new.created_at)
     is distinct from (old.id, old.project_id, old.assignment_id, old.submission_id, old.created_at)
     or (new.created_by is distinct from old.created_by and new.created_by is not null) then
    raise exception 'This part of a revision request cannot change.' using errcode = 'ES409';
  end if;
  if new.status is distinct from old.status and not private.revision_transition_allowed(old.status, new.status) then
    raise exception 'This change request cannot move from % to %.',
      replace(old.status::text, '_', ' '), replace(new.status::text, '_', ' ') using errcode = 'ES409';
  end if;
  -- A begun request cannot become a scope change: that would skip the quote and extra pay gate.
  if new.type = 'scope_change' and old.type <> 'scope_change' and old.status in ('acknowledged', 'in_progress') then
    raise exception 'This change request has already begun, so it cannot become a scope change. Raise a new change request instead.'
      using errcode = 'ES409';
  end if;
  if new.type <> 'client_revision' then
    new.adjustment_required := false;
  end if;
  if old.status = 'requested' and new.status in ('acknowledged', 'in_progress', 'resubmitted') then
    v_gate := private.revision_gate(new.id);
    if v_gate = 'needs_extra_pay' then
      raise exception 'This change needs extra pay agreed first. Accept the extra pay offer before you begin.'
        using errcode = 'ES409';
    elsif v_gate = 'waiting_for_scope_approval' then
      raise exception 'This scope change is not approved yet. Please wait before you begin.' using errcode = 'ES409';
    end if;
  end if;
  return new;
end;
$$;

-- Locks the request's project and assignment (in that order), then the request.
create function private.lock_revision_request(p_revision_id uuid)
returns public.revision_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_project uuid;
  v_assignment uuid;
  r public.revision_requests;
begin
  select project_id, assignment_id into v_project, v_assignment from public.revision_requests where id = p_revision_id;
  if v_project is null then
    raise exception 'Change request not found.' using errcode = 'ES422';
  end if;
  perform 1 from public.projects where id = v_project for update;
  perform 1 from public.assignments where id = v_assignment for update;
  select * into r from public.revision_requests where id = p_revision_id for update;
  return r;
end;
$$;

-- Amounts in whole cents, above 0.
create function private.require_money(p_amount numeric, p_label text)
returns numeric
language plpgsql
immutable
security definer
set search_path = ''
as $$
begin
  if p_amount is null or p_amount <= 0 or p_amount <> round(p_amount, 2) or p_amount >= 10000000000 then
    raise exception 'Please enter the % as an amount above 0, in whole cents.', p_label using errcode = 'ES422';
  end if;
  return p_amount;
end;
$$;

-- A client due date entered by the admin (call 5: no default); today or later (business timezone).
create function private.require_client_due_date(p_due_date date)
returns date
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_due_date is null then
    raise exception 'Please enter the client due date.' using errcode = 'ES422';
  end if;
  if p_due_date < private.business_date(now()) then
    raise exception 'The client due date cannot be in the past.' using errcode = 'ES422';
  end if;
  return p_due_date;
end;
$$;

-- Inserts an extra_work client milestone, invoiced now with the admin's due date.
create function private.add_extra_work_milestone(p_project_id uuid, p_amount numeric, p_currency char(3),
  p_due_date date, p_quote_id uuid, p_revision_id uuid, p_admin uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_terms uuid;
  v_seq int;
  v_id uuid;
begin
  select id into v_terms from public.project_terms where project_id = p_project_id and status = 'agreed';
  if v_terms is null then
    raise exception 'Agree the project terms before charging the client.' using errcode = 'ES409';
  end if;
  perform 1 from public.client_milestones where project_id = p_project_id and voided_at is null for update;
  v_seq := coalesce((select max(seq) from public.client_milestones where project_id = p_project_id), 0) + 1;
  if v_seq > 100 then
    raise exception 'This project has too many client milestones.' using errcode = 'ES409';
  end if;
  insert into public.client_milestones (project_id, terms_id, seq, kind, amount, currency, scope_quote_id,
    revision_request_id, created_by)
  values (p_project_id, v_terms, v_seq, 'extra_work', p_amount, p_currency, p_quote_id, p_revision_id, p_admin)
  returning id into v_id;
  update public.client_milestones set invoice_issued_at = now(), due_date = p_due_date where id = v_id;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_set_revision_adjustment_required: the admin marks an open client revision as needing extra
-- editor pay before it begins (F2 a), or clears the mark (e.g. after a declined offer, when the
-- client drops the extra work). Setting it is allowed only before the editor has begun.
-- ---------------------------------------------------------------------------
create function public.admin_set_revision_adjustment_required(p_revision_id uuid, p_required boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  r public.revision_requests;
begin
  if p_required is null then
    raise exception 'Choose whether extra pay is required.' using errcode = 'ES422';
  end if;
  r := private.lock_revision_request(p_revision_id);
  if r.type <> 'client_revision' then
    raise exception 'Only a client revision can require extra pay here. A scope change always needs its own offer.'
      using errcode = 'ES409';
  end if;
  if p_required and r.status not in ('requested', 'disputed') then
    raise exception 'The editor has already begun this change request.' using errcode = 'ES409';
  end if;
  if not p_required and r.status not in ('requested', 'acknowledged', 'in_progress', 'disputed') then
    raise exception 'This change request is closed.' using errcode = 'ES409';
  end if;
  if r.adjustment_required = p_required then
    return;
  end if;
  update public.revision_requests set adjustment_required = p_required where id = r.id;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'revision_request.adjustment_required', 'revision_request', r.id::text,
    jsonb_build_object('revision_request_id', r.id, 'assignment_id', r.assignment_id, 'project_id', r.project_id,
      'to', p_required));
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_offer_adjustment: offers extra editor pay (F2 d). extra_round needs an open client
-- revision marked adjustment_required; scope_change needs an accepted quote on an open scope-change
-- request; cancellation needs a settled cancellation on the assignment. The currency is the
-- assignment's agreed currency (no conversion). Notifies the editor. Returns the offer id.
-- ---------------------------------------------------------------------------
create function public.admin_offer_adjustment(p_assignment_id uuid, p_kind text, p_amount numeric,
  p_revision_request_id uuid default null, p_scope_quote_id uuid default null, p_note text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v public.assignments;
  v_project public.projects;
  v_kind public.adjustment_kind;
  v_note text := private.clean_text(p_note, 1000, 'note');
  r public.revision_requests;
  q public.scope_change_quotes;
  v_id uuid;
begin
  if p_kind is null or p_kind not in ('extra_round', 'scope_change', 'cancellation') then
    raise exception 'Choose extra round, scope change or cancellation.' using errcode = 'ES422';
  end if;
  v_kind := p_kind::public.adjustment_kind;
  perform private.require_money(p_amount, 'extra pay');
  if (v_kind = 'extra_round') <> (p_revision_request_id is not null)
     or (v_kind = 'scope_change') <> (p_scope_quote_id is not null) then
    raise exception 'Choose the change request or scope quote this extra pay is for.' using errcode = 'ES422';
  end if;

  v := private.lock_assignment(p_assignment_id);
  select * into v_project from public.projects where id = v.project_id;
  if v_project.archived_at is not null then
    raise exception 'This project is archived. Restore it first.' using errcode = 'ES409';
  end if;

  if v_kind = 'cancellation' then
    if v.status <> 'withdrawn' or v_project.status <> 'cancelled'
       or not exists (select 1 from public.cancellation_settlements s where s.assignment_id = v.id) then
      raise exception 'Extra cancellation pay can be offered only after the cancellation is settled.'
        using errcode = 'ES409';
    end if;
  else
    if v.status <> 'in_progress' then
      raise exception 'Extra pay can be offered only while the editor is working on the project.' using errcode = 'ES409';
    end if;
    if v_kind = 'extra_round' then
      select * into r from public.revision_requests where id = p_revision_request_id for update;
    else
      select * into q from public.scope_change_quotes where id = p_scope_quote_id for update;
      if q.id is null or q.project_id <> v.project_id then
        raise exception 'Scope quote not found.' using errcode = 'ES422';
      end if;
      if q.status <> 'accepted' then
        raise exception 'Record the client''s acceptance of the scope quote before offering extra pay.'
          using errcode = 'ES409';
      end if;
      select * into r from public.revision_requests where id = q.revision_request_id for update;
    end if;
    if r.id is null or r.assignment_id <> v.id then
      raise exception 'Change request not found.' using errcode = 'ES422';
    end if;
    if r.status not in ('requested', 'disputed') then
      raise exception 'Extra pay must be agreed before the change begins; this one has already begun or closed.'
        using errcode = 'ES409';
    end if;
    if v_kind = 'extra_round' and (r.type <> 'client_revision' or not r.adjustment_required) then
      raise exception 'Mark this client revision as needing extra pay first.' using errcode = 'ES409';
    end if;
  end if;

  if v.agreed_currency is null then
    raise exception 'This assignment has no agreed currency.' using errcode = 'ES409';
  end if;
  begin
    insert into public.compensation_adjustments (assignment_id, project_id, editor_id, kind, amount, currency,
      revision_request_id, scope_quote_id, note, offered_by)
    values (v.id, v.project_id, v.editor_id, v_kind, p_amount, v.agreed_currency,
      case when v_kind = 'extra_round' then r.id end, q.id, v_note, v_admin)
    returning id into v_id;
  exception
    when unique_violation then
      raise exception 'There is already an open or accepted extra pay offer for this.' using errcode = 'ES409';
  end;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'adjustment.offered', 'adjustment', v_id::text,
    jsonb_build_object('adjustment_id', v_id, 'assignment_id', v.id, 'project_id', v.project_id, 'kind', v_kind));
  perform private.notify(array[v.editor_id], 'adjustment_offered', 'project', v.project_id,
    'Extra pay offered',
    format('Lenscape offered you extra pay on "%s". Review it on the project page and accept or decline.',
      v_project.title));
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_withdraw_adjustment: withdraws an offer the editor has not answered.
-- ---------------------------------------------------------------------------
create function public.admin_withdraw_adjustment(p_adjustment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_assignment uuid;
  c public.compensation_adjustments;
begin
  select assignment_id into v_assignment from public.compensation_adjustments where id = p_adjustment_id;
  if v_assignment is null then
    raise exception 'Extra pay offer not found.' using errcode = 'ES422';
  end if;
  perform private.lock_assignment(v_assignment);
  select * into c from public.compensation_adjustments where id = p_adjustment_id for update;
  if c.status <> 'offered' then
    raise exception 'Only an unanswered offer can be withdrawn.' using errcode = 'ES409';
  end if;
  update public.compensation_adjustments set status = 'withdrawn', withdrawn_by = v_admin, withdrawn_at = now()
  where id = c.id;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'adjustment.withdrawn', 'adjustment', c.id::text,
    jsonb_build_object('adjustment_id', c.id, 'assignment_id', c.assignment_id, 'project_id', c.project_id,
      'kind', c.kind));
end;
$$;

-- ---------------------------------------------------------------------------
-- editor_respond_adjustment: the editor accepts or declines their own open offer. Accepting
-- creates its own payments row (payable_reason adjustment_accepted, payable now, due editor pay
-- days later in the business timezone); the agreed amount is never edited. Notifies the admins.
-- ---------------------------------------------------------------------------
create function public.editor_respond_adjustment(p_adjustment_id uuid, p_response text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_editor();
  v_assignment uuid;
  v public.assignments;
  c public.compensation_adjustments;
  r public.revision_requests;
  v_open boolean;
begin
  if p_response is null or p_response not in ('accept', 'decline') then
    raise exception 'Choose accept or decline.' using errcode = 'ES422';
  end if;
  select assignment_id into v_assignment from public.compensation_adjustments
  where id = p_adjustment_id and editor_id = v_uid;
  if v_assignment is null then
    raise exception 'Extra pay offer not found.' using errcode = 'ES422';
  end if;
  v := private.lock_assignment(v_assignment);
  select * into c from public.compensation_adjustments where id = p_adjustment_id for update;
  if c.status <> 'offered' then
    raise exception 'This offer is no longer open.' using errcode = 'ES409';
  end if;
  if c.kind = 'cancellation' then
    v_open := v.status = 'withdrawn';
  else
    select rr.* into r from public.revision_requests rr
    where rr.id = coalesce(c.revision_request_id,
                           (select q.revision_request_id from public.scope_change_quotes q
                            where q.id = c.scope_quote_id and q.status <> 'declined'));
    v_open := v.status = 'in_progress' and r.id is not null and r.status in ('requested', 'disputed');
  end if;
  if not v_open then
    raise exception 'This offer is no longer open.' using errcode = 'ES409';
  end if;

  update public.compensation_adjustments
  set status = case when p_response = 'accept' then 'accepted' else 'declined' end::public.adjustment_status,
      answered_by = v_uid, answered_at = now()
  where id = c.id;

  if p_response = 'accept' then
    insert into public.payments (assignment_id, project_id, editor_id, kind, milestone_seq, adjustment_id, amount,
      currency, status, payable_reason, payable_at, due_date, created_by)
    values (c.assignment_id, c.project_id, c.editor_id, 'assignment', null, c.id, c.amount, c.currency,
      'pending_approval', 'adjustment_accepted', now(),
      private.business_date(now()) + private.editor_pay_days(c.project_id), c.offered_by);
  end if;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_uid, 'adjustment.' || case when p_response = 'accept' then 'accepted' else 'declined' end,
    'adjustment', c.id::text,
    jsonb_build_object('adjustment_id', c.id, 'assignment_id', c.assignment_id, 'project_id', c.project_id,
      'kind', c.kind));
  perform private.notify(private.active_admin_ids(), 'adjustment_answered', 'project', c.project_id,
    case when p_response = 'accept' then 'Extra pay accepted' else 'Extra pay declined' end,
    format('The editor %s the extra pay offer on "%s".',
      case when p_response = 'accept' then 'accepted' else 'declined' end, private.project_title(c.project_id)));
end;
$$;

-- ---------------------------------------------------------------------------
-- editor_list_adjustments: the editor's own offers (editor pay only; no admin ids, no client
-- money, no quote). Optionally one project.
-- ---------------------------------------------------------------------------
create function public.editor_list_adjustments(p_project_id uuid default null)
returns table (id uuid, assignment_id uuid, project_id uuid, project_title text, kind public.adjustment_kind,
  amount numeric, currency char(3), revision_request_id uuid, status public.adjustment_status, note text,
  offered_at timestamptz, answered_at timestamptz, withdrawn_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_editor();
begin
  return query
  select c.id, c.assignment_id, c.project_id, p.title, c.kind, c.amount, c.currency,
    coalesce(c.revision_request_id, q.revision_request_id), c.status, c.note, c.offered_at, c.answered_at,
    c.withdrawn_at
  from public.compensation_adjustments c
  join public.projects p on p.id = c.project_id
  left join public.scope_change_quotes q on q.id = c.scope_quote_id
  where c.editor_id = v_uid and (p_project_id is null or c.project_id = p_project_id)
  order by c.offered_at desc, c.id;
end;
$$;

-- editor_revision_gate: the gate code of the editor's own change request (no client facts).
create function public.editor_revision_gate(p_revision_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_editor();
begin
  if not exists (select 1 from public.revision_requests r join public.assignments a on a.id = r.assignment_id
                 where r.id = p_revision_id and a.editor_id = v_uid) then
    raise exception 'Change request not found.' using errcode = 'ES422';
  end if;
  return private.revision_gate(p_revision_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Scope quotes (admin-only client money). drafted -> sent -> accepted | declined; the client's
-- answer is recorded by an admin. Acceptance creates an extra_work client milestone invoiced now
-- with the admin's due date (call 5: no default).
-- ---------------------------------------------------------------------------
create function public.admin_create_scope_quote(p_revision_request_id uuid, p_description text, p_amount numeric,
  p_currency text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_description text := private.clean_text(p_description, 4000, 'description');
  v_currency text := upper(trim(coalesce(p_currency, '')));
  r public.revision_requests;
  v_project public.projects;
  v_id uuid;
begin
  if v_description is null then
    raise exception 'Please describe the scope change for the client.' using errcode = 'ES422';
  end if;
  perform private.require_money(p_amount, 'client quote');
  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Please enter a three-letter currency code.' using errcode = 'ES422';
  end if;
  r := private.lock_revision_request(p_revision_request_id);
  select * into v_project from public.projects where id = r.project_id;
  if v_project.status = 'cancelled' or v_project.archived_at is not null then
    raise exception 'This project is cancelled or archived and cannot be edited.' using errcode = 'ES409';
  end if;
  if r.type <> 'scope_change' then
    raise exception 'A scope quote is for a scope-change request.' using errcode = 'ES409';
  end if;
  if r.status not in ('requested', 'disputed') then
    raise exception 'This scope change has already begun or closed.' using errcode = 'ES409';
  end if;
  begin
    insert into public.scope_change_quotes (project_id, revision_request_id, description, amount, currency, created_by)
    values (r.project_id, r.id, v_description, p_amount, v_currency, v_admin)
    returning id into v_id;
  exception
    when unique_violation then
      raise exception 'This scope change already has a quote.' using errcode = 'ES409';
  end;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'scope_quote.created', 'project', r.project_id::text,
    jsonb_build_object('project_id', r.project_id, 'quote_id', v_id, 'revision_request_id', r.id));
  return v_id;
end;
$$;

create function private.lock_scope_quote(p_quote_id uuid)
returns public.scope_change_quotes
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_revision uuid;
  q public.scope_change_quotes;
  v_project public.projects;
begin
  select revision_request_id into v_revision from public.scope_change_quotes where id = p_quote_id;
  if v_revision is null then
    raise exception 'Scope quote not found.' using errcode = 'ES422';
  end if;
  perform private.lock_revision_request(v_revision);
  select * into q from public.scope_change_quotes where id = p_quote_id for update;
  select * into v_project from public.projects where id = q.project_id;
  if v_project.status = 'cancelled' or v_project.archived_at is not null then
    raise exception 'This project is cancelled or archived and cannot be edited.' using errcode = 'ES409';
  end if;
  return q;
end;
$$;

create function public.admin_send_scope_quote(p_quote_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  q public.scope_change_quotes := private.lock_scope_quote(p_quote_id);
begin
  if q.status <> 'drafted' then
    raise exception 'This scope quote was already sent.' using errcode = 'ES409';
  end if;
  update public.scope_change_quotes set status = 'sent', sent_at = now() where id = q.id;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'scope_quote.sent', 'project', q.project_id::text,
    jsonb_build_object('project_id', q.project_id, 'quote_id', q.id));
end;
$$;

create function public.admin_record_scope_quote_answer(p_quote_id uuid, p_accepted boolean, p_due_date date default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  q public.scope_change_quotes;
  v_milestone uuid;
begin
  if p_accepted is null then
    raise exception 'Choose whether the client accepted the quote.' using errcode = 'ES422';
  end if;
  if p_accepted then
    perform private.require_client_due_date(p_due_date);
  end if;
  q := private.lock_scope_quote(p_quote_id);
  if q.status <> 'sent' then
    raise exception 'Send the scope quote before recording the client''s answer.' using errcode = 'ES409';
  end if;
  update public.scope_change_quotes
  set status = case when p_accepted then 'accepted' else 'declined' end::public.scope_quote_status,
      answered_at = now(), answered_by = v_admin
  where id = q.id;
  if p_accepted then
    v_milestone := private.add_extra_work_milestone(q.project_id, q.amount, q.currency, p_due_date, q.id, null, v_admin);
  end if;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, case when p_accepted then 'scope_quote.accepted' else 'scope_quote.declined' end,
    'project', q.project_id::text,
    jsonb_build_object('project_id', q.project_id, 'quote_id', q.id, 'milestone_id', v_milestone));
  return v_milestone;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_charge_extra_round: the client charge for a chargeable round (beyond the included rounds)
-- from the agreed terms' extra_round_charge, as an extra_work milestone with the admin's due date
-- (call 5). Once per round.
-- ---------------------------------------------------------------------------
create function public.admin_charge_extra_round(p_revision_request_id uuid, p_due_date date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  r public.revision_requests;
  t public.project_terms;
  v_milestone uuid;
begin
  perform private.require_client_due_date(p_due_date);
  r := private.lock_revision_request(p_revision_request_id);
  if exists (select 1 from public.projects p where p.id = r.project_id
             and (p.status = 'cancelled' or p.archived_at is not null)) then
    raise exception 'This project is cancelled or archived and cannot be edited.' using errcode = 'ES409';
  end if;
  if r.type <> 'client_revision' or not r.beyond_allowance then
    raise exception 'Only a client revision beyond the included rounds is charged.' using errcode = 'ES409';
  end if;
  select * into t from public.project_terms where project_id = r.project_id and status = 'agreed';
  if t.extra_round_charge is null or t.charge_currency is null then
    raise exception 'Set the extra round charge in the project terms first.' using errcode = 'ES409';
  end if;
  if exists (select 1 from public.client_milestones where revision_request_id = r.id and voided_at is null) then
    raise exception 'This round was already charged.' using errcode = 'ES409';
  end if;
  v_milestone := private.add_extra_work_milestone(r.project_id, t.extra_round_charge, t.charge_currency, p_due_date,
    null, r.id, v_admin);
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'client_milestone.extra_round_charged', 'project', r.project_id::text,
    jsonb_build_object('project_id', r.project_id, 'milestone_id', v_milestone, 'revision_request_id', r.id));
  return v_milestone;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_reverse_payment (12D part 1 body): the reversal and any re-opened row keep the line
-- (milestone, extra pay offer or settlement); the open-row check is per line.
-- ---------------------------------------------------------------------------
create or replace function public.admin_reverse_payment(p_payment_id uuid, p_reason text, p_reopen boolean)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v public.payments;
  v_reason text;
  v_id uuid;
  v_project_id uuid;
  v_assignment_id uuid;
begin
  select project_id, assignment_id into v_project_id, v_assignment_id from public.payments where id = p_payment_id;
  if v_project_id is null then
    raise exception 'Payment not found.' using errcode = 'ES422';
  end if;
  perform 1 from public.projects where id = v_project_id for update;
  perform 1 from public.assignments where id = v_assignment_id for update;
  v := private.lock_payment(p_payment_id);
  if v.kind <> 'assignment' or v.status <> 'paid' then
    raise exception 'Only a paid payment can be reversed.' using errcode = 'ES409';
  end if;
  if exists (select 1 from public.payments where reverses_payment_id = v.id) then
    raise exception 'This payment has already been reversed.' using errcode = 'ES409';
  end if;
  v_reason := private.clean_text(p_reason, 500, 'reason');
  if v_reason is null then
    raise exception 'Please give a reason for the reversal.' using errcode = 'ES422';
  end if;
  if p_reopen is null then
    raise exception 'Choose whether to re-open the payment.' using errcode = 'ES422';
  end if;
  if p_reopen and exists (select 1 from public.assignments
                          where id = v.assignment_id
                            and status in ('reassigned', 'withdrawn', 'declined', 'not_selected')) then
    raise exception 'This assignment has ended, so the payment cannot be re-opened.' using errcode = 'ES409';
  end if;
  if p_reopen and exists (select 1 from public.payments
                          where assignment_id = v.assignment_id and kind = 'assignment'
                            and status not in ('paid', 'cancelled') and split_from_payment_id is null
                            and (milestone_seq = v.milestone_seq or adjustment_id = v.adjustment_id
                                 or settlement_id = v.settlement_id)) then
    raise exception 'This milestone already has an open payment.' using errcode = 'ES409';
  end if;

  begin
    insert into public.payments (assignment_id, project_id, editor_id, kind, milestone_seq, adjustment_id, settlement_id,
      amount, currency, status, reverses_payment_id, reversal_reason, marked_paid_by, marked_paid_at, created_by)
    values (v.assignment_id, v.project_id, v.editor_id, 'reversal', v.milestone_seq, v.adjustment_id, v.settlement_id,
      -v.amount, v.currency, 'paid', v.id, v_reason, v_admin, now(), v_admin)
    returning id into v_id;
    if p_reopen then
      insert into public.payments (assignment_id, project_id, editor_id, kind, milestone_seq, adjustment_id,
        settlement_id, amount, currency, status, payable_reason, payable_at, created_by)
      values (v.assignment_id, v.project_id, v.editor_id, 'assignment', v.milestone_seq, v.adjustment_id,
        v.settlement_id, v.amount, v.currency, 'pending_approval', v.payable_reason,
        case when v.payable_reason is not null then now() end, v_admin);
    end if;
  exception
    when unique_violation then
      raise exception 'This payment changed at the same time. Please reload and try again.' using errcode = 'ES409';
    when check_violation then
      raise exception 'This reversal is not valid.' using errcode = 'ES422';
  end;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- editor_list_payments (return type changes: dropped and recreated; only the app calls it). Adds
-- line_kind, a fixed label of what the row pays: milestone, extra_round, scope_change,
-- cancellation_extra (accepted offers), cancellation_settlement (the settlement's shortfall) or
-- cancellation_reconciliation (a settlement reversing an overpayment). Never reasons, the
-- payable reason, admin ids or client money (KB9a-5).
-- ---------------------------------------------------------------------------
drop function public.editor_list_payments();

create function public.editor_list_payments()
returns table (id uuid, project_id uuid, project_title text, kind public.payment_kind, milestone_seq smallint,
  line_kind text, amount numeric, currency char(3), status public.payment_status,
  hold_label public.payment_hold_label, waiting_on_client boolean, reverses_payment_id uuid,
  split_from_payment_id uuid, due_date date, transfer_date date, transaction_reference text,
  approved_at timestamptz, marked_paid_at timestamptz, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_editor();
begin
  return query
  select p.id, p.project_id, pr.title, p.kind, p.milestone_seq,
    case
      when p.settlement_id is not null and p.milestone_seq is null and p.adjustment_id is null
        then 'cancellation_settlement'
      when p.settlement_id is not null then 'cancellation_reconciliation'
      when c.kind = 'cancellation' then 'cancellation_extra'
      when c.kind is not null then c.kind::text
      else 'milestone'
    end,
    p.amount, p.currency, p.status,
    (case
       when p.status = 'on_hold' and p.split_from_payment_id is null and a.status in ('reassigned', 'withdrawn')
         then 'assignment_ended'
       when p.status = 'on_hold' then 'under_review'
       when p.status = 'not_due' and p.waiting_on_client then 'waiting_for_client_payment'
     end)::public.payment_hold_label,
    p.waiting_on_client, p.reverses_payment_id, p.split_from_payment_id, p.due_date,
    p.transfer_date, p.transaction_reference, p.approved_at, p.marked_paid_at, p.created_at
  from public.payments p
  join public.projects pr on pr.id = p.project_id
  join public.assignments a on a.id = p.assignment_id
  left join public.compensation_adjustments c on c.id = p.adjustment_id
  where p.editor_id = v_uid
  order by p.created_at desc, p.milestone_seq, p.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges
-- ---------------------------------------------------------------------------
revoke all on function
  private.revision_gate(uuid), private.lock_revision_request(uuid), private.require_money(numeric, text),
  private.require_client_due_date(date),
  private.add_extra_work_milestone(uuid, numeric, char, date, uuid, uuid, uuid),
  private.lock_scope_quote(uuid)
from public, anon, authenticated;

revoke all on function
  public.admin_set_revision_adjustment_required(uuid, boolean),
  public.admin_offer_adjustment(uuid, text, numeric, uuid, uuid, text),
  public.admin_withdraw_adjustment(uuid),
  public.editor_respond_adjustment(uuid, text),
  public.editor_list_adjustments(uuid),
  public.editor_revision_gate(uuid),
  public.admin_create_scope_quote(uuid, text, numeric, text),
  public.admin_send_scope_quote(uuid),
  public.admin_record_scope_quote_answer(uuid, boolean, date),
  public.admin_charge_extra_round(uuid, date),
  public.editor_list_payments()
from public, anon, authenticated;
grant execute on function
  public.admin_set_revision_adjustment_required(uuid, boolean),
  public.admin_offer_adjustment(uuid, text, numeric, uuid, uuid, text),
  public.admin_withdraw_adjustment(uuid),
  public.editor_respond_adjustment(uuid, text),
  public.editor_list_adjustments(uuid),
  public.editor_revision_gate(uuid),
  public.admin_create_scope_quote(uuid, text, numeric, text),
  public.admin_send_scope_quote(uuid),
  public.admin_record_scope_quote_answer(uuid, boolean, date),
  public.admin_charge_extra_round(uuid, date),
  public.editor_list_payments()
to anon, authenticated;
