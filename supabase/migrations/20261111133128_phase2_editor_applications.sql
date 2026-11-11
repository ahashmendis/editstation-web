-- Phase 2: editor applications and vetting.
-- Decisions: L (application statuses), M (only an admin can reopen a rejected application),
--            E (no bank details in applications), G open (assessment payment not recorded).
-- Rules from Phase 1: every function in `public` is executable by anon + authenticated and
-- authorises inside its body; helpers live in `private`. Custom SQLSTATEs (never 42501, see
-- docs/SECURITY_AND_PRIVACY.md): ES401 not signed in, ES403 not allowed, ES409 wrong state,
-- ES422 invalid input.

-- ---------------------------------------------------------------------------
-- Fix (found in Phase 2 testing): the Phase 1 append-only trigger blocked the
-- `on delete set null` of activity_logs.actor_id, so no account could ever be deleted
-- (including for data-protection requests). Allow exactly one kind of change: clearing
-- actor_id with every other column unchanged. Everything else stays blocked.
-- Retention of the remaining log content is an owner/legal decision (OPEN_QUESTIONS P).
-- ---------------------------------------------------------------------------
create or replace function private.prevent_activity_log_changes()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
     and new.actor_id is null
     and old.actor_id is not null
     and (new.id, new.action, new.entity_type, new.entity_id, new.details, new.created_at)
         is not distinct from
         (old.id, old.action, old.entity_type, old.entity_id, old.details, old.created_at)
  then
    return new;  -- anonymising a deleted actor
  end if;
  raise exception 'activity_logs is append-only' using errcode = '42501';
end;
$$;

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------
create type public.application_status as enum (
  'draft', 'submitted', 'under_review', 'info_requested', 'test_requested',
  'approved', 'rejected', 'withdrawn'
);
create type public.editor_level as enum ('junior', 'professional', 'specialist');
create type public.profile_option_kind as enum ('specialisation', 'software');
create type public.application_request_kind as enum ('info', 'test');
create type public.assessment_result as enum ('passed', 'failed', 'inconclusive');

-- ---------------------------------------------------------------------------
-- Editor profile fields (KB §7.3; only what is operationally necessary)
-- ---------------------------------------------------------------------------
alter table public.editor_profiles
  add column region text check (char_length(region) between 1 and 120),
  add column experience_years smallint check (experience_years between 0 and 60),
  add column experience_summary text check (char_length(experience_summary) between 1 and 2000),
  add column availability text check (char_length(availability) between 1 and 500),
  add column typical_turnaround text check (char_length(typical_turnaround) between 1 and 200),
  add column hardware text check (char_length(hardware) between 1 and 500),
  add column software_other text check (char_length(software_other) between 1 and 200),
  add column level public.editor_level;

comment on column public.editor_profiles.level is 'Set by an admin at approval (KB §7.4).';

-- Owner may edit their own profile fields; access/level columns stay admin-only.
grant update (region, experience_years, experience_summary, availability, typical_turnaround,
              hardware, software_other)
  on public.editor_profiles to authenticated;

create policy editor_profiles_update_own on public.editor_profiles
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Reference options (admin-managed lists; seeded from KB §7.1 and §7.3)
-- ---------------------------------------------------------------------------
create table public.profile_options (
  kind public.profile_option_kind not null,
  code text not null check (code ~ '^[a-z0-9_]{1,40}$'),
  label text not null check (char_length(label) between 1 and 80),
  active boolean not null default true,
  sort_order smallint not null default 0,
  primary key (kind, code)
);

insert into public.profile_options (kind, code, label, sort_order) values
  ('specialisation', 'short_form_social', 'Short-form / social', 10),
  ('specialisation', 'long_form', 'Long-form', 20),
  ('specialisation', 'cinematic_storytelling', 'Cinematic / storytelling', 30),
  ('specialisation', 'motion_graphics', 'Motion graphics', 40),
  ('software', 'davinci_resolve', 'DaVinci Resolve', 10),
  ('software', 'premiere_pro', 'Adobe Premiere Pro', 20),
  ('software', 'final_cut_pro', 'Final Cut Pro', 30),
  ('software', 'capcut', 'CapCut', 40);

