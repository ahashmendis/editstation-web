-- Phase 12E (2/3): payout details schema, LOCKED. Spec docs/superpowers/specs/2026-11-15-phase12-commercial-terms-design.md
-- §4.8 and call 1; owner decision E (2026-11-11, go-ahead 2026-11-15); SECURITY_AND_PRIVACY S10.
--
-- Real bank details must not be stored until counsel confirms PDPA handling. The app_settings flag
-- payout_details_enabled starts false; while false every payout write function refuses and a guard
-- trigger refuses any insert, so no row can exist. Only an admin function changes the flag.
--
-- editor_payout_details, editor_payout_detail_versions and editor_payout_attestations have NO
-- grants to anon or authenticated (RLS on, no policies): every read and write goes through the
-- security definer functions in the next migration. No field-level encryption in this slice (see
-- SECURITY_AND_PRIVACY S10). Audit rows never contain bank values.

-- ---------------------------------------------------------------------------
-- The flag (admin setting, default false)
-- ---------------------------------------------------------------------------
alter table public.app_settings drop constraint app_settings_key_check;
alter table public.app_settings add constraint app_settings_key_check
  check (key in ('business_timezone', 'payout_details_enabled'));
insert into public.app_settings (key, value) values ('payout_details_enabled', 'false'::jsonb);

-- True only when the setting is exactly JSON true; a missing or malformed row reads as false.
create function private.payout_details_enabled()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select s.value = 'true'::jsonb from public.app_settings s
                   where s.key = 'payout_details_enabled'), false);
$$;

-- Notifications about an editor's payout details point at the editor.
alter table public.notifications drop constraint notifications_entity_type_check;
alter table public.notifications add constraint notifications_entity_type_check
  check (entity_type in ('client_inquiry', 'editor_application', 'project', 'payment', 'editor_profile'));

-- ---------------------------------------------------------------------------
-- editor_payout_details: the current details, one row per editor
-- ---------------------------------------------------------------------------
create type public.payout_verification_status as enum ('unverified', 'verified');

create table public.editor_payout_details (
  editor_id uuid primary key references public.editor_profiles (user_id) on delete cascade,
  account_holder text not null check (char_length(account_holder) between 1 and 120),
  bank text not null check (char_length(bank) between 1 and 120),
  branch text not null check (char_length(branch) between 1 and 120),
  account_number text not null check (account_number ~ '^[A-Za-z0-9 -]{6,34}$'
    and char_length(regexp_replace(account_number, '[^A-Za-z0-9]', '', 'g')) >= 6),
  version int not null check (version >= 1),
  verification_status public.payout_verification_status not null default 'unverified',
  verified_by uuid references public.profiles (id) on delete set null,
  verified_at timestamptz,
  verified_method text check (verified_method in ('phone', 'in_person', 'other')),
  verification_note text check (char_length(verification_note) between 1 and 500),
  last_changed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  -- verified_by may be cleared by on delete set null; the rest travels with the status.
  constraint editor_payout_details_verification check (
    (verification_status = 'verified') = (verified_at is not null and verified_method is not null)
    and (verification_status = 'verified' or (verified_by is null and verification_note is null)))
);
create index editor_payout_details_verified_by_idx on public.editor_payout_details (verified_by);
comment on table public.editor_payout_details is
  'Editor payout (bank) details. LOCKED until payout_details_enabled. No API grants: functions only. Never log values.';

-- ---------------------------------------------------------------------------
-- editor_payout_detail_versions: append-only full history of every saved version
-- ---------------------------------------------------------------------------
create table public.editor_payout_detail_versions (
  id uuid primary key default gen_random_uuid(),
  editor_id uuid not null references public.editor_profiles (user_id) on delete cascade,
  version int not null check (version >= 1),
  account_holder text not null check (char_length(account_holder) between 1 and 120),
  bank text not null check (char_length(bank) between 1 and 120),
  branch text not null check (char_length(branch) between 1 and 120),
  account_number text not null check (account_number ~ '^[A-Za-z0-9 -]{6,34}$'
    and char_length(regexp_replace(account_number, '[^A-Za-z0-9]', '', 'g')) >= 6),
  changed_by uuid references public.profiles (id) on delete set null,
  changed_at timestamptz not null default now(),
  unique (editor_id, version)
);
create index editor_payout_detail_versions_changed_by_idx on public.editor_payout_detail_versions (changed_by);
comment on table public.editor_payout_detail_versions is
  'Append-only history of editor payout details. No API grants: functions only. Never log values.';

