-- Phase 4 (1/6): projects, briefs and clients schema.
-- Spec: docs/superpowers/specs/2026-11-13-phase4-projects-briefs-design.md §5, §6.
-- Decisions: J (project statuses), T (clients table, admin-only).
-- Every table is admin-read-only through the API. There are no insert/update/delete grants or
-- policies: all writes go through public.admin_* security definer functions (later migrations).
-- Editor-visible-later tables (projects, brief_versions, project_deliverables,
-- project_references) never hold client identity or client price.

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------
create type public.project_status as enum (
  'draft', 'open', 'assigned', 'in_progress', 'in_review', 'revision_requested', 'approved',
  'completed', 'on_hold', 'cancelled'
);
create type public.brief_type as enum ('fully_instructed', 'reference_based', 'creative_led');
create type public.reference_priority as enum ('essential', 'optional');

-- ---------------------------------------------------------------------------
-- Clients (admin-only; decision T)
-- ---------------------------------------------------------------------------
create table public.clients (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 200),
  company text check (char_length(company) between 1 and 200),
  -- Stored normalised; the matching key is exactly lower(btrim(email)).
  email text not null check (
    email = lower(btrim(email))
    and char_length(email) <= 254
    and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  phone text check (char_length(phone) between 1 and 40),
  notes text check (char_length(notes) between 1 and 5000),
  merged_into_id uuid references public.clients (id) on delete restrict,
  archived_at timestamptz,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint clients_not_merged_into_self check (merged_into_id is distinct from id)
);
-- One record per email among unmerged clients (archived ones included).
create unique index clients_email_unmerged_key on public.clients (email) where merged_into_id is null;
create index clients_merged_into_idx on public.clients (merged_into_id);
create index clients_created_by_idx on public.clients (created_by);
create trigger clients_set_updated_at
  before update on public.clients
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- Projects (editor-safe columns only: never client identity or client price)
-- ---------------------------------------------------------------------------
create table public.projects (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 200),
  brief_type public.brief_type not null,
  service_type_code text references public.service_types (code),
  status public.project_status not null default 'draft',
  status_before_hold public.project_status,
  summary text check (char_length(summary) between 1 and 5000),
  deadline date,
  requires_interpretation boolean not null default false,
  -- Pay offered to editors (not client data). Null until the admin sets it.
  proposed_amount numeric(12, 2) check (proposed_amount >= 0),
  proposed_currency char(3) not null default 'LKR' check (proposed_currency ~ '^[A-Z]{3}$'),
  revision_allowance smallint not null default 3 check (revision_allowance between 0 and 20),
  current_brief_version int not null default 1 check (current_brief_version >= 1),
  -- Set the first time the project becomes open; never changed or cleared afterwards.
  first_opened_at timestamptz,
  created_by uuid references public.profiles (id) on delete set null,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint projects_hold_state_chk check (
    (status = 'on_hold') = (status_before_hold is not null)
    and (status_before_hold is null or status_before_hold <> 'on_hold'))
);
create index projects_status_idx on public.projects (status, created_at desc);
create index projects_service_type_idx on public.projects (service_type_code);
create index projects_created_by_idx on public.projects (created_by);
create trigger projects_set_updated_at
  before update on public.projects
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- Project internal record (admin-only, 1:1): client link, client price, notes
-- ---------------------------------------------------------------------------
create table public.project_internal (
  project_id uuid primary key references public.projects (id) on delete cascade,
  client_id uuid references public.clients (id) on delete restrict,
  source_inquiry_id uuid unique references public.client_inquiries (id) on delete restrict,
  client_price numeric(12, 2) check (client_price >= 0),
  client_price_currency char(3) not null default 'LKR' check (client_price_currency ~ '^[A-Z]{3}$'),
  internal_notes text check (char_length(internal_notes) between 1 and 5000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index project_internal_client_idx on public.project_internal (client_id);
create trigger project_internal_set_updated_at
  before update on public.project_internal
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- Brief versions (immutable once the project has been opened)
-- ---------------------------------------------------------------------------
create table public.brief_versions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  version int not null check (version >= 1),
  change_summary text check (char_length(change_summary) between 1 and 1000),
  created_by uuid references public.profiles (id) on delete set null,
  instructions text check (char_length(instructions) between 1 and 5000),
  desired_outcome text check (char_length(desired_outcome) between 1 and 5000),
  audience text check (char_length(audience) between 1 and 5000),
  core_message text check (char_length(core_message) between 1 and 5000),
  brand_constraints text check (char_length(brand_constraints) between 1 and 5000),
  mandatory_content text check (char_length(mandatory_content) between 1 and 5000),
  prohibited_content text check (char_length(prohibited_content) between 1 and 5000),
  requires_reacknowledgement boolean not null default false,
  deliverables jsonb not null default '[]'::jsonb check (jsonb_typeof(deliverables) = 'array'),
  "references" jsonb not null default '[]'::jsonb check (jsonb_typeof("references") = 'array'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint brief_versions_project_version_key unique (project_id, version)
);
create index brief_versions_created_by_idx on public.brief_versions (created_by);
create trigger brief_versions_set_updated_at
  before update on public.brief_versions
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- Live deliverables and references (the version snapshot is the history)
-- ---------------------------------------------------------------------------
create table public.project_deliverables (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 200),
  format text check (char_length(format) between 1 and 100),
  resolution text check (char_length(resolution) between 1 and 50),
  aspect_ratio text check (char_length(aspect_ratio) between 1 and 20),
  duration_seconds int check (duration_seconds >= 0),
  notes text check (char_length(notes) between 1 and 2000),
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index project_deliverables_project_idx on public.project_deliverables (project_id, sort_order);
create trigger project_deliverables_set_updated_at
  before update on public.project_deliverables
  for each row execute function private.set_updated_at();

-- KB §4.2. Pulled forward from Phase 5; admin-only here. Links only, no uploads.
create table public.project_references (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  title text check (char_length(title) between 1 and 200),
  url text not null check (url ~ '^https://[^\s]+$' and char_length(url) <= 2048),
  start_seconds int check (start_seconds >= 0),
  end_seconds int check (end_seconds >= 0),
  observation_notes text check (char_length(observation_notes) between 1 and 2000),
  priority public.reference_priority not null default 'optional',
  category text check (char_length(category) between 1 and 60),
  access_notes text check (char_length(access_notes) between 1 and 1000),
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint project_references_timecodes_chk check (
    start_seconds is null or end_seconds is null or end_seconds >= start_seconds)
);
create index project_references_project_idx on public.project_references (project_id, sort_order);
create trigger project_references_set_updated_at
  before update on public.project_references
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS and privileges: admin select only, no direct writes for anyone
-- ---------------------------------------------------------------------------
alter table public.clients enable row level security;
alter table public.projects enable row level security;
alter table public.project_internal enable row level security;
alter table public.brief_versions enable row level security;
alter table public.project_deliverables enable row level security;
alter table public.project_references enable row level security;

revoke all on public.clients, public.projects, public.project_internal, public.brief_versions,
  public.project_deliverables, public.project_references from anon, authenticated;
grant select on public.clients, public.projects, public.project_internal, public.brief_versions,
  public.project_deliverables, public.project_references to authenticated;

create policy clients_select_admin on public.clients
  for select to authenticated using ((select private.is_admin()));
create policy projects_select_admin on public.projects
  for select to authenticated using ((select private.is_admin()));
create policy project_internal_select_admin on public.project_internal
  for select to authenticated using ((select private.is_admin()));
create policy brief_versions_select_admin on public.brief_versions
  for select to authenticated using ((select private.is_admin()));
create policy project_deliverables_select_admin on public.project_deliverables
  for select to authenticated using ((select private.is_admin()));
create policy project_references_select_admin on public.project_references
  for select to authenticated using ((select private.is_admin()));

-- ---------------------------------------------------------------------------
-- Guard triggers (hold for every caller, including the table owner)
-- ---------------------------------------------------------------------------
create function private.guard_first_opened_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.first_opened_at is not null
     and new.first_opened_at is distinct from old.first_opened_at then
    raise exception 'The date a project was first opened cannot be changed.' using errcode = 'ES409';
  end if;
  return new;
end;
$$;

create trigger projects_guard_first_opened_at
  before update on public.projects
  for each row execute function private.guard_first_opened_at();

-- Delete is always refused. Update is allowed only for the pre-open, in-place edit of version 1
-- (project never opened), and never changes which project or version a row is.
create function private.guard_brief_versions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Brief versions cannot be deleted.' using errcode = 'ES409';
  end if;
  if new.project_id <> old.project_id or new.version <> old.version or old.version <> 1 then
    raise exception 'Brief versions cannot be changed.' using errcode = 'ES409';
  end if;
  if exists (select 1 from public.projects p
             where p.id = old.project_id and p.first_opened_at is not null) then
    raise exception 'This brief version belongs to an opened project and cannot be changed.'
      using errcode = 'ES409';
  end if;
  return new;
end;
$$;

create trigger brief_versions_guard
  before update or delete on public.brief_versions
  for each row execute function private.guard_brief_versions();

-- ---------------------------------------------------------------------------
-- Audit: project creation and status changes (no personal data in details)
-- ---------------------------------------------------------------------------
-- Details hold status names only (spec §7); free-text status notes are not stored in Phase 4.
create function private.audit_projects()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_details jsonb;
begin
  if tg_op = 'INSERT' or old.status is distinct from new.status then
    v_details := jsonb_build_object(
      'from', case when tg_op = 'INSERT' then null else old.status end,
      'to', new.status);
    insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
    values (
      (select p.id from public.profiles p where p.id = (select auth.uid())),
      case when tg_op = 'INSERT' then 'project.created' else 'project.' || new.status::text end,
      'project',
      new.id::text,
      v_details);
  end if;
  return new;
end;
$$;

create trigger projects_audit
  after insert or update of status on public.projects
  for each row execute function private.audit_projects();

revoke all on function private.guard_first_opened_at(), private.guard_brief_versions(),
  private.audit_projects() from public, anon, authenticated;