create table public.editor_profile_options (
  editor_id uuid not null references public.editor_profiles (user_id) on delete cascade,
  kind public.profile_option_kind not null,
  code text not null,
  created_at timestamptz not null default now(),
  primary key (editor_id, kind, code),
  foreign key (kind, code) references public.profile_options (kind, code)
);
create index editor_profile_options_option_idx on public.editor_profile_options (kind, code);

create table public.editor_portfolio_links (
  id uuid primary key default gen_random_uuid(),
  editor_id uuid not null references public.editor_profiles (user_id) on delete cascade,
  url text not null check (url ~ '^https://[^\s]+$' and char_length(url) <= 2048),
  label text check (char_length(label) between 1 and 120),
  created_at timestamptz not null default now()
);
create index editor_portfolio_links_editor_idx on public.editor_portfolio_links (editor_id);

-- ---------------------------------------------------------------------------
-- Applications, requests, vetting notes
-- ---------------------------------------------------------------------------
create table public.editor_applications (
  id uuid primary key default gen_random_uuid(),
  editor_id uuid not null references public.editor_profiles (user_id) on delete cascade,
  attempt smallint not null default 1 check (attempt >= 1),
  status public.application_status not null default 'draft',
  -- What the applicant submitted, frozen at submission so later profile edits don't change
  -- what was reviewed. Never queried for logic.
  submitted_snapshot jsonb,
  submitted_at timestamptz,
  terms_version text check (char_length(terms_version) between 1 and 40),
  privacy_version text check (char_length(privacy_version) between 1 and 40),
  review_started_by uuid references public.profiles (id) on delete set null,
  review_started_at timestamptz,
  decided_by uuid references public.profiles (id) on delete set null,
  decided_at timestamptz,
  -- Shown to the applicant. Internal reasoning belongs in editor_vetting_notes.
  decision_message text check (char_length(decision_message) between 1 and 2000),
  reopened_from uuid references public.editor_applications (id) on delete set null,
  reopened_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (editor_id, attempt)
);
-- At most one draft/open application per editor.
create unique index editor_applications_one_active_idx on public.editor_applications (editor_id)
  where status in ('draft', 'submitted', 'under_review', 'info_requested', 'test_requested');
create index editor_applications_status_idx on public.editor_applications (status, submitted_at);
create index editor_applications_review_started_by_idx on public.editor_applications (review_started_by);
create index editor_applications_decided_by_idx on public.editor_applications (decided_by);
create index editor_applications_reopened_from_idx on public.editor_applications (reopened_from);
create index editor_applications_reopened_by_idx on public.editor_applications (reopened_by);

create trigger editor_applications_set_updated_at
  before update on public.editor_applications
  for each row execute function private.set_updated_at();

create table public.application_requests (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.editor_applications (id) on delete cascade,
  kind public.application_request_kind not null,
  message text not null check (char_length(message) between 1 and 4000),
  requested_by uuid references public.profiles (id) on delete set null,
  requested_at timestamptz not null default now(),
  response text check (char_length(response) between 1 and 4000),
  response_link text check (response_link ~ '^https://[^\s]+$' and char_length(response_link) <= 2048),
  responded_at timestamptz,
  -- Practical test outcome (kind = 'test' only). Whether tests are paid is open (question G).
  assessment_result public.assessment_result,
  assessment_notes text check (char_length(assessment_notes) between 1 and 4000),
  assessed_by uuid references public.profiles (id) on delete set null,
  assessed_at timestamptz,
  check (assessment_result is null or kind = 'test')
);
create index application_requests_application_idx on public.application_requests (application_id);
create index application_requests_requested_by_idx on public.application_requests (requested_by);
create index application_requests_assessed_by_idx on public.application_requests (assessed_by);

create table public.editor_vetting_notes (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.editor_applications (id) on delete cascade,
  author_id uuid references public.profiles (id) on delete set null,
  note text not null check (char_length(note) between 1 and 4000),
  created_at timestamptz not null default now()
);
create index editor_vetting_notes_application_idx on public.editor_vetting_notes (application_id);
create index editor_vetting_notes_author_idx on public.editor_vetting_notes (author_id);

