-- Phase 3: public client inquiries (no accounts) and admin inquiry management.
-- Decisions: N (statuses), U (links only), V (admin-managed budget ranges + discuss, none
-- seeded), H (LKR default, currency stored), O (honeypot + limits now; Turnstile before launch),
-- KB3 (placeholder service list from KB §7.1, admin-editable).
-- An inquiry is a lead, never a project: nothing here creates a project. Conversion is Phase 4.
-- Rules carried over: public functions are executable by anon + authenticated and authorise
-- in their body; custom SQLSTATEs ES4xx (ES429 = rate limited).

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------
create type public.inquiry_status as enum (
  'new', 'reviewing', 'contacted', 'in_discussion', 'converted', 'declined', 'closed', 'spam'
);

-- ---------------------------------------------------------------------------
-- Admin-managed reference lists (readable by the public form)
-- ---------------------------------------------------------------------------
create table public.service_types (
  code text primary key check (code ~ '^[a-z0-9_]{1,40}$'),
  label text not null check (char_length(label) between 1 and 80),
  active boolean not null default true,
  sort_order smallint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger service_types_set_updated_at
  before update on public.service_types
  for each row execute function private.set_updated_at();

-- KB3 is open: placeholder categories from KB §7.1, editable by admins.
insert into public.service_types (code, label, sort_order) values
  ('short_form_social', 'Short-form / social video', 10),
  ('long_form', 'Long-form video', 20),
  ('cinematic_storytelling', 'Cinematic / storytelling', 30),
  ('motion_graphics', 'Motion graphics', 40),
  ('not_sure', 'Not sure yet / something else', 99);

-- Decision V: ranges are admin-managed. None are seeded (no invented pricing).
create table public.budget_ranges (
  id uuid primary key default gen_random_uuid(),
  label text not null check (char_length(label) between 1 and 80),
  min_amount numeric(12, 2) check (min_amount >= 0),
  max_amount numeric(12, 2) check (max_amount >= 0),
  currency char(3) not null default 'LKR' check (currency ~ '^[A-Z]{3}$'),
  active boolean not null default true,
  sort_order smallint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (min_amount is null or max_amount is null or min_amount <= max_amount)
);
create trigger budget_ranges_set_updated_at
  before update on public.budget_ranges
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- Inquiries
-- ---------------------------------------------------------------------------
create table public.client_inquiries (
  id uuid primary key default gen_random_uuid(),
  contact_name text not null check (char_length(contact_name) between 1 and 200),
  company text check (char_length(company) between 1 and 200),
  email text not null check (char_length(email) <= 254 and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  phone text check (char_length(phone) between 1 and 40),
  service_type_code text not null references public.service_types (code),
  -- Labels are copied at submission so later renames don't rewrite what the client chose.
  service_type_label text not null,
  description text not null check (char_length(description) between 1 and 5000),
  expected_deliverables text check (char_length(expected_deliverables) between 1 and 2000),
  budget_range_id uuid references public.budget_ranges (id) on delete set null,
  budget_label text not null,
  budget_currency char(3) not null default 'LKR' check (budget_currency ~ '^[A-Z]{3}$'),
  expected_deadline date,
  client_notes text check (char_length(client_notes) between 1 and 2000),
  privacy_notice_version text not null check (char_length(privacy_notice_version) between 1 and 40),
  status public.inquiry_status not null default 'new',
  status_changed_at timestamptz,
  status_changed_by uuid references public.profiles (id) on delete set null,
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index client_inquiries_status_idx on public.client_inquiries (status, submitted_at desc);
create index client_inquiries_email_idx on public.client_inquiries (lower(email), submitted_at desc);
create index client_inquiries_submitted_at_idx on public.client_inquiries (submitted_at desc);
create index client_inquiries_service_type_idx on public.client_inquiries (service_type_code);
create index client_inquiries_budget_range_idx on public.client_inquiries (budget_range_id);
create index client_inquiries_status_changed_by_idx on public.client_inquiries (status_changed_by);
create trigger client_inquiries_set_updated_at
  before update on public.client_inquiries
  for each row execute function private.set_updated_at();

create table public.client_inquiry_links (
  id uuid primary key default gen_random_uuid(),
  inquiry_id uuid not null references public.client_inquiries (id) on delete cascade,
  url text not null check (url ~ '^https://[^\s]+$' and char_length(url) <= 2048),
  label text check (char_length(label) between 1 and 120)
);
create index client_inquiry_links_inquiry_idx on public.client_inquiry_links (inquiry_id);

create table public.inquiry_notes (
  id uuid primary key default gen_random_uuid(),
  inquiry_id uuid not null references public.client_inquiries (id) on delete cascade,
  author_id uuid references public.profiles (id) on delete set null,
  note text not null check (char_length(note) between 1 and 4000),
  created_at timestamptz not null default now()
);
create index inquiry_notes_inquiry_idx on public.inquiry_notes (inquiry_id);
create index inquiry_notes_author_idx on public.inquiry_notes (author_id);

alter table public.service_types enable row level security;
alter table public.budget_ranges enable row level security;
alter table public.client_inquiries enable row level security;
alter table public.client_inquiry_links enable row level security;
alter table public.inquiry_notes enable row level security;

-- ---------------------------------------------------------------------------
-- Privileges and policies
-- ---------------------------------------------------------------------------
revoke all on public.service_types, public.budget_ranges, public.client_inquiries,
  public.client_inquiry_links, public.inquiry_notes from anon, authenticated;

-- Reference lists: the public form reads active rows; admins manage them.
grant select on public.service_types, public.budget_ranges to anon, authenticated;
grant insert, update on public.service_types, public.budget_ranges to authenticated;

create policy service_types_select on public.service_types
  for select to anon, authenticated
  using (active or (select private.is_admin()));
create policy service_types_insert_admin on public.service_types
  for insert to authenticated with check ((select private.is_admin()));
create policy service_types_update_admin on public.service_types
  for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));

create policy budget_ranges_select on public.budget_ranges
  for select to anon, authenticated
  using (active or (select private.is_admin()));
create policy budget_ranges_insert_admin on public.budget_ranges
  for insert to authenticated with check ((select private.is_admin()));
create policy budget_ranges_update_admin on public.budget_ranges
  for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));

