-- Client area, phase C2a: a signed-in client starts a new project. Spec:
-- docs/superpowers/specs/2026-11-17-client-area-design.md ("Submit a project"), decisions log
-- "Client area" (2026-11-17).
--
--   * A client submission is a LEAD: client_submit_project creates a client_inquiries row exactly
--     like the public form does, never a project. Only an admin converts it (admin_convert_inquiry).
--   * client_inquiries.client_id (nullable) links such a lead to the submitting client. It is set
--     only by client_submit_project; it changes afterwards only when that client is merged into
--     another (it then follows the merge, like the client's users and projects do).
--   * Contact details come from the caller's own account and client record, never from input.
--   * Abuse limits: 10 submissions per client per 24 hours (ES409), plus the public form's input
--     limits (required fields, active service type and budget option, at most 10 https links). The
--     app keeps the public form's honeypot. The per-IP and global caps of the anonymous form do not
--     apply: the caller is an authenticated, admin-invited client.
--   * client_list_requests returns client-safe fields only (what the client wrote, the submitted
--     date, a mapped status and the project id once that project is visible under the C1 rules):
--     never the raw status, notes, admin identities, contact details or other clients' rows.
--   * The admin notification is the existing one: the insert writes 'inquiry.submitted' through
--     the inquiry audit trigger, and the activity-log trigger notifies admins ('inquiry_new').
--   * admin_convert_inquiry converts a client-linked lead for THAT client (the link is carried to
--     project_internal.client_id); choosing a different client is refused.
--   * Audit rows hold ids and field names only.

-- ---------------------------------------------------------------------------
-- Link a lead to its client
-- ---------------------------------------------------------------------------
alter table public.client_inquiries
  add column client_id uuid references public.clients (id) on delete restrict;
comment on column public.client_inquiries.client_id is
  'Set only by client_submit_project (a lead from a signed-in client). Null for public-form inquiries.';
create index client_inquiries_client_idx on public.client_inquiries (client_id, submitted_at desc)
  where client_id is not null;

-- client_id is fixed once written, except to follow a merge of that client.
create function private.client_inquiries_client_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.client_id is distinct from old.client_id
     and (old.client_id is null or new.client_id is null
          or new.client_id is distinct from (select c.merged_into_id from public.clients c where c.id = old.client_id)) then
    raise exception 'The client of a submitted request cannot be changed.' using errcode = 'ES409';
  end if;
  return new;
end;
$$;

create trigger client_inquiries_client_guard
  before update of client_id on public.client_inquiries
  for each row execute function private.client_inquiries_client_guard();

-- Merging clients moves the source client's requests to the kept client (its users move too).
create function private.move_client_inquiries_on_merge()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_moved int;
begin
  update public.client_inquiries set client_id = new.merged_into_id where client_id = new.id;
  get diagnostics v_moved = row_count;
  if v_moved > 0 then
    insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
    values ((select auth.uid()), 'client_inquiry.moved_on_merge', 'client', new.id::text,
      jsonb_build_object('to_client_id', new.merged_into_id, 'count', v_moved));
  end if;
  return new;
end;
$$;

create trigger clients_move_client_inquiries_on_merge
  after update of merged_into_id on public.clients
  for each row when (old.merged_into_id is null and new.merged_into_id is not null)
  execute function private.move_client_inquiries_on_merge();

-- ---------------------------------------------------------------------------
-- Audit: the existing inquiry audit row also records the client id of a client-account lead.
-- Unchanged otherwise from 20261111140306_phase3_public_inquiries (same actions, same details for
-- public-form inquiries, so the 'inquiry.submitted' -> inquiry_new notification still fires).
-- ---------------------------------------------------------------------------
create or replace function private.audit_client_inquiries()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or old.status is distinct from new.status then
    insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
    values (
      -- Public form: the caller may be anonymous or carry a stale token for a deleted account.
      -- Record an actor only if that profile exists, so a submission can never fail on it.
      (select p.id from public.profiles p where p.id = (select auth.uid())),
      case when tg_op = 'INSERT' then 'inquiry.submitted' else 'inquiry.' || new.status::text end,
      'client_inquiry',
      new.id::text,
      jsonb_build_object('from', case when tg_op = 'INSERT' then null else old.status end,
                         'to', new.status)
        || case when new.client_id is not null
                then jsonb_build_object('client_id', new.client_id) else '{}'::jsonb end
    );
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Pure mapping: inquiry status -> client-facing request status key (labels live in the app,
-- src/features/client-area/constants.ts). Spam is never revealed: it reads "not taken forward".
-- ---------------------------------------------------------------------------
create function private.client_request_status_key(p_status public.inquiry_status)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select case p_status::text
    when 'new' then 'received'
    when 'reviewing' then 'in_review'
    when 'contacted' then 'in_review'
    when 'in_discussion' then 'in_review'
    when 'converted' then 'accepted'
    when 'declined' then 'not_taken_forward'
    when 'closed' then 'not_taken_forward'
    when 'spam' then 'not_taken_forward'
  end;
$$;

-- ---------------------------------------------------------------------------
-- client_submit_project: a lead from the caller's client. Returns the new request's id.
-- ---------------------------------------------------------------------------
create function public.client_submit_project(
  p_service_type text,
  p_description text,
  p_expected_deliverables text,
  p_budget_range_id uuid,
  p_expected_deadline date,
  p_client_notes text,
  p_links jsonb,
  p_privacy_notice_version text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
  v_client_id uuid := private.require_client();
  v_client public.clients%rowtype;
  v_profile public.profiles%rowtype;
  v_service public.service_types%rowtype;
  v_budget public.budget_ranges%rowtype;
  v_id uuid;
  v_link jsonb;
begin
  -- Serialise submissions of one client so the daily limit cannot be raced past. FOR NO KEY
  -- UPDATE conflicts with itself (and with a merge or archive, which update the row) but not with
  -- the FOR KEY SHARE locks that inserts referencing this client take, so other work on the
  -- client (projects, invitations) is not blocked.
  select * into v_client from public.clients c where c.id = v_client_id for no key update;
  -- require_client() read the membership before this lock: an archive or merge that committed in
  -- between is seen here (the row lock waits for it and returns the latest version), so re-check.
  if v_client.id is null or v_client.archived_at is not null or v_client.merged_into_id is not null then
    raise exception 'Your client account changed just now. Please reload the page and try again.'
      using errcode = 'ES409';
  end if;
  select * into v_profile from public.profiles p where p.id = v_uid;
  if v_profile.id is null or nullif(btrim(v_profile.email), '') is null then
    raise exception 'Client access is required.' using errcode = 'ES403';
  end if;

  if nullif(trim(p_description), '') is null then
    raise exception 'Please describe the project.' using errcode = 'ES422';
  end if;
  if nullif(trim(p_privacy_notice_version), '') is null then
    raise exception 'Please confirm you have read the privacy notice.' using errcode = 'ES422';
  end if;

  select * into v_service from public.service_types where code = p_service_type and active;
  if v_service.code is null then
    raise exception 'Please choose a type of service.' using errcode = 'ES422';
  end if;

  if p_budget_range_id is not null then
    select * into v_budget from public.budget_ranges where id = p_budget_range_id and active;
    if v_budget.id is null then
      raise exception 'Please choose a budget option.' using errcode = 'ES422';
    end if;
  end if;

  if p_links is not null and jsonb_typeof(p_links) <> 'array' then
    raise exception 'Invalid reference links.' using errcode = 'ES422';
  end if;
  if jsonb_array_length(coalesce(p_links, '[]'::jsonb)) > 10 then
    raise exception 'You can add up to 10 reference links.' using errcode = 'ES422';
  end if;
  if exists (select 1 from jsonb_array_elements(coalesce(p_links, '[]'::jsonb)) l
             where jsonb_typeof(l) <> 'object') then
    raise exception 'Invalid reference links.' using errcode = 'ES422';
  end if;

  if (select count(*) from public.client_inquiries i
      where i.client_id = v_client_id and i.submitted_at > now() - interval '24 hours') >= 10 then
    raise exception 'You have sent several project requests today. Please wait a while, or contact the studio directly.'
      using errcode = 'ES409';
  end if;

  -- Contact details: the caller's own account and client record, never the input.
  insert into public.client_inquiries (
    contact_name, company, email, phone, service_type_code, service_type_label, description,
    expected_deliverables, budget_range_id, budget_label, budget_currency, expected_deadline,
    client_notes, privacy_notice_version, client_id)
  values (
    coalesce(v_profile.full_name, v_client.name), v_client.company, lower(btrim(v_profile.email)),
    coalesce(v_profile.phone, v_client.phone),
    v_service.code, v_service.label, trim(p_description),
    nullif(trim(p_expected_deliverables), ''),
    v_budget.id, coalesce(v_budget.label, 'Prefer to discuss'), coalesce(v_budget.currency, 'LKR'),
    p_expected_deadline, nullif(trim(p_client_notes), ''), trim(p_privacy_notice_version), v_client_id)
  returning id into v_id;

  for v_link in select * from jsonb_array_elements(coalesce(p_links, '[]'::jsonb)) loop
    insert into public.client_inquiry_links (inquiry_id, url, label)
    values (v_id, trim(v_link ->> 'url'), nullif(trim(v_link ->> 'label'), ''));
  end loop;

  return v_id;
exception
  when check_violation then
    raise exception 'Please check your entries: links must start with https:// and fields must not be too long.'
      using errcode = 'ES422';
end;
$$;

-- ---------------------------------------------------------------------------
-- client_list_requests: the caller's client's submitted requests, client-safe fields only.
-- project_id is set only when the request became a project the client can open (C1 rules: the
-- project belongs to this client, is past draft and is not archived).
-- ---------------------------------------------------------------------------
create function public.client_list_requests()
returns table (
  id uuid,
  service_type_label text,
  description text,
  expected_deadline date,
  submitted_at timestamptz,
  request_status text,
  project_id uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_client uuid := private.require_client();
begin
  return query
  select i.id, i.service_type_label, i.description, i.expected_deadline, i.submitted_at,
    private.client_request_status_key(i.status),
    (select p.id from public.projects p
     join public.project_internal pi on pi.project_id = p.id
     where p.id = i.converted_project_id and pi.client_id = v_client
       and p.archived_at is null and p.status <> 'draft')
  from public.client_inquiries i
  where i.client_id = v_client
  order by i.submitted_at desc
  limit 200;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_convert_inquiry: unchanged from 20261114051655_phase4_clients_and_conversion except
-- step 0 and 3: a lead from a client account is converted for that client (the link is carried
-- to the project; an archived client is ES409 "restore first"), choosing another client for it
-- is refused, the client is locked before the inquiry (merge lock order), and a deadlock becomes
-- ES409 "try again".
-- ---------------------------------------------------------------------------
create or replace function public.admin_convert_inquiry(p_inquiry_id uuid, p_input jsonb)
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
  v_lead_client uuid;
  v_lead_merged uuid;
begin
  if jsonb_typeof(v_input) <> 'object' then
    raise exception 'The project details are not valid.' using errcode = 'ES422';
  end if;

  -- 0. A lead from a client account: lock its client (for share) BEFORE the inquiry. A client
  --    merge locks the clients first and then rewrites the inquiries (trigger), so taking the
  --    locks in the same order avoids a merge/convert deadlock. The client id is read without a
  --    lock first and re-checked under the inquiry lock below.
  v_lead_client := (select i.client_id from public.client_inquiries i where i.id = p_inquiry_id);
  if v_lead_client is not null then
    select c.merged_into_id, c.archived_at into v_lead_merged, v_client_archived
    from public.clients c where c.id = v_lead_client for share;
    if v_lead_merged is not null then
      raise exception 'This client was merged just now. Please reload the page and try again.'
        using errcode = 'ES409';
    end if;
    if v_client_archived is not null then
      raise exception 'This request came from a client that is archived. Restore the client first.'
        using errcode = 'ES409';
    end if;
  end if;

  -- 1. Serialise concurrent conversions of the same inquiry (double clicks, two admins).
  select * into v_inquiry from public.client_inquiries where id = p_inquiry_id for update;
  if v_inquiry.id is not null and v_inquiry.client_id is distinct from v_lead_client then
    raise exception 'This request changed just now. Please reload the page and try again.'
      using errcode = 'ES409';
  end if;

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
    -- 3. Client: the submitting client account's client, or the one given, or the unmerged client
    --    with the same normalised email, or a new one.
    v_client := private.jsonb_uuid(v_input, 'client_id', 'client');
    if v_inquiry.client_id is not null then
      if v_client is not null and v_client <> v_inquiry.client_id then
        raise exception 'This request came from a client account, so it becomes a project for that client.'
          using errcode = 'ES409';
      end if;
      -- Already locked (for share) and checked in step 0.
      v_client := v_inquiry.client_id;
    elsif v_client is not null then
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
exception
  -- Belt and braces: any other lock-order cycle (for example with a concurrent merge of the
  -- client matched by email) surfaces as a user-safe "try again", never a raw error.
  when deadlock_detected then
    raise exception 'Another change to this client happened at the same time. Please try again.'
      using errcode = 'ES409';
end;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges: private helpers reach no API role; public functions are executable by
-- anon and authenticated and authorise in the body (guardrails 000 and 046).
-- ---------------------------------------------------------------------------
revoke all on function
  private.client_inquiries_client_guard(), private.move_client_inquiries_on_merge(),
  private.audit_client_inquiries(),
  private.client_request_status_key(public.inquiry_status)
from public, anon, authenticated, service_role;

revoke all on function
  public.client_submit_project(text, text, text, uuid, date, text, jsonb, text),
  public.client_list_requests(),
  public.admin_convert_inquiry(uuid, jsonb)
from public, anon, authenticated;
grant execute on function
  public.client_submit_project(text, text, text, uuid, date, text, jsonb, text),
  public.client_list_requests(),
  public.admin_convert_inquiry(uuid, jsonb)
to anon, authenticated;