-- ---------------------------------------------------------------------------
-- editor_payout_attestations (call 1): "payout account verified outside the app", admin and date,
-- no bank data. Append-only. Counts only while payout_details_enabled is false.
-- ---------------------------------------------------------------------------
create table public.editor_payout_attestations (
  id uuid primary key default gen_random_uuid(),
  editor_id uuid not null references public.editor_profiles (user_id) on delete cascade,
  note text not null check (char_length(note) between 1 and 500),
  attested_by uuid references public.profiles (id) on delete set null,
  attested_at timestamptz not null default now()
);
create index editor_payout_attestations_editor_idx on public.editor_payout_attestations (editor_id, attested_at desc);
create index editor_payout_attestations_attested_by_idx on public.editor_payout_attestations (attested_by);
comment on table public.editor_payout_attestations is
  'Interim attestations that an editor''s payout account was verified outside the app. No bank data. No API grants.';

-- ---------------------------------------------------------------------------
-- Guards (hold for the table owner too)
-- ---------------------------------------------------------------------------
-- Current details: no row while the flag is off (an insert starts unverified); the editor never
-- moves; a content change is exactly the next version and resets verification; otherwise the
-- version stays (verification may be recorded).
create function private.guard_editor_payout_details()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    return old;
  end if;
  if tg_op = 'INSERT' then
    if not private.payout_details_enabled() then
      raise exception 'Payout details are not enabled yet.' using errcode = 'ES409';
    end if;
    if new.verification_status <> 'unverified' then
      raise exception 'New payout details start unverified.' using errcode = 'ES409';
    end if;
    return new;
  end if;
  if new.editor_id <> old.editor_id then
    raise exception 'Payout details cannot move to another editor.' using errcode = 'ES409';
  end if;
  if (new.account_holder, new.bank, new.branch, new.account_number)
     is distinct from (old.account_holder, old.bank, old.branch, old.account_number) then
    if not private.payout_details_enabled() then
      raise exception 'Payout details are not enabled yet.' using errcode = 'ES409';
    end if;
    if new.version <> old.version + 1 or new.verification_status <> 'unverified' then
      raise exception 'A change to payout details must be the next version and unverified.' using errcode = 'ES409';
    end if;
  elsif new.version <> old.version then
    raise exception 'The payout details version only moves forward with a change.' using errcode = 'ES409';
  end if;
  return new;
end;
$$;

create trigger editor_payout_details_guard
  before insert or update or delete on public.editor_payout_details
  for each row execute function private.guard_editor_payout_details();

-- Append-only tables: insert (versions: next version, flag on), never update or delete, except
-- the actor column cleared by on delete set null and the cascade from deleting the editor.
create function private.guard_payout_append_only()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor text := case tg_table_name when 'editor_payout_detail_versions' then 'changed_by' else 'attested_by' end;
begin
  if tg_op = 'INSERT' then
    if tg_table_name = 'editor_payout_detail_versions' then
      if not private.payout_details_enabled() then
        raise exception 'Payout details are not enabled yet.' using errcode = 'ES409';
      end if;
      if new.version <> coalesce((select max(v.version) from public.editor_payout_detail_versions v
                                  where v.editor_id = new.editor_id), 0) + 1 then
        raise exception 'Payout details must be added as the next version.' using errcode = 'ES409';
      end if;
    end if;
    return new;
  end if;
  if tg_op = 'DELETE' then
    if not exists (select 1 from public.editor_profiles e where e.user_id = old.editor_id) then
      return old;
    end if;
    raise exception 'This history cannot be deleted.' using errcode = 'ES409';
  end if;
  if to_jsonb(old) ->> v_actor is not null and to_jsonb(new) ->> v_actor is null
     and (to_jsonb(new) - v_actor) = (to_jsonb(old) - v_actor) then
    return new;
  end if;
  raise exception 'This history cannot be changed.' using errcode = 'ES409';
end;
$$;

create trigger editor_payout_detail_versions_guard
  before insert or update or delete on public.editor_payout_detail_versions
  for each row execute function private.guard_payout_append_only();
create trigger editor_payout_attestations_guard
  before insert or update or delete on public.editor_payout_attestations
  for each row execute function private.guard_payout_append_only();

-- ---------------------------------------------------------------------------
-- RLS on, default deny, no API grants and no policies (functions only)
-- ---------------------------------------------------------------------------
alter table public.editor_payout_details enable row level security;
alter table public.editor_payout_detail_versions enable row level security;
alter table public.editor_payout_attestations enable row level security;
revoke all on public.editor_payout_details, public.editor_payout_detail_versions,
  public.editor_payout_attestations from public, anon, authenticated;

revoke all on function private.payout_details_enabled(), private.guard_editor_payout_details(),
  private.guard_payout_append_only()
from public, anon, authenticated;