-- Inquiries: admin-only reads; writes only through functions. Anonymous visitors can submit
-- (function) but can never read anything back.
grant select on public.client_inquiries, public.client_inquiry_links to authenticated;
grant select, insert on public.inquiry_notes to authenticated;

create policy client_inquiries_select_admin on public.client_inquiries
  for select to authenticated using ((select private.is_admin()));
create policy client_inquiry_links_select_admin on public.client_inquiry_links
  for select to authenticated using ((select private.is_admin()));
create policy inquiry_notes_select_admin on public.inquiry_notes
  for select to authenticated using ((select private.is_admin()));
create policy inquiry_notes_insert_admin on public.inquiry_notes
  for insert to authenticated
  with check ((select private.is_admin()) and author_id = (select auth.uid()));

-- Per-source throttle (decision O). Holds only a SHA-256 hash of the client IP, supplied by the
-- app, and only for one hour. Not reachable through the API (private schema).
create table private.inquiry_throttle (
  client_key text not null check (client_key ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now()
);
create index inquiry_throttle_key_idx on private.inquiry_throttle (client_key, created_at);
revoke all on private.inquiry_throttle from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Audit (no personal data in details)
-- ---------------------------------------------------------------------------
create function private.audit_client_inquiries()
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
    );
  end if;
  return new;
end;
$$;

create trigger client_inquiries_audit
  after insert or update of status on public.client_inquiries
  for each row execute function private.audit_client_inquiries();

