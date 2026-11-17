-- Client area, phase C1. Spec: docs/superpowers/specs/2026-11-17-client-area-design.md (owner
-- approved 2026-11-17, decisions log "Client area").
--
--   * client_users links an auth account to a clients row. Only admins invite or revoke. Several
--     users per client; at most one active membership per account. A client account is never an
--     admin or an editor (guard triggers below), and only an account created by the invitation
--     flow (confirmed email, app_metadata.client_invite = true, which only the service key can
--     set) or a former client user can be linked, so a self-registered sign-up cannot be turned
--     into client access (pre-registration takeover).
--   * client_project_updates: admin-written progress notes; the client sees published ones.
--   * The studio's bank transfer details are an admin setting (app_settings key
--     client_bank_details). No row = hidden. Never pre-filled (the owner supplies them).
--   * Clients get NO table grants. Every client read goes through the client_* functions below,
--     which authorise in the body (active, non-revoked membership of the project's client) and
--     return client-safe projections only: no editor identity, assignment, editor pay, notes,
--     offers, opportunities, asset links, client price or raw internal status.
--   * The client-facing status is derived from projects.status by ONE pure mapping in the
--     database (private.client_status_key), so the raw status never reaches a client session.
--   * Revocation applies at once: every client function re-checks revoked_at on each call. Users
--     of an archived client lose access the same way (private.require_client checks the client).
--   * Clients see only projects past draft, never a deadline (projects.deadline and the confirmed
--     deadlines are editor-facing and may include a buffer; a client-facing date is an open owner
--     item), and a client account can never apply as an editor or hold an editor profile.
--   * Audit rows hold ids and field names only.

-- ---------------------------------------------------------------------------
-- Setting: studio bank transfer details shown to clients (empty = hidden)
-- ---------------------------------------------------------------------------
alter table public.app_settings drop constraint app_settings_key_check;
alter table public.app_settings add constraint app_settings_key_check
  check (key in ('business_timezone', 'payout_details_enabled', 'client_bank_details'));

-- ---------------------------------------------------------------------------
-- client_users
-- ---------------------------------------------------------------------------
create table public.client_users (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  client_id uuid not null references public.clients (id) on delete restrict,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_by uuid references public.profiles (id) on delete set null,
  constraint client_users_revoked_by_chk check (revoked_by is null or revoked_at is not null)
);
comment on table public.client_users is
  'Client accounts (admin-invited). No API grants: read and written only through functions.';
-- One active membership per account; revoked rows stay as history.
create unique index client_users_one_active_key on public.client_users (user_id) where revoked_at is null;
create index client_users_user_idx on public.client_users (user_id);
create index client_users_client_idx on public.client_users (client_id);
create index client_users_created_by_idx on public.client_users (created_by);
create index client_users_revoked_by_idx on public.client_users (revoked_by);

alter table public.client_users enable row level security;
revoke all on public.client_users from anon, authenticated;

-- ---------------------------------------------------------------------------
-- client_project_updates
-- ---------------------------------------------------------------------------
create table public.client_project_updates (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 5000),
  published boolean not null default true,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  withdrawn_at timestamptz,
  withdrawn_by uuid references public.profiles (id) on delete set null,
  constraint client_project_updates_withdrawn_chk check (
    published = (withdrawn_at is null) and (withdrawn_by is null or withdrawn_at is not null))
);
comment on table public.client_project_updates is
  'Admin-written progress updates shown to the project''s client users while published. No API grants.';
create index client_project_updates_project_idx on public.client_project_updates (project_id, created_at desc);
create index client_project_updates_created_by_idx on public.client_project_updates (created_by);
create index client_project_updates_withdrawn_by_idx on public.client_project_updates (withdrawn_by);

alter table public.client_project_updates enable row level security;
revoke all on public.client_project_updates from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Guards (hold for every caller, the table owner included)
-- ---------------------------------------------------------------------------

