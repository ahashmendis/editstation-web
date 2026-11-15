-- Phase 12C (2/4): client billing schema. Spec docs/superpowers/specs/2026-11-15-phase12-commercial-terms-design.md
-- §4.2, §5, calls 3, 4, 7, 9. Owner decisions KB9, KB9a-2, KB9b.
-- client_milestones is admin-only client money: editors never read it (they see only a derived
-- "client deposit verified" flag through the assignment gate). No write grants: every write goes
-- through security definer functions, and the guard trigger holds for the table owner too.
-- app_settings holds admin settings; 12C adds the business timezone (call 4).

-- ---------------------------------------------------------------------------
-- app_settings (admin-only). One row per known key; values are validated by the setter.
-- ---------------------------------------------------------------------------
create table public.app_settings (
  key text primary key check (key in ('business_timezone')),
  value jsonb not null,
  updated_by uuid references public.profiles (id) on delete set null,
  updated_at timestamptz not null default now()
);
create index app_settings_updated_by_idx on public.app_settings (updated_by);
create trigger app_settings_set_updated_at
  before update on public.app_settings
  for each row execute function private.set_updated_at();

alter table public.app_settings enable row level security;
revoke all on public.app_settings from anon, authenticated;
grant select on public.app_settings to authenticated;
create policy app_settings_select_admin on public.app_settings
  for select to authenticated using ((select private.is_admin()));

-- Call 4 default (owner to confirm): Asia/Colombo.
insert into public.app_settings (key, value) values ('business_timezone', to_jsonb('Asia/Colombo'::text));

-- The business timezone used for every "calendar day" comparison; falls back to Asia/Colombo.
create function private.business_timezone()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select s.value #>> '{}' from public.app_settings s
     where s.key = 'business_timezone' and exists (select 1 from pg_catalog.pg_timezone_names z
                                                    where z.name = s.value #>> '{}')),
    'Asia/Colombo');
$$;

-- The calendar date of an instant in the business timezone.
create function private.business_date(p_at timestamptz)
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select (p_at at time zone private.business_timezone())::date;
$$;

-- ---------------------------------------------------------------------------
-- client_milestones
-- ---------------------------------------------------------------------------
create type public.client_milestone_kind as enum ('deposit', 'balance', 'extra_work', 'refund');
create type public.client_verification_status as enum ('expected', 'received_unverified', 'verified');

create table public.client_milestones (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  -- The agreed terms the milestone was computed from.
  terms_id uuid not null references public.project_terms (id) on delete restrict,
  seq smallint not null check (seq between 1 and 100),
  kind public.client_milestone_kind not null,
  -- Share of the client price this row was computed from (deposit/balance only); recorded with
  -- the row so a per-project split (e.g. 100% upfront) stays auditable.
  share_percent smallint check (share_percent between 1 and 100),
  amount numeric(12, 2) not null,
  currency char(3) not null check (currency ~ '^[A-Z]{3}$'),
  invoice_issued_at timestamptz,
  due_date date,
  received_at timestamptz,
  transfer_reference text check (char_length(transfer_reference) between 1 and 120),
  verification_status public.client_verification_status not null default 'expected',
  verified_by uuid references public.profiles (id) on delete set null,
  verified_at timestamptz,
  -- Refunds are negative rows reversing a received row (like payment reversals).
  reverses_id uuid references public.client_milestones (id) on delete restrict,
  -- Set while the project is on the unpaid-deposit hold (KB9a-2); cleared when the hold is
  -- released (extension or manual resume). auto_held_for_due records the due date the rule acted
  -- on, so it acts at most once per due date even after a manual release.
  auto_held_at timestamptz,
  auto_held_for_due date,
  -- Latest admin reasons (audit rows hold field names only).
  due_change_reason text check (char_length(due_change_reason) between 1 and 2000),
  correction_reason text check (char_length(correction_reason) between 1 and 2000),
  -- Replaced before invoicing (e.g. the client price changed before work began).
  voided_at timestamptz,
  voided_by uuid references public.profiles (id) on delete set null,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint client_milestones_amount_chk check (
    (kind = 'refund' and amount < 0 and reverses_id is not null and share_percent is null)
    or (kind <> 'refund' and amount > 0 and reverses_id is null)),
  constraint client_milestones_share_chk check (
    (kind in ('deposit', 'balance')) = (share_percent is not null)),
  constraint client_milestones_received_chk check (
    (verification_status = 'expected') = (received_at is null)
    and (verification_status = 'expected' or transfer_reference is not null)),
  constraint client_milestones_verified_chk check (
    (verification_status = 'verified') = (verified_at is not null)),
  constraint client_milestones_invoice_chk check (
    invoice_issued_at is not null or (due_date is null and auto_held_at is null and auto_held_for_due is null)),
  constraint client_milestones_voided_chk check (
    voided_at is null or (verification_status = 'expected' and invoice_issued_at is null))
);
create unique index client_milestones_seq_key on public.client_milestones (project_id, seq) where voided_at is null;
create unique index client_milestones_one_deposit_key on public.client_milestones (project_id)
  where kind = 'deposit' and voided_at is null;