alter table public.profile_options enable row level security;
alter table public.editor_profile_options enable row level security;
alter table public.editor_portfolio_links enable row level security;
alter table public.editor_applications enable row level security;
alter table public.application_requests enable row level security;
alter table public.editor_vetting_notes enable row level security;

-- ---------------------------------------------------------------------------
-- Privileges and policies
-- ---------------------------------------------------------------------------
revoke all on public.profile_options, public.editor_profile_options, public.editor_portfolio_links,
  public.editor_applications, public.application_requests, public.editor_vetting_notes
  from anon, authenticated;

grant select on public.profile_options to authenticated;
grant select, insert, delete on public.editor_profile_options to authenticated;
grant select, insert, delete on public.editor_portfolio_links to authenticated;
grant update (url, label) on public.editor_portfolio_links to authenticated;
grant select on public.editor_applications to authenticated;   -- writes only via functions
grant select on public.application_requests to authenticated;  -- writes only via functions
grant select, insert on public.editor_vetting_notes to authenticated;

create policy profile_options_select on public.profile_options
  for select to authenticated using (active or (select private.is_admin()));

create policy editor_profile_options_select on public.editor_profile_options
  for select to authenticated
  using (editor_id = (select auth.uid()) or (select private.is_admin()));
create policy editor_profile_options_insert_own on public.editor_profile_options
  for insert to authenticated
  with check (editor_id = (select auth.uid()));
create policy editor_profile_options_delete_own on public.editor_profile_options
  for delete to authenticated
  using (editor_id = (select auth.uid()));

create policy editor_portfolio_links_select on public.editor_portfolio_links
  for select to authenticated
  using (editor_id = (select auth.uid()) or (select private.is_admin()));
create policy editor_portfolio_links_insert_own on public.editor_portfolio_links
  for insert to authenticated
  with check (editor_id = (select auth.uid()));
create policy editor_portfolio_links_update_own on public.editor_portfolio_links
  for update to authenticated
  using (editor_id = (select auth.uid()))
  with check (editor_id = (select auth.uid()));
create policy editor_portfolio_links_delete_own on public.editor_portfolio_links
  for delete to authenticated
  using (editor_id = (select auth.uid()));

create policy editor_applications_select on public.editor_applications
  for select to authenticated
  using (editor_id = (select auth.uid()) or (select private.is_admin()));

create policy application_requests_select on public.application_requests
  for select to authenticated
  using (
    (select private.is_admin())
    or exists (
      select 1 from public.editor_applications a
      where a.id = application_id and a.editor_id = (select auth.uid())
    )
  );

create policy editor_vetting_notes_select_admin on public.editor_vetting_notes
  for select to authenticated using ((select private.is_admin()));
create policy editor_vetting_notes_insert_admin on public.editor_vetting_notes
  for insert to authenticated
  with check ((select private.is_admin()) and author_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Integrity triggers
-- ---------------------------------------------------------------------------
create function private.limit_portfolio_links()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select count(*) from public.editor_portfolio_links where editor_id = new.editor_id) >= 10 then
    raise exception 'You can add up to 10 portfolio links.' using errcode = 'ES422';
  end if;
  return new;
end;
$$;

create trigger editor_portfolio_links_limit
  before insert on public.editor_portfolio_links
  for each row execute function private.limit_portfolio_links();

-- Only active options can be newly selected.
create function private.require_active_option()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.profile_options
    where kind = new.kind and code = new.code and active
  ) then
    raise exception 'That option is not available.' using errcode = 'ES422';
  end if;
  return new;
end;
$$;

create trigger editor_profile_options_active
  before insert on public.editor_profile_options
  for each row execute function private.require_active_option();

create function private.audit_editor_applications()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or old.status is distinct from new.status then
    insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
    values (
      (select auth.uid()),
      'application.' || new.status::text,
      'editor_application',
      new.id::text,
      jsonb_build_object(
        'editor_id', new.editor_id,
        'attempt', new.attempt,
        'from', case when tg_op = 'INSERT' then null else old.status end,
        'to', new.status
      )
    );
  end if;
  return new;
