-- Phase 9 (1/3): payments and admin payment notes. Spec
-- docs/superpowers/specs/2026-11-14-phase9-earnings-design.md §5-§7; decision I.
-- Select-only grants and one combined select policy per table. Every write is a public.admin_*
-- security definer function or a private trigger. The guards hold for the table owner too.
-- payments holds no client data, client price or admin notes; editors still read it only through
-- public.editor_list_payments() so admin actor ids stay hidden.

create type public.payment_status as enum (
  'not_due', 'pending_approval', 'approved', 'processing', 'paid', 'on_hold');
create type public.payment_kind as enum ('assignment', 'reversal');

-- ---------------------------------------------------------------------------
-- payments
-- ---------------------------------------------------------------------------
create table public.payments (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments (id) on delete restrict,
  project_id uuid not null references public.projects (id) on delete restrict,
  editor_id uuid not null references public.editor_profiles (user_id) on delete restrict,
  kind public.payment_kind not null default 'assignment',
  amount numeric(12, 2) not null,
  currency char(3) not null check (currency ~ '^[A-Z]{3}$'),
  status public.payment_status not null default 'not_due',
  held_from_status public.payment_status,
  on_hold_reason text check (char_length(on_hold_reason) between 1 and 500),
  due_date date,
  transfer_date date,
  transaction_reference text check (char_length(transaction_reference) between 1 and 120),
  reverses_payment_id uuid references public.payments (id) on delete restrict,
  reversal_reason text check (char_length(reversal_reason) between 1 and 500),
  approved_by uuid references public.profiles (id) on delete set null,
  approved_at timestamptz,
  marked_paid_by uuid references public.profiles (id) on delete set null,
  marked_paid_at timestamptz,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payments_amount_chk check (
    (kind = 'assignment' and amount > 0) or (kind = 'reversal' and amount < 0)),
  constraint payments_hold_chk check (
    (status = 'on_hold') = (held_from_status is not null)
    and (status = 'on_hold') = (on_hold_reason is not null)
    and (held_from_status is null or held_from_status not in ('on_hold', 'paid'))),
  constraint payments_approved_chk check (
    kind <> 'assignment'
    or not (status in ('approved', 'processing', 'paid')
            or coalesce(held_from_status in ('approved', 'processing'), false))
    or approved_at is not null),
  constraint payments_paid_chk check (
    status <> 'paid'
    or (marked_paid_at is not null
        and (kind <> 'assignment' or (transaction_reference is not null and transfer_date is not null)))),
  constraint payments_reversal_chk check (
    (kind = 'reversal') = (reverses_payment_id is not null)
    and (kind = 'reversal') = (reversal_reason is not null)
    and (kind <> 'reversal' or status = 'paid'))
);
-- At most one unpaid assignment payment per assignment; one reversal per payment.
create unique index payments_open_key on public.payments (assignment_id)
  where kind = 'assignment' and status <> 'paid';
create unique index payments_reverses_key on public.payments (reverses_payment_id);
create index payments_assignment_idx on public.payments (assignment_id);
create index payments_editor_idx on public.payments (editor_id, created_at desc);
create index payments_project_idx on public.payments (project_id);
create index payments_status_idx on public.payments (status);
create index payments_approved_by_idx on public.payments (approved_by);
create index payments_marked_paid_by_idx on public.payments (marked_paid_by);
create index payments_created_by_idx on public.payments (created_by);
create trigger payments_set_updated_at
  before update on public.payments
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- payment_notes: admin-only, append-only (KB §8.2 internal notes; mirrors project_notes)
-- ---------------------------------------------------------------------------
create table public.payment_notes (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.payments (id) on delete restrict,
  author_id uuid references public.profiles (id) on delete set null,
  note text not null check (char_length(note) between 1 and 4000),
  created_at timestamptz not null default now()
);
create index payment_notes_payment_idx on public.payment_notes (payment_id, created_at desc);
create index payment_notes_author_idx on public.payment_notes (author_id);
create trigger payment_notes_append_only
  before update or delete on public.payment_notes
  for each row execute function private.guard_append_only('author_id');

-- ---------------------------------------------------------------------------
-- RLS and privileges
-- ---------------------------------------------------------------------------
alter table public.payments enable row level security;
alter table public.payment_notes enable row level security;

revoke all on public.payments, public.payment_notes from anon, authenticated;
grant select on public.payments, public.payment_notes to authenticated;

-- Admin-only: rows carry actor ids (approved_by, marked_paid_by, created_by). Editors read their
-- own payments only through public.editor_list_payments(), which omits those columns.
create policy payments_select on public.payments
  for select to authenticated
  using ((select private.is_admin()));
create policy payment_notes_select on public.payment_notes
  for select to authenticated using ((select private.is_admin()));

-- ---------------------------------------------------------------------------
-- Lifecycle (spec §7). on_hold -> held_from_status is checked by the guard, which knows the row.
-- ---------------------------------------------------------------------------
create function private.payment_transition_allowed(p_from public.payment_status, p_to public.payment_status)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select coalesce(case
    when p_from = 'not_due' then p_to in ('pending_approval', 'on_hold')
    when p_from = 'pending_approval' then p_to in ('approved', 'on_hold')
    when p_from = 'approved' then p_to in ('processing', 'paid', 'on_hold')
    when p_from = 'processing' then p_to in ('paid', 'on_hold')
    else false
  end, false);
$$;