-- client_users: an admin or editor account can never be linked; identity columns are fixed; a
-- revocation is final (re-inviting creates a new row); the client changes only by a client merge.
create function private.client_users_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Rows are deleted only by the account-deletion cascade (no API role has any grant).
  if tg_op = 'INSERT' then
    if exists (select 1 from public.admin_users a where a.user_id = new.user_id) then
      raise exception 'This email belongs to a studio account and cannot be a client user.' using errcode = 'ES409';
    end if;
    if exists (select 1 from public.editor_profiles e where e.user_id = new.user_id and e.access_status <> 'none')
       or exists (select 1 from public.editor_applications ea where ea.editor_id = new.user_id) then
      raise exception 'This email belongs to an editor or applicant account and cannot be a client user.' using errcode = 'ES409';
    end if;
    return new;
  end if;
  -- created_by/revoked_by may only become null (profile deletion, on delete set null).
  if new.id <> old.id or new.user_id <> old.user_id or new.created_at <> old.created_at
     or (new.created_by is distinct from old.created_by and new.created_by is not null) then
    raise exception 'Client access records cannot be rewritten.' using errcode = 'ES409';
  end if;
  if old.revoked_at is not null and (new.revoked_at is distinct from old.revoked_at
       or new.client_id <> old.client_id
       or (new.revoked_by is distinct from old.revoked_by and new.revoked_by is not null)) then
    raise exception 'This client access was already removed.' using errcode = 'ES409';
  end if;
  return new;
end;
$$;

create trigger client_users_guard
  before insert or update on public.client_users
  for each row execute function private.client_users_guard();

-- An account with active client access cannot become an active editor or an admin.
create function private.refuse_client_as_editor()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.access_status = 'active' and exists (
       select 1 from public.client_users cu where cu.user_id = new.user_id and cu.revoked_at is null) then
    raise exception 'This account has client access and cannot become an editor. Remove its client access first.'
      using errcode = 'ES409';
  end if;
  return new;
end;
$$;

create trigger editor_profiles_refuse_client
  before insert or update of access_status on public.editor_profiles
  for each row execute function private.refuse_client_as_editor();

create function private.refuse_client_as_admin()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.revoked_at is null and exists (
       select 1 from public.client_users cu where cu.user_id = new.user_id and cu.revoked_at is null) then
    raise exception 'This account has client access and cannot become an admin. Remove its client access first.'
      using errcode = 'ES409';
  end if;
  return new;
end;
$$;

create trigger admin_users_refuse_client
  before insert or update on public.admin_users
  for each row execute function private.refuse_client_as_admin();

-- Merging clients (public.admin_merge_clients) moves projects to the kept client; active client
-- users follow, so they keep seeing their projects.
create function private.move_client_users_on_merge()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_moved int;
begin
  update public.client_users set client_id = new.merged_into_id
  where client_id = new.id and revoked_at is null;
  get diagnostics v_moved = row_count;
  if v_moved > 0 then
    insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
    values ((select auth.uid()), 'client_user.moved_on_merge', 'client', new.id::text,
      jsonb_build_object('to_client_id', new.merged_into_id, 'count', v_moved));
  end if;
  return new;
end;
$$;

create trigger clients_move_client_users_on_merge
  after update of merged_into_id on public.clients
  for each row when (old.merged_into_id is null and new.merged_into_id is not null)
  execute function private.move_client_users_on_merge();

-- client_project_updates: the text and project are fixed; the only change is withdrawing a
-- published update (it then stays on record for admins). Never deleted except with its project.
create function private.client_project_updates_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- created_by/withdrawn_by may only become null (profile deletion, on delete set null).
  if new.id <> old.id or new.project_id <> old.project_id or new.body <> old.body
     or new.created_at <> old.created_at
     or (new.created_by is distinct from old.created_by and new.created_by is not null)
     or (not old.published and new.published) then
    raise exception 'A published update cannot be edited. Withdraw it and publish a new one.' using errcode = 'ES409';
  end if;
  -- A withdrawal is final: its time and author never change once set.
  if old.withdrawn_at is not null and (new.withdrawn_at is distinct from old.withdrawn_at
       or (new.withdrawn_by is distinct from old.withdrawn_by and new.withdrawn_by is not null)) then
    raise exception 'This update was already withdrawn.' using errcode = 'ES409';
  end if;
  return new;
end;
$$;

create trigger client_project_updates_guard
  before update on public.client_project_updates
  for each row execute function private.client_project_updates_guard();

-- A client account (active membership) can never apply as an editor: no application row can be
-- created or changed for it (covers submit_editor_application and any later path).
create function private.refuse_client_application()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.client_users cu where cu.user_id = new.editor_id and cu.revoked_at is null) then
    raise exception 'Client accounts cannot apply as editors.' using errcode = 'ES409';
  end if;
  return new;