end;
$$;

create trigger editor_applications_audit
  after insert or update of status on public.editor_applications
  for each row execute function private.audit_editor_applications();

create function private.audit_application_requests()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (
    (select auth.uid()),
    case
      when tg_op = 'INSERT' then 'application_request.created'
      when old.responded_at is null and new.responded_at is not null then 'application_request.answered'
      when old.assessment_result is distinct from new.assessment_result then 'assessment.recorded'
      else 'application_request.updated'
    end,
    'application_request',
    new.id::text,
    jsonb_build_object('application_id', new.application_id, 'kind', new.kind,
                       'assessment_result', new.assessment_result)
  );
  return new;
end;
$$;

create trigger application_requests_audit
  after insert or update on public.application_requests
  for each row execute function private.audit_application_requests();

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------
create function private.require_user()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'Please sign in.' using errcode = 'ES401';
  end if;
  return v_uid;
end;
$$;

create function private.require_admin()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
begin
  if not private.is_admin() then
    raise exception 'Admin access with two-step verification is required.' using errcode = 'ES403';
  end if;
  return v_uid;
end;
$$;

-- Frozen copy of what an applicant submitted.
create function private.application_snapshot(p_editor_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'full_name', p.full_name,
    'email', p.email,
    'phone', p.phone,
    'region', e.region,
    'experience_years', e.experience_years,
    'experience_summary', e.experience_summary,
    'availability', e.availability,
    'typical_turnaround', e.typical_turnaround,
    'hardware', e.hardware,
    'software_other', e.software_other,
    'specialisations', coalesce((
      select jsonb_agg(o.label order by o.sort_order)
      from public.editor_profile_options epo
      join public.profile_options o on o.kind = epo.kind and o.code = epo.code
      where epo.editor_id = p_editor_id and epo.kind = 'specialisation'), '[]'::jsonb),
    'software', coalesce((
      select jsonb_agg(o.label order by o.sort_order)
      from public.editor_profile_options epo
      join public.profile_options o on o.kind = epo.kind and o.code = epo.code
      where epo.editor_id = p_editor_id and epo.kind = 'software'), '[]'::jsonb),
    'portfolio_links', coalesce((
      select jsonb_agg(jsonb_build_object('url', l.url, 'label', l.label) order by l.created_at)
      from public.editor_portfolio_links l where l.editor_id = p_editor_id), '[]'::jsonb)
  )
  from public.profiles p
  join public.editor_profiles e on e.user_id = p.id
  where p.id = p_editor_id;
$$;