create index client_milestones_terms_idx on public.client_milestones (terms_id);
create index client_milestones_reverses_idx on public.client_milestones (reverses_id);
create index client_milestones_verified_by_idx on public.client_milestones (verified_by);
create index client_milestones_voided_by_idx on public.client_milestones (voided_by);
create index client_milestones_created_by_idx on public.client_milestones (created_by);
-- The timed rule scans unverified, invoiced deposits.
create index client_milestones_open_deposit_idx on public.client_milestones (due_date)
  where kind = 'deposit' and voided_at is null and verification_status <> 'verified';
create trigger client_milestones_set_updated_at
  before update on public.client_milestones
  for each row execute function private.set_updated_at();

-- RLS: admin select only; no write grants for any API role. Editors and anon read nothing.
alter table public.client_milestones enable row level security;
revoke all on public.client_milestones from anon, authenticated;
grant select on public.client_milestones to authenticated;
create policy client_milestones_select_admin on public.client_milestones
  for select to authenticated using ((select private.is_admin()));

-- ---------------------------------------------------------------------------
-- Guard (every caller, including the table owner)
-- Delete: never. Insert: a refund reverses a received row of the same project and currency, and
-- refunds never exceed it. Update: identity and money columns are fixed; status moves
-- expected -> received_unverified -> verified; verified is final except through the audited
-- correction function (transaction-local flag naming the row); a voided row is frozen.
-- ---------------------------------------------------------------------------
create function private.guard_client_milestones()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_orig public.client_milestones;
  v_old jsonb;
  v_new jsonb;
begin
  if tg_op = 'DELETE' then
    raise exception 'Client milestones cannot be deleted.' using errcode = 'ES409';
  end if;

  if tg_op = 'INSERT' then
    if new.verification_status <> 'expected' or new.invoice_issued_at is not null or new.voided_at is not null
       or new.auto_held_at is not null or new.auto_held_for_due is not null then
      raise exception 'A client milestone starts as expected.' using errcode = 'ES409';
    end if;
    if not exists (select 1 from public.project_terms t where t.id = new.terms_id and t.project_id = new.project_id) then
      raise exception 'A client milestone must belong to its project''s terms.' using errcode = 'ES409';
    end if;
    if new.kind = 'refund' then
      select * into v_orig from public.client_milestones where id = new.reverses_id for update;
      if v_orig.id is null or v_orig.project_id <> new.project_id or v_orig.kind = 'refund'
         or v_orig.verification_status = 'expected' or v_orig.currency <> new.currency then
        raise exception 'A refund must reverse a received payment of the same project and currency.'
          using errcode = 'ES409';
      end if;
      if v_orig.amount + new.amount + coalesce((select sum(r.amount) from public.client_milestones r
                                                where r.reverses_id = v_orig.id), 0) < 0 then
        raise exception 'Refunds cannot exceed the payment they reverse.' using errcode = 'ES409';
      end if;
    end if;
    return new;
  end if;

  v_old := to_jsonb(old) - 'updated_at';
  v_new := to_jsonb(new) - 'updated_at';
  -- on delete set null of an actor column, everything else unchanged.
  if (v_old ->> 'verified_by' is not null and v_new ->> 'verified_by' is null
      and (v_new - 'verified_by') = (v_old - 'verified_by'))
     or (v_old ->> 'voided_by' is not null and v_new ->> 'voided_by' is null
      and (v_new - 'voided_by') = (v_old - 'voided_by'))
     or (v_old ->> 'created_by' is not null and v_new ->> 'created_by' is null
      and (v_new - 'created_by') = (v_old - 'created_by')) then
    return new;
  end if;

  if (new.id, new.project_id, new.terms_id, new.seq, new.kind, new.share_percent, new.amount, new.currency,
      new.reverses_id, new.created_by, new.created_at)
     is distinct from
     (old.id, old.project_id, old.terms_id, old.seq, old.kind, old.share_percent, old.amount, old.currency,
      old.reverses_id, old.created_by, old.created_at) then
    raise exception 'A client milestone''s amount and identity cannot change.' using errcode = 'ES409';
  end if;
  if old.voided_at is not null then
    raise exception 'A replaced client milestone cannot change.' using errcode = 'ES409';
  end if;
  if old.invoice_issued_at is not null and new.invoice_issued_at is distinct from old.invoice_issued_at then
    raise exception 'The invoice date cannot change once issued.' using errcode = 'ES409';
  end if;

  if old.verification_status = 'verified' then
    if new.verification_status = 'verified'
       and (new.received_at, new.transfer_reference, new.verified_by, new.verified_at)
           is not distinct from (old.received_at, old.transfer_reference, old.verified_by, old.verified_at) then
      return new;  -- e.g. auto-hold or due-date fields on a verified row are not money facts
    end if;
    if coalesce(current_setting('es.client_milestone_correction', true), '') <> old.id::text
       or new.verification_status <> 'received_unverified' then
      raise exception 'A verified client payment is final.' using errcode = 'ES409';
    end if;
    return new;
  end if;

  if not (new.verification_status = old.verification_status
          or (old.verification_status = 'expected' and new.verification_status = 'received_unverified')
          or (old.verification_status = 'received_unverified' and new.verification_status = 'verified')) then
    raise exception 'This client payment cannot move to that status.' using errcode = 'ES409';
  end if;
  return new;
end;
$$;

create trigger client_milestones_guard
  before insert or update or delete on public.client_milestones
  for each row execute function private.guard_client_milestones();

revoke all on function private.business_timezone(), private.business_date(timestamptz),
  private.guard_client_milestones()
from public, anon, authenticated;