-- ---------------------------------------------------------------------------
-- Public submission (anonymous). Returns nothing readable.
-- ---------------------------------------------------------------------------
create function public.submit_client_inquiry(
  p_contact_name text,
  p_company text,
  p_email text,
  p_phone text,
  p_service_type text,
  p_description text,
  p_expected_deliverables text,
  p_budget_range_id uuid,
  p_expected_deadline date,
  p_client_notes text,
  p_links jsonb,
  p_privacy_notice_version text,
  p_client_key text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_service public.service_types%rowtype;
  v_budget public.budget_ranges%rowtype;
  v_email text := lower(trim(p_email));
  v_id uuid;
  v_link jsonb;
begin
  if nullif(trim(p_contact_name), '') is null or nullif(v_email, '') is null
     or nullif(trim(p_description), '') is null then
    raise exception 'Please give your name, email and a project description.' using errcode = 'ES422';
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

  -- Abuse limits (decision O). The app adds a honeypot and per-IP limit; Turnstile comes
  -- before public launch. These hold even if the database function is called directly.
  if (select count(*) from public.client_inquiries
      where lower(email) = v_email and submitted_at > now() - interval '1 hour') >= 3 then
    raise exception 'You have sent several inquiries recently. Please wait a while, or email us directly.'
      using errcode = 'ES429';
  end if;
  -- Per source (hashed IP from the app; absent when the function is called directly).
  delete from private.inquiry_throttle where created_at < now() - interval '1 hour';
  if p_client_key is not null then
    if p_client_key !~ '^[0-9a-f]{64}$' then
      raise exception 'Invalid request.' using errcode = 'ES422';
    end if;
    if (select count(*) from private.inquiry_throttle where client_key = p_client_key) >= 5 then
      raise exception 'You have sent several inquiries recently. Please wait a while, or email us directly.'
        using errcode = 'ES429';
    end if;
  end if;
  if (select count(*) from public.client_inquiries
      where submitted_at > now() - interval '1 hour') >= 100 then
    raise exception 'We are receiving a lot of inquiries right now. Please try again later.'
      using errcode = 'ES429';
  end if;

  insert into public.client_inquiries (
    contact_name, company, email, phone, service_type_code, service_type_label, description,
    expected_deliverables, budget_range_id, budget_label, budget_currency, expected_deadline,
    client_notes, privacy_notice_version)
  values (
    trim(p_contact_name), nullif(trim(p_company), ''), v_email, nullif(trim(p_phone), ''),
    v_service.code, v_service.label, trim(p_description),
    nullif(trim(p_expected_deliverables), ''),
    v_budget.id, coalesce(v_budget.label, 'Prefer to discuss'), coalesce(v_budget.currency, 'LKR'),
    p_expected_deadline, nullif(trim(p_client_notes), ''), trim(p_privacy_notice_version))
  returning id into v_id;

  if p_client_key is not null then
    insert into private.inquiry_throttle (client_key) values (p_client_key);
  end if;

  for v_link in select * from jsonb_array_elements(coalesce(p_links, '[]'::jsonb)) loop
    insert into public.client_inquiry_links (inquiry_id, url, label)
    values (v_id, trim(v_link ->> 'url'), nullif(trim(v_link ->> 'label'), ''));
  end loop;
exception
  when check_violation then
    raise exception 'Please check your entries: links must start with https:// and fields must not be too long.'
      using errcode = 'ES422';
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin status changes
-- ---------------------------------------------------------------------------
create function public.admin_set_inquiry_status(
  p_inquiry_id uuid, p_status public.inquiry_status, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_current public.inquiry_status;
begin
  if p_status = 'converted' then
    raise exception 'An inquiry becomes "converted" only when a project is created from it.'
      using errcode = 'ES409';
  end if;

  select status into v_current from public.client_inquiries where id = p_inquiry_id for update;
  if v_current is null then
    raise exception 'Inquiry not found.' using errcode = 'ES422';
  end if;
  if v_current = 'converted' then
    raise exception 'A converted inquiry cannot change status.' using errcode = 'ES409';
  end if;
  if v_current = p_status then
    raise exception 'The inquiry already has that status.' using errcode = 'ES409';
  end if;

  update public.client_inquiries
  set status = p_status, status_changed_at = now(), status_changed_by = v_admin
  where id = p_inquiry_id;

  if nullif(trim(p_note), '') is not null then
    insert into public.inquiry_notes (inquiry_id, author_id, note)
    values (p_inquiry_id, v_admin, trim(p_note));
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges
-- ---------------------------------------------------------------------------
grant execute on function
  public.submit_client_inquiry(text, text, text, text, text, text, text, uuid, date, text, jsonb, text, text),
  public.admin_set_inquiry_status(uuid, public.inquiry_status, text)
to anon, authenticated;

revoke execute on function private.audit_client_inquiries() from public, anon, authenticated;