-- ---------------------------------------------------------------------------
-- Insert guard: the row matches its assignment; a reversal matches the paid row it reverses.
-- ---------------------------------------------------------------------------
create function private.check_payment_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_assignment public.assignments;
  v_original public.payments;
begin
  select * into v_assignment from public.assignments where id = new.assignment_id;
  if not found or v_assignment.project_id <> new.project_id or v_assignment.editor_id <> new.editor_id then
    raise exception 'A payment must match its assignment.' using errcode = 'ES409';
  end if;
  if new.kind = 'assignment' then
    if v_assignment.confirmed_at is null then
      raise exception 'A payment needs a confirmed assignment.' using errcode = 'ES409';
    end if;
    if new.amount is distinct from v_assignment.agreed_amount
       or new.currency is distinct from v_assignment.agreed_currency then
      raise exception 'A payment must be for the agreed amount.' using errcode = 'ES409';
    end if;
  elsif new.kind = 'reversal' then
    select * into v_original from public.payments where id = new.reverses_payment_id;
    if not found or v_original.kind <> 'assignment' or v_original.status <> 'paid'
       or v_original.assignment_id <> new.assignment_id then
      raise exception 'Only a paid payment can be reversed.' using errcode = 'ES409';
    end if;
    if new.amount <> -v_original.amount or new.currency <> v_original.currency then
      raise exception 'A reversal must be for the whole paid amount.' using errcode = 'ES409';
    end if;
  end if;
  return new;
end;
$$;

create trigger payments_check_row
  before insert on public.payments
  for each row execute function private.check_payment_row();

-- ---------------------------------------------------------------------------
-- Update/delete guard (spec §5). updated_at is maintained by its own trigger and ignored here.
-- ---------------------------------------------------------------------------
create function private.guard_payments()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actors text[] := array['approved_by', 'marked_paid_by', 'created_by'];
  v_col text;
begin
  if tg_op = 'DELETE' then
    raise exception 'Payments cannot be deleted.' using errcode = 'ES409';
  end if;

  if old.status = 'paid' then
    -- Only clearing actor columns (on delete set null) with every other column unchanged.
    if (to_jsonb(new) - v_actors - 'updated_at') <> (to_jsonb(old) - v_actors - 'updated_at') then
      raise exception 'This payment has been paid and cannot be changed.' using errcode = 'ES409';
    end if;
    foreach v_col in array v_actors loop
      if (to_jsonb(new) ->> v_col) is distinct from (to_jsonb(old) ->> v_col)
         and (to_jsonb(new) ->> v_col) is not null then
        raise exception 'This payment has been paid and cannot be changed.' using errcode = 'ES409';
      end if;
    end loop;
    return new;
  end if;

  if (new.assignment_id, new.project_id, new.editor_id, new.kind, new.amount, new.currency,
      new.reverses_payment_id, new.reversal_reason, new.created_at)
     is distinct from
     (old.assignment_id, old.project_id, old.editor_id, old.kind, old.amount, old.currency,
      old.reverses_payment_id, old.reversal_reason, old.created_at)
     or (new.created_by is distinct from old.created_by and new.created_by is not null) then
    raise exception 'This part of a payment cannot change.' using errcode = 'ES409';
  end if;

  if new.status is distinct from old.status then
    if old.status = 'on_hold' then
      if new.status is distinct from old.held_from_status then
        raise exception 'This payment cannot move from on hold to %.', replace(new.status::text, '_', ' ')
          using errcode = 'ES409';
      end if;
    elsif not private.payment_transition_allowed(old.status, new.status) then
      raise exception 'This payment cannot move from % to %.',
        replace(old.status::text, '_', ' '), replace(new.status::text, '_', ' ')
        using errcode = 'ES409';
    elsif new.status = 'on_hold' and new.held_from_status is distinct from old.status then
      raise exception 'A hold must return to the status it came from.' using errcode = 'ES409';
    end if;
  end if;
  return new;
end;
$$;

create trigger payments_guard
  before update or delete on public.payments
  for each row execute function private.guard_payments();

-- ---------------------------------------------------------------------------
-- Audit (ids and enum names only: never amounts, references, reasons, notes or dates)
-- ---------------------------------------------------------------------------
create function private.audit_payments()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_action text;
  v_from public.payment_status;
  v_to public.payment_status;
begin
  if tg_op = 'INSERT' then
    v_action := case when new.kind = 'reversal' then 'payment.reversed' else 'payment.created' end;
    v_to := new.status;
  elsif new.status is distinct from old.status then
    v_action := case when old.status = 'on_hold' then 'payment.hold_released' else 'payment.' || new.status::text end;
    v_from := old.status;
    v_to := new.status;
  elsif new.due_date is distinct from old.due_date then
    v_action := 'payment.due_date_set';
  else
    return new;
  end if;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (
    (select p.id from public.profiles p where p.id = (select auth.uid())),
    v_action,
    'payment',
    coalesce(new.reverses_payment_id, new.id)::text,
    jsonb_build_object('payment_id', new.id, 'assignment_id', new.assignment_id, 'from', v_from, 'to', v_to));
  return new;
end;
$$;

create trigger payments_audit
  after insert or update of status, due_date on public.payments
  for each row execute function private.audit_payments();

revoke all on function
  private.payment_transition_allowed(public.payment_status, public.payment_status),
  private.check_payment_row(), private.guard_payments(), private.audit_payments()
from public, anon, authenticated;