-- Which required fields are missing (empty array = complete).
create function private.application_missing_fields(p_editor_id uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select array_remove(array[
    case when p.full_name is null then 'full name' end,
    case when p.phone is null then 'phone' end,
    case when e.region is null then 'general location' end,
    case when e.experience_years is null then 'years of experience' end,
    case when e.experience_summary is null then 'experience summary' end,
    case when e.availability is null then 'availability' end,
    case when e.typical_turnaround is null then 'typical turnaround' end,
    case when not exists (select 1 from public.editor_portfolio_links where editor_id = p_editor_id)
      then 'at least one portfolio link' end,
    case when not exists (select 1 from public.editor_profile_options
                          where editor_id = p_editor_id and kind = 'specialisation')
      then 'at least one specialisation' end,
    case when e.software_other is null and not exists (
           select 1 from public.editor_profile_options
           where editor_id = p_editor_id and kind = 'software')
      then 'editing software' end
  ], null)
  from public.profiles p
  join public.editor_profiles e on e.user_id = p.id
  where p.id = p_editor_id;
$$;

-- ---------------------------------------------------------------------------
-- Applicant actions
-- ---------------------------------------------------------------------------

-- Save the caller's own profile, options and portfolio links in one transaction.
-- Fields may be partial (drafts); completeness is enforced at submission.
create function public.save_editor_profile(
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
create function public.submit_editor_application(p_terms_version text, p_privacy_version text)
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

create function public.withdraw_editor_application()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
  v_id uuid;
begin
  update public.editor_applications
  set status = 'withdrawn'
  where editor_id = v_uid
    and status in ('submitted', 'under_review', 'info_requested', 'test_requested')
  returning id into v_id;

  if v_id is null then
    raise exception 'There is no submitted application to withdraw.' using errcode = 'ES409';
  end if;
  return v_id;
end;
$$;

create function public.respond_to_application_request(
  p_request_id uuid, p_response text, p_response_link text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
  v_app_id uuid;
begin
  select r.application_id into v_app_id
  from public.application_requests r
  join public.editor_applications a on a.id = r.application_id
  where r.id = p_request_id
    and a.editor_id = v_uid
    and r.responded_at is null
    and a.status in ('info_requested', 'test_requested')
  for update of r;

  if v_app_id is null then
    raise exception 'This request is not open for a response.' using errcode = 'ES409';
  end if;
  if nullif(trim(p_response), '') is null and nullif(trim(p_response_link), '') is null then
    raise exception 'Please add a response or a link.' using errcode = 'ES422';
  end if;

  update public.application_requests
  set response = nullif(trim(p_response), ''),
      response_link = nullif(trim(p_response_link), ''),
      responded_at = now()
  where id = p_request_id;

  -- Back to review once nothing is outstanding.
  if not exists (
    select 1 from public.application_requests
    where application_id = v_app_id and responded_at is null
  ) then
    update public.editor_applications set status = 'under_review' where id = v_app_id;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin actions (require MFA-verified admin)
-- ---------------------------------------------------------------------------
create function public.admin_start_application_review(p_application_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
begin
  update public.editor_applications
  set status = 'under_review', review_started_by = v_admin, review_started_at = now()
  where id = p_application_id and status = 'submitted';
  if not found then
    raise exception 'Only a newly submitted application can be moved to review.' using errcode = 'ES409';
  end if;
end;
$$;

create function public.admin_create_application_request(
  p_application_id uuid, p_kind public.application_request_kind, p_message text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_status public.application_status;
  v_request_id uuid;
begin
  if nullif(trim(p_message), '') is null then
    raise exception 'Please write the request.' using errcode = 'ES422';
  end if;

  select status into v_status from public.editor_applications where id = p_application_id for update;
  if v_status is null or v_status not in ('submitted', 'under_review', 'info_requested', 'test_requested') then
    raise exception 'Requests can only be sent while an application is open.' using errcode = 'ES409';
  end if;

  insert into public.application_requests (application_id, kind, message, requested_by)
  values (p_application_id, p_kind, trim(p_message), v_admin)
  returning id into v_request_id;

  update public.editor_applications
  set status = case when p_kind = 'test' then 'test_requested' else 'info_requested' end::public.application_status,
      review_started_by = coalesce(review_started_by, v_admin),
      review_started_at = coalesce(review_started_at, now())
  where id = p_application_id;

  return v_request_id;
end;
$$;

create function public.admin_record_assessment_result(
  p_request_id uuid, p_result public.assessment_result, p_notes text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
begin
  update public.application_requests
  set assessment_result = p_result,
      assessment_notes = nullif(trim(p_notes), ''),
      assessed_by = v_admin,
      assessed_at = now()
  where id = p_request_id and kind = 'test';
  if not found then
    raise exception 'Results can only be recorded on a practical test request.' using errcode = 'ES409';
  end if;
end;
$$;

create function public.admin_approve_application(
  p_application_id uuid, p_level public.editor_level, p_message text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_editor uuid;
begin
  if p_level is null then
    raise exception 'Choose an initial level.' using errcode = 'ES422';
  end if;

  update public.editor_applications
  set status = 'approved', decided_by = v_admin, decided_at = now(),
      decision_message = nullif(trim(p_message), '')
  where id = p_application_id and status in ('submitted', 'under_review')
  returning editor_id into v_editor;

  if v_editor is null then
    raise exception 'Only a submitted or in-review application with no open requests can be approved.'
      using errcode = 'ES409';
  end if;

  -- Approval is the only path that activates editor access (decisions D, L).
  update public.editor_profiles
  set access_status = 'active', level = p_level,
      access_changed_at = now(), access_changed_by = v_admin,
      access_change_reason = 'Application approved'
  where user_id = v_editor and access_status = 'none';
  if not found then
    raise exception 'This account''s editor access cannot be activated from its current state.'
      using errcode = 'ES409';
  end if;
end;
$$;

create function public.admin_reject_application(p_application_id uuid, p_message text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
begin
  update public.editor_applications
  set status = 'rejected', decided_by = v_admin, decided_at = now(),
      decision_message = nullif(trim(p_message), '')
  where id = p_application_id
    and status in ('submitted', 'under_review', 'info_requested', 'test_requested');
  if not found then
    raise exception 'Only an open application can be rejected.' using errcode = 'ES409';
  end if;
end;
$$;

-- Decision M: the only way a rejected (or withdrawn) applicant can apply again.
create function public.admin_reopen_application(p_editor_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_last public.editor_applications%rowtype;
  v_new uuid;
begin
  select * into v_last from public.editor_applications
  where editor_id = p_editor_id order by attempt desc limit 1 for update;

  if v_last.id is null or v_last.status not in ('rejected', 'withdrawn') then
    raise exception 'Only a rejected or withdrawn application can be reopened.' using errcode = 'ES409';
  end if;
  if (select access_status from public.editor_profiles where user_id = p_editor_id) <> 'none' then
    raise exception 'This account already has editor status.' using errcode = 'ES409';
  end if;

  insert into public.editor_applications (editor_id, attempt, status, reopened_from, reopened_by)
  values (p_editor_id, v_last.attempt + 1, 'draft', v_last.id, v_admin)
  returning id into v_new;
  return v_new;
end;
$$;

create function public.admin_set_editor_access(
  p_editor_id uuid, p_status public.editor_access_status, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_current public.editor_access_status;
begin
  if nullif(trim(p_reason), '') is null then
    raise exception 'Please give a reason.' using errcode = 'ES422';
  end if;

  select access_status into v_current from public.editor_profiles where user_id = p_editor_id for update;
  if v_current is null then
    raise exception 'Editor not found.' using errcode = 'ES422';
  end if;

  -- Allowed: active -> suspended | revoked, suspended -> active | revoked. Revoked is final.
  -- Activation from 'none' happens only through admin_approve_application.
  if not (
    (v_current = 'active' and p_status in ('suspended', 'revoked'))
    or (v_current = 'suspended' and p_status in ('active', 'revoked'))
  ) then
    raise exception 'Cannot change editor access from % to %.', v_current, p_status using errcode = 'ES409';
  end if;

  update public.editor_profiles
  set access_status = p_status, access_changed_at = now(), access_changed_by = v_admin,
      access_change_reason = trim(p_reason)
  where user_id = p_editor_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges
-- ---------------------------------------------------------------------------
-- Public API functions: executable by both API roles (guardrail); each authorises itself.
grant execute on function
  public.save_editor_profile(text, text, text, smallint, text, text, text, text, text, text[], text[], jsonb),
  public.submit_editor_application(text, text),
  public.withdraw_editor_application(),
  public.respond_to_application_request(uuid, text, text),
  public.admin_start_application_review(uuid),
  public.admin_create_application_request(uuid, public.application_request_kind, text),
  public.admin_record_assessment_result(uuid, public.assessment_result, text),
  public.admin_approve_application(uuid, public.editor_level, text),
  public.admin_reject_application(uuid, text),
  public.admin_reopen_application(uuid),
  public.admin_set_editor_access(uuid, public.editor_access_status, text)
to anon, authenticated;

-- Internal helpers: not callable by API roles. require_user/require_admin run inside the
-- security definer functions above (as their owner), so no API grant is needed.
revoke execute on function
  private.require_user(), private.require_admin(), private.application_snapshot(uuid),
  private.application_missing_fields(uuid), private.limit_portfolio_links(),
  private.require_active_option(), private.audit_editor_applications(),
  private.audit_application_requests()
from public, anon, authenticated;