end;
$$;

create trigger editor_applications_refuse_client
  before insert or update on public.editor_applications
  for each row execute function private.refuse_client_application();

-- save_editor_profile (Phase 2) gains one check: a client account has no editor profile. The rest
-- of the body is unchanged from 20261111133128_phase2_editor_applications.
create or replace function public.save_editor_profile(
  p_full_name text,
  p_phone text,
  p_region text,
  p_experience_years smallint,
  p_experience_summary text,
  p_availability text,
  p_typical_turnaround text,
  p_hardware text,
  p_software_other text,
  p_specialisations text[],
  p_software text[],
  p_links jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
  v_link jsonb;
begin
  if private.is_admin_account() then
    raise exception 'Admin accounts do not have an editor profile.' using errcode = 'ES403';
  end if;
  if exists (select 1 from public.client_users cu where cu.user_id = v_uid and cu.revoked_at is null) then
    raise exception 'Client accounts do not have an editor profile.' using errcode = 'ES403';
  end if;
  if p_links is not null and jsonb_typeof(p_links) <> 'array' then
    raise exception 'Invalid portfolio links.' using errcode = 'ES422';
  end if;
  if jsonb_array_length(coalesce(p_links, '[]'::jsonb)) > 10 then
    raise exception 'You can add up to 10 portfolio links.' using errcode = 'ES422';
  end if;

  update public.profiles
  set full_name = nullif(trim(p_full_name), ''), phone = nullif(trim(p_phone), '')
  where id = v_uid;

  update public.editor_profiles
  set region = nullif(trim(p_region), ''),
      experience_years = p_experience_years,
      experience_summary = nullif(trim(p_experience_summary), ''),
      availability = nullif(trim(p_availability), ''),
      typical_turnaround = nullif(trim(p_typical_turnaround), ''),
      hardware = nullif(trim(p_hardware), ''),
      software_other = nullif(trim(p_software_other), '')
  where user_id = v_uid;

  delete from public.editor_profile_options where editor_id = v_uid;
  insert into public.editor_profile_options (editor_id, kind, code)
    select v_uid, 'specialisation'::public.profile_option_kind, code from unnest(coalesce(p_specialisations, '{}')) as code
    union
    select v_uid, 'software'::public.profile_option_kind, code from unnest(coalesce(p_software, '{}')) as code;

  delete from public.editor_portfolio_links where editor_id = v_uid;
  for v_link in select * from jsonb_array_elements(coalesce(p_links, '[]'::jsonb)) loop
    insert into public.editor_portfolio_links (editor_id, url, label)
    values (v_uid, trim(v_link ->> 'url'), nullif(trim(v_link ->> 'label'), ''));
  end loop;
exception
  when check_violation then
    raise exception 'Please check your entries: links must start with https:// and fields must not be too long.'
      using errcode = 'ES422';
  when foreign_key_violation then
    raise exception 'One of the selected options is not available.' using errcode = 'ES422';
end;
$$;

-- submit_editor_application (Phase 2) gains the same early check (the trigger above is the
-- backstop). The rest of the body is unchanged from 20261111133128_phase2_editor_applications.
create or replace function public.submit_editor_application(p_terms_version text, p_privacy_version text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
  v_app public.editor_applications%rowtype;
  v_missing text[];
begin
  if private.is_admin_account() then
    raise exception 'Admin accounts cannot apply as editors.' using errcode = 'ES403';
  end if;
  if exists (select 1 from public.client_users cu where cu.user_id = v_uid and cu.revoked_at is null) then
    raise exception 'Client accounts cannot apply as editors.' using errcode = 'ES403';
  end if;
  if (select access_status from public.editor_profiles where user_id = v_uid) <> 'none' then
    raise exception 'This account already has editor status.' using errcode = 'ES409';
  end if;
  if coalesce(trim(p_terms_version), '') = '' or coalesce(trim(p_privacy_version), '') = '' then
    raise exception 'Please accept the editor terms and privacy notice.' using errcode = 'ES422';
  end if;

  select * into v_app from public.editor_applications
  where editor_id = v_uid
    and status in ('draft', 'submitted', 'under_review', 'info_requested', 'test_requested')
  for update;

  if found and v_app.status <> 'draft' then
    raise exception 'Your application has already been submitted.' using errcode = 'ES409';
  end if;

  if not found then
    -- Decision M: after a rejection (or withdrawal), only an admin can reopen.
    if exists (select 1 from public.editor_applications where editor_id = v_uid) then
      raise exception 'Your previous application is closed. Please contact Lenscape Studios to reopen it.'
        using errcode = 'ES409';
    end if;
  end if;

  v_missing := private.application_missing_fields(v_uid);
  if cardinality(v_missing) > 0 then
    raise exception 'Please complete: %.', array_to_string(v_missing, ', ') using errcode = 'ES422';
  end if;

  if v_app.id is null then
    insert into public.editor_applications (editor_id, attempt, status)
    values (v_uid, 1, 'draft')
    returning * into v_app;
  end if;

  update public.editor_applications
  set status = 'submitted',
      submitted_at = now(),
      submitted_snapshot = private.application_snapshot(v_uid),
      terms_version = trim(p_terms_version),
      privacy_version = trim(p_privacy_version)
  where id = v_app.id;

  return v_app.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Pure mappings (the single source of truth for what a client is told)
-- ---------------------------------------------------------------------------

-- Project status -> client-facing status key. Labels live in the app
-- (src/features/client-area/constants.ts). Every enum value must map (pgTAP checks it). Draft
-- projects are never shown to clients, so 'received' is only a safe fallback. 'approved' (the
-- studio approved the editor's work; there is no client review step yet) reads 'finalising'.
create function private.client_status_key(p_status public.project_status)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select case p_status::text
    when 'draft' then 'received'
    when 'open' then 'planning'
    when 'assigned' then 'planning'
    when 'in_progress' then 'in_production'
    when 'in_review' then 'in_production'
    when 'revision_requested' then 'revisions_in_progress'
    when 'approved' then 'finalising'
    when 'completed' then 'completed'
    when 'on_hold' then 'on_hold'
    when 'cancelled' then 'cancelled'
  end;
$$;

-- Client milestone -> client-facing payment status key.
create function private.client_payment_status_key(
  p_kind public.client_milestone_kind,
  p_verification public.client_verification_status,
  p_invoice_issued_at timestamptz)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select case
    when p_kind = 'refund' then 'refunded'
    when p_verification = 'verified' then 'paid'
    when p_verification = 'received_unverified' then 'confirming'
    when p_invoice_issued_at is null then 'not_invoiced'
    else 'awaiting_payment'
  end;
$$;

-- ---------------------------------------------------------------------------
-- Caller checks
-- ---------------------------------------------------------------------------

-- The caller's client (active membership), or ES401/ES403.
create function private.require_client()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
  v_client uuid;
begin
  -- An archived client's users lose access (their membership row is kept).
  select cu.client_id into v_client
  from public.client_users cu
  join public.clients c on c.id = cu.client_id
  where cu.user_id = v_uid and cu.revoked_at is null and c.archived_at is null;
  if v_client is null then
    raise exception 'Client access is required.' using errcode = 'ES403';
  end if;
  return v_client;
end;
$$;

-- Client-safe milestone rows of one project (never voided rows, never references or reasons).
create function private.client_milestones_json(p_project_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', m.id,
      'seq', m.seq,
      'kind', m.kind,
      'amount', m.amount,
      'currency', m.currency,
      'due_date', m.due_date,
      'invoice_issued_at', m.invoice_issued_at,
      'received_at', m.received_at,
      'payment_status', private.client_payment_status_key(m.kind, m.verification_status, m.invoice_issued_at))
    order by m.seq), '[]'::jsonb)
  from public.client_milestones m
  where m.project_id = p_project_id and m.voided_at is null;
$$;

-- ---------------------------------------------------------------------------
-- my_client_status: routing read for the signed-in account. 'active', 'revoked' (had access, all
-- removed or the client archived) or null (not a client, or signed out). Reveals nothing about
-- anyone else.
-- ---------------------------------------------------------------------------
create function public.my_client_status()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when (select auth.uid()) is null then null
    when exists (select 1 from public.client_users cu
                 join public.clients c on c.id = cu.client_id
                 where cu.user_id = (select auth.uid()) and cu.revoked_at is null
                   and c.archived_at is null) then 'active'
    when exists (select 1 from public.client_users cu where cu.user_id = (select auth.uid())) then 'revoked'
    else null
  end;
$$;

-- ---------------------------------------------------------------------------
-- Client reads
-- ---------------------------------------------------------------------------

-- The caller's client's projects past draft (draft and archived projects are hidden).
create function public.client_list_projects()
returns table (
  id uuid,
  title text,
  client_status text,
  created_at timestamptz,
  last_update_at timestamptz
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
  select p.id, p.title, private.client_status_key(p.status), p.created_at,
    (select max(u.created_at) from public.client_project_updates u
     where u.project_id = p.id and u.published)
  from public.projects p
  join public.project_internal pi on pi.project_id = p.id
  where pi.client_id = v_client and p.archived_at is null and p.status <> 'draft'
  order by p.created_at desc;
end;
$$;

-- One project of the caller's client, client-safe fields only. Null when the project does not
-- exist, is a draft, is archived or belongs to another client (the same answer, so existence
-- never leaks).
create function public.client_get_project(p_project_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_client uuid := private.require_client();
  v jsonb;
begin
  if p_project_id is null then
    return null;
  end if;
  select jsonb_build_object(
      'id', p.id,
      'title', p.title,
      'client_status', private.client_status_key(p.status),
      'created_at', p.created_at,
      'deliverables', coalesce((
        select jsonb_agg(jsonb_build_object(
            'name', d.name, 'format', d.format, 'resolution', d.resolution,
            'aspect_ratio', d.aspect_ratio, 'duration_seconds', d.duration_seconds)
          order by d.sort_order, d.created_at)
        from public.project_deliverables d where d.project_id = p.id), '[]'::jsonb),
      'updates', coalesce((
        select jsonb_agg(jsonb_build_object('id', u.id, 'body', u.body, 'published_at', u.created_at)
          order by u.created_at desc)
        from public.client_project_updates u where u.project_id = p.id and u.published), '[]'::jsonb),
      'milestones', private.client_milestones_json(p.id))
  into v
  from public.projects p
  join public.project_internal pi on pi.project_id = p.id
  where p.id = p_project_id and pi.client_id = v_client and p.archived_at is null
    and p.status <> 'draft';
  return v;
end;
$$;

-- Payments across the caller's client's projects, plus the studio bank details if configured.
create function public.client_get_payment_info()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_client uuid := private.require_client();
begin
  return jsonb_build_object(
    'bank_details', (select nullif(btrim(s.value #>> '{}'), '') from public.app_settings s
                     where s.key = 'client_bank_details' and jsonb_typeof(s.value) = 'string'),
    'projects', coalesce((
      select jsonb_agg(jsonb_build_object(
          'project_id', p.id,
          'title', p.title,
          'milestones', private.client_milestones_json(p.id))
        order by p.created_at desc)
      from public.projects p
      join public.project_internal pi on pi.project_id = p.id
      where pi.client_id = v_client and p.archived_at is null and p.status <> 'draft'), '[]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin: client users
-- ---------------------------------------------------------------------------

-- Links an existing account to a client. The app first creates the account server-side (service
-- key, confirmed email, no usable password, app_metadata.client_invite = true); this function then
-- authorises and links it.
create function public.admin_invite_client_user(p_client_id uuid, p_email text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_client public.clients;
  v_user uuid;
  v_invited boolean;
  v_confirmed boolean;
  v_existing uuid;
  v_id uuid;
begin
  if p_client_id is null then
    raise exception 'Choose a client.' using errcode = 'ES422';
  end if;
  if char_length(v_email) > 254 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Enter a valid email address.' using errcode = 'ES422';
  end if;
  select * into v_client from public.clients c where c.id = p_client_id for share;
  if not found then
    raise exception 'That client does not exist.' using errcode = 'ES422';
  end if;
  if v_client.merged_into_id is not null then
    raise exception 'This client was merged into another record. Invite users on that record.' using errcode = 'ES409';
  end if;
  if v_client.archived_at is not null then
    raise exception 'Restore this client before inviting users.' using errcode = 'ES409';
  end if;

  select u.id, coalesce(u.raw_app_meta_data ->> 'client_invite', '') = 'true', u.email_confirmed_at is not null
  into v_user, v_invited, v_confirmed
  from auth.users u where lower(u.email) = v_email;
  if v_user is null then
    raise exception 'No sign-in account exists for that email yet.' using errcode = 'ES422';
  end if;
  -- Serialise invitations for the same account.
  perform 1 from public.profiles pr where pr.id = v_user for update;

  if exists (select 1 from public.admin_users a where a.user_id = v_user) then
    raise exception 'This email belongs to a studio account and cannot be a client user.' using errcode = 'ES409';
  end if;
  if exists (select 1 from public.editor_profiles e where e.user_id = v_user and e.access_status <> 'none')
     or exists (select 1 from public.editor_applications ea where ea.editor_id = v_user) then
    raise exception 'This email belongs to an editor or applicant account and cannot be a client user.' using errcode = 'ES409';
  end if;
  -- Only an invitation-created account (app_metadata flag set by the service key, confirmed), or
  -- a former client user, may be linked: a self-registered sign-up could have been created by
  -- someone else with this email. (app_metadata cannot be set by a user; user_metadata is ignored.)
  if (not v_invited or not v_confirmed)
     and not exists (select 1 from public.client_users cu where cu.user_id = v_user) then
    raise exception 'This email already has a self-registered EDITSTATION account, so it cannot be used for client access.'
      using errcode = 'ES409';
  end if;

  select cu.client_id into v_existing from public.client_users cu
  where cu.user_id = v_user and cu.revoked_at is null;
  if v_existing = p_client_id then
    raise exception 'This person already has access to this client.' using errcode = 'ES409';
  elsif v_existing is not null then
    raise exception 'This person already has access to another client.' using errcode = 'ES409';
  end if;

  insert into public.client_users (user_id, client_id, created_by)
  values (v_user, p_client_id, v_admin)
  returning id into v_id;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'client_user.invited', 'client_user', v_id::text,
    jsonb_build_object('client_id', p_client_id, 'user_id', v_user));
  return v_id;
end;
$$;

create function public.admin_revoke_client_user(p_client_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_row public.client_users;
begin
  select * into v_row from public.client_users cu where cu.id = p_client_user_id for update;
  if not found then
    raise exception 'That client user does not exist.' using errcode = 'ES422';
  end if;
  if v_row.revoked_at is not null then
    raise exception 'This client access was already removed.' using errcode = 'ES409';
  end if;
  update public.client_users set revoked_at = now(), revoked_by = v_admin where id = v_row.id;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'client_user.revoked', 'client_user', v_row.id::text,
    jsonb_build_object('client_id', v_row.client_id, 'user_id', v_row.user_id));
end;
$$;

-- Client users of one client (p_client_id null = every client), active first.
create function public.admin_list_client_users(p_client_id uuid default null)
returns table (
  id uuid,
  client_id uuid,
  user_id uuid,
  email text,
  created_at timestamptz,
  revoked_at timestamptz,
  last_sign_in_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  perform private.require_admin();
  return query
  select cu.id, cu.client_id, cu.user_id, pr.email, cu.created_at, cu.revoked_at, u.last_sign_in_at
  from public.client_users cu
  join public.profiles pr on pr.id = cu.user_id
  left join auth.users u on u.id = cu.user_id
  where p_client_id is null or cu.client_id = p_client_id
  order by (cu.revoked_at is null) desc, cu.created_at desc;
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin: client updates
-- ---------------------------------------------------------------------------
create function public.admin_publish_client_update(p_project_id uuid, p_body text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_body text := btrim(coalesce(p_body, ''));
  v_archived timestamptz;
  v_id uuid;
begin
  if char_length(v_body) not between 1 and 5000 then
    raise exception 'Write an update of up to 5000 characters.' using errcode = 'ES422';
  end if;
  select p.archived_at into v_archived from public.projects p where p.id = p_project_id for share;
  if not found then
    raise exception 'That project does not exist.' using errcode = 'ES422';
  end if;
  if v_archived is not null then
    raise exception 'Restore the project before publishing updates.' using errcode = 'ES409';
  end if;
  insert into public.client_project_updates (project_id, body, created_by)
  values (p_project_id, v_body, v_admin)
  returning id into v_id;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'client_update.published', 'project', p_project_id::text,
    jsonb_build_object('update_id', v_id, 'fields', jsonb_build_array('body')));
  return v_id;
end;
$$;

create function public.admin_withdraw_client_update(p_update_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_row public.client_project_updates;
begin
  select * into v_row from public.client_project_updates u where u.id = p_update_id for update;
  if not found then
    raise exception 'That update does not exist.' using errcode = 'ES422';
  end if;
  if not v_row.published then
    raise exception 'This update was already withdrawn.' using errcode = 'ES409';
  end if;
  update public.client_project_updates
  set published = false, withdrawn_at = now(), withdrawn_by = v_admin
  where id = v_row.id;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'client_update.withdrawn', 'project', v_row.project_id::text,
    jsonb_build_object('update_id', v_row.id, 'fields', jsonb_build_array('published')));
end;
$$;

-- What the project's client sees (mapped status, active user count) and every update.
create function public.admin_list_client_updates(p_project_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_status public.project_status;
  v_archived timestamptz;
  v_client uuid;
begin
  perform private.require_admin();
  select p.status, p.archived_at, pi.client_id into v_status, v_archived, v_client
  from public.projects p
  left join public.project_internal pi on pi.project_id = p.id
  where p.id = p_project_id;
  if not found then
    raise exception 'That project does not exist.' using errcode = 'ES422';
  end if;
  return jsonb_build_object(
    'client_status', private.client_status_key(v_status),
    'has_client', v_client is not null,
    'visible_to_client', v_status <> 'draft' and v_archived is null,
    'active_client_users', (select count(*) from public.client_users cu
                            where v_client is not null and cu.client_id = v_client and cu.revoked_at is null),
    'updates', coalesce((
      select jsonb_agg(jsonb_build_object(
          'id', u.id, 'body', u.body, 'published', u.published, 'created_at', u.created_at,
          'withdrawn_at', u.withdrawn_at)
        order by u.created_at desc)
      from public.client_project_updates u where u.project_id = p_project_id), '[]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin: bank details setting (blank clears it, which hides the panel from clients)
-- ---------------------------------------------------------------------------
create function public.admin_set_bank_details(p_details text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_details text := btrim(coalesce(p_details, ''));
begin
  if char_length(v_details) > 2000 then
    raise exception 'Keep the bank details to 2000 characters or fewer.' using errcode = 'ES422';
  end if;
  if v_details = '' then
    delete from public.app_settings where key = 'client_bank_details';
  else
    insert into public.app_settings (key, value, updated_by)
    values ('client_bank_details', to_jsonb(v_details), v_admin)
    on conflict (key) do update set value = excluded.value, updated_by = excluded.updated_by;
  end if;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'app_settings.changed', 'app_settings', 'client_bank_details',
    jsonb_build_object('fields', '["client_bank_details"]'::jsonb, 'cleared', v_details = ''));
end;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges: private helpers reach no API role; public functions are executable by
-- anon and authenticated and authorise in the body (guardrails 000 and 046).
-- ---------------------------------------------------------------------------
revoke all on function
  private.client_users_guard(), private.refuse_client_as_editor(), private.refuse_client_as_admin(),
  private.move_client_users_on_merge(), private.client_project_updates_guard(),
  private.refuse_client_application(),
  private.client_status_key(public.project_status),
  private.client_payment_status_key(public.client_milestone_kind, public.client_verification_status, timestamptz),
  private.require_client(), private.client_milestones_json(uuid)
from public, anon, authenticated, service_role;

revoke all on function
  public.my_client_status(), public.client_list_projects(), public.client_get_project(uuid),
  public.client_get_payment_info(), public.admin_invite_client_user(uuid, text),
  public.admin_revoke_client_user(uuid), public.admin_list_client_users(uuid),
  public.admin_publish_client_update(uuid, text), public.admin_withdraw_client_update(uuid),
  public.admin_list_client_updates(uuid), public.admin_set_bank_details(text)
from public, anon, authenticated;
grant execute on function
  public.my_client_status(), public.client_list_projects(), public.client_get_project(uuid),
  public.client_get_payment_info(), public.admin_invite_client_user(uuid, text),
  public.admin_revoke_client_user(uuid), public.admin_list_client_users(uuid),
  public.admin_publish_client_update(uuid, text), public.admin_withdraw_client_update(uuid),
  public.admin_list_client_updates(uuid), public.admin_set_bank_details(text)
to anon, authenticated;
