-- Phase 12D part 2 (3/5): extra pay offers, scope quotes, cancellation settlements and the payment
-- changes they need. Spec docs/superpowers/specs/2026-11-15-phase12-commercial-terms-design.md
-- §4.3 (cancelled), §4.4, §4.6, calls 2, 5, 6; decisions F, F2 (a-d), KB9a-3, Phase 12 principles.
--
-- New admin-only tables (RLS on, select for admins only, no write grants; every write is a
-- security definer function and the guards hold for the table owner too):
--   compensation_adjustments  extra editor pay offered by an admin and answered by the editor;
--                             holds editor pay only (editors read their own rows through
--                             public.editor_list_adjustments, which omits admin ids)
--   scope_change_quotes       the client quote for a scope change (client money)
--   cancellation_settlements  one per cancelled project: the stage, the schedule percentages, the
--                             editor and client figures (client money)
-- payments: adjustment_id / settlement_id lines (milestone_seq is null on them), the cancelled
-- status (final; only a settlement sets it), partial reversals for a settlement's overpayment.
-- revision_requests.adjustment_required; client_milestones links to a quote, an extra round or
-- a settlement.

create type public.adjustment_kind as enum ('extra_round', 'scope_change', 'cancellation');
create type public.adjustment_status as enum ('offered', 'accepted', 'declined', 'withdrawn');
create type public.scope_quote_status as enum ('drafted', 'sent', 'accepted', 'declined');

-- ---------------------------------------------------------------------------
-- scope_change_quotes (admin-only client money)
-- ---------------------------------------------------------------------------
create table public.scope_change_quotes (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  -- The scope-change request this quote prices (type scope_change).
  revision_request_id uuid not null references public.revision_requests (id) on delete restrict,
  description text not null check (char_length(description) between 1 and 4000),
  amount numeric(12, 2) not null check (amount > 0),
  currency char(3) not null check (currency ~ '^[A-Z]{3}$'),
  status public.scope_quote_status not null default 'drafted',
  sent_at timestamptz,
  -- The client's answer, recorded by an admin.
  answered_at timestamptz,
  answered_by uuid references public.profiles (id) on delete set null,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scope_change_quotes_status_chk check (
    (status = 'drafted') = (sent_at is null)
    and (status in ('accepted', 'declined')) = (answered_at is not null))
);
-- One live (not declined) quote per scope-change request.
create unique index scope_change_quotes_open_key on public.scope_change_quotes (revision_request_id)
  where status <> 'declined';
create index scope_change_quotes_project_idx on public.scope_change_quotes (project_id, created_at);
create index scope_change_quotes_revision_idx on public.scope_change_quotes (revision_request_id);
create index scope_change_quotes_answered_by_idx on public.scope_change_quotes (answered_by);
create index scope_change_quotes_created_by_idx on public.scope_change_quotes (created_by);
create trigger scope_change_quotes_set_updated_at
  before update on public.scope_change_quotes
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- compensation_adjustments (editor pay only; the original agreed amount is never edited)
-- ---------------------------------------------------------------------------
create table public.compensation_adjustments (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments (id) on delete restrict,
  project_id uuid not null references public.projects (id) on delete restrict,
  editor_id uuid not null references public.editor_profiles (user_id) on delete restrict,
  kind public.adjustment_kind not null,
  amount numeric(12, 2) not null check (amount > 0),
  currency char(3) not null check (currency ~ '^[A-Z]{3}$'),
  revision_request_id uuid references public.revision_requests (id) on delete restrict,
  scope_quote_id uuid references public.scope_change_quotes (id) on delete restrict,
  status public.adjustment_status not null default 'offered',
  -- Written for the editor (what the extra pay covers).
  note text check (char_length(note) between 1 and 1000),
  offered_by uuid references public.profiles (id) on delete set null,
  offered_at timestamptz not null default now(),
  answered_by uuid references public.profiles (id) on delete set null,
  answered_at timestamptz,
  withdrawn_by uuid references public.profiles (id) on delete set null,
  withdrawn_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint compensation_adjustments_target_chk check (
    (kind = 'extra_round' and revision_request_id is not null and scope_quote_id is null)
    or (kind = 'scope_change' and scope_quote_id is not null and revision_request_id is null)
    or (kind = 'cancellation' and revision_request_id is null and scope_quote_id is null)),
  constraint compensation_adjustments_status_chk check (
    (status in ('accepted', 'declined')) = (answered_at is not null)
    and (status = 'withdrawn') = (withdrawn_at is not null))
);
-- At most one live (offered or accepted) offer per extra round, per scope quote, and one open
-- cancellation offer per assignment.
create unique index compensation_adjustments_round_key on public.compensation_adjustments (revision_request_id)
  where status in ('offered', 'accepted');
create unique index compensation_adjustments_quote_key on public.compensation_adjustments (scope_quote_id)
  where status in ('offered', 'accepted');
create unique index compensation_adjustments_cancel_key on public.compensation_adjustments (assignment_id)
  where kind = 'cancellation' and status = 'offered';
create index compensation_adjustments_assignment_idx on public.compensation_adjustments (assignment_id);
create index compensation_adjustments_project_idx on public.compensation_adjustments (project_id);
create index compensation_adjustments_editor_idx on public.compensation_adjustments (editor_id, offered_at desc);
create index compensation_adjustments_revision_idx on public.compensation_adjustments (revision_request_id);
create index compensation_adjustments_quote_idx on public.compensation_adjustments (scope_quote_id);
create index compensation_adjustments_offered_by_idx on public.compensation_adjustments (offered_by);
create index compensation_adjustments_answered_by_idx on public.compensation_adjustments (answered_by);
create index compensation_adjustments_withdrawn_by_idx on public.compensation_adjustments (withdrawn_by);
create trigger compensation_adjustments_set_updated_at
  before update on public.compensation_adjustments
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- cancellation_settlements (admin-only; append-only). The editor figures are editor pay; the
-- client figures are client money, so editors never read this table.
-- ---------------------------------------------------------------------------
create table public.cancellation_settlements (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null unique references public.projects (id) on delete restrict,
  assignment_id uuid not null references public.assignments (id) on delete restrict,
  terms_id uuid not null references public.project_terms (id) on delete restrict,
  -- The project status at cancellation (on hold from assigned counts as assigned).
  stage public.terms_stage not null,
  editor_earned_percent numeric(5, 2) not null,
  client_charge_percent numeric(5, 2) not null,
  agreed_amount numeric(12, 2) not null,
  editor_currency char(3) not null,
  -- agreed_amount x editor_earned_percent, rounded to cents, plus editor_extra_pay.
  computed_editor_earned numeric(12, 2) not null check (computed_editor_earned >= 0),
  editor_earned numeric(12, 2) not null check (editor_earned >= 0),
  adjustment_reason text check (char_length(adjustment_reason) between 1 and 2000),
  -- Accepted extra pay (extra rounds, scope changes), earned in full; its rows stay as they are.
  editor_extra_pay numeric(12, 2) not null default 0 check (editor_extra_pay >= 0),
  -- Net paid on the milestone rows before the settlement.
  editor_paid_before numeric(12, 2) not null,
  -- Milestone shortfall paid through the settlement row, or milestone overpayment reversed
  -- (recovering the money happens outside the app).
  editor_settlement_amount numeric(12, 2) not null check (editor_settlement_amount >= 0),
  editor_overpayment numeric(12, 2) not null check (editor_overpayment >= 0),
  cancelled_payment_count int not null check (cancelled_payment_count >= 0),
  -- Client side: deposit + balance milestones (the agreed client price), verified money received
  -- net of earlier refunds, the stage charge, the refund recorded, and any amount still owed.
  client_base numeric(12, 2) not null default 0,
  client_currency char(3) check (client_currency ~ '^[A-Z]{3}$'),
  client_received numeric(12, 2) not null default 0,
  client_charge numeric(12, 2) not null default 0,
  client_refund numeric(12, 2) not null default 0 check (client_refund >= 0),
  client_owes numeric(12, 2) not null default 0 check (client_owes >= 0),
  settled_by uuid references public.profiles (id) on delete set null,
  settled_at timestamptz not null default now(),
  constraint cancellation_settlements_reason_chk check (
    editor_earned = computed_editor_earned or adjustment_reason is not null),
  constraint cancellation_settlements_editor_chk check (
    not (editor_settlement_amount > 0 and editor_overpayment > 0)),
  constraint cancellation_settlements_client_chk check (not (client_refund > 0 and client_owes > 0))
);
create index cancellation_settlements_assignment_idx on public.cancellation_settlements (assignment_id);
create index cancellation_settlements_terms_idx on public.cancellation_settlements (terms_id);
create index cancellation_settlements_settled_by_idx on public.cancellation_settlements (settled_by);
create trigger cancellation_settlements_append_only
  before update or delete on public.cancellation_settlements
  for each row execute function private.guard_append_only('settled_by');

-- ---------------------------------------------------------------------------
-- Guards for quotes and adjustments: no delete; identity and money fixed; one answering move.
-- Actor columns may only be cleared (on delete set null) outside that move.
-- ---------------------------------------------------------------------------
create function private.guard_scope_change_quotes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fixed text[] := array['updated_at', 'answered_by', 'created_by'];
  v_moving text[] := array['status', 'sent_at', 'answered_at'];
begin
  if tg_op = 'DELETE' then
    raise exception 'Scope quotes cannot be deleted.' using errcode = 'ES409';
  end if;
  if new.created_by is distinct from old.created_by and new.created_by is not null then
    raise exception 'This part of a scope quote cannot change.' using errcode = 'ES409';
  end if;
  if new.status is distinct from old.status then
    if not ((old.status = 'drafted' and new.status = 'sent')
            or (old.status = 'sent' and new.status in ('accepted', 'declined'))) then
      raise exception 'This scope quote cannot move from % to %.', old.status, new.status using errcode = 'ES409';
    end if;
    if (to_jsonb(new) - v_fixed - v_moving) <> (to_jsonb(old) - v_fixed - v_moving)
       or (new.answered_by is distinct from old.answered_by and old.answered_by is not null) then
      raise exception 'This part of a scope quote cannot change.' using errcode = 'ES409';
    end if;
    return new;
  end if;
  if (to_jsonb(new) - v_fixed) <> (to_jsonb(old) - v_fixed)
     or (new.answered_by is distinct from old.answered_by and new.answered_by is not null) then
    raise exception 'This part of a scope quote cannot change.' using errcode = 'ES409';
  end if;
  return new;
end;
$$;

create trigger scope_change_quotes_guard
  before update or delete on public.scope_change_quotes
  for each row execute function private.guard_scope_change_quotes();

create function private.guard_compensation_adjustments()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actors text[] := array['updated_at', 'offered_by', 'answered_by', 'withdrawn_by'];
  v_moving text[] := array['status', 'answered_at', 'withdrawn_at'];
begin
  if tg_op = 'DELETE' then
    raise exception 'Extra pay offers cannot be deleted.' using errcode = 'ES409';
  end if;
  if new.offered_by is distinct from old.offered_by and new.offered_by is not null then
    raise exception 'This part of an extra pay offer cannot change.' using errcode = 'ES409';
  end if;
  if old.status = 'offered' and new.status <> 'offered' then
    if (to_jsonb(new) - v_actors - v_moving) <> (to_jsonb(old) - v_actors - v_moving) then
      raise exception 'This part of an extra pay offer cannot change.' using errcode = 'ES409';
    end if;
    return new;
  end if;
  if (to_jsonb(new) - v_actors) <> (to_jsonb(old) - v_actors)
     or (new.answered_by is distinct from old.answered_by and new.answered_by is not null)
     or (new.withdrawn_by is distinct from old.withdrawn_by and new.withdrawn_by is not null) then
    raise exception 'This extra pay offer was answered and cannot change.' using errcode = 'ES409';
  end if;
  return new;
end;
$$;

create trigger compensation_adjustments_guard
  before update or delete on public.compensation_adjustments
  for each row execute function private.guard_compensation_adjustments();

-- ---------------------------------------------------------------------------
-- RLS: admin select only for all three; no write grants for any API role.
-- ---------------------------------------------------------------------------
alter table public.scope_change_quotes enable row level security;
alter table public.compensation_adjustments enable row level security;
alter table public.cancellation_settlements enable row level security;
revoke all on public.scope_change_quotes, public.compensation_adjustments, public.cancellation_settlements
from anon, authenticated;
grant select on public.scope_change_quotes, public.compensation_adjustments, public.cancellation_settlements
to authenticated;
create policy scope_change_quotes_select_admin on public.scope_change_quotes
  for select to authenticated using ((select private.is_admin()));
-- Admin-only: rows carry admin actor ids. Editors read their own offers through
-- public.editor_list_adjustments().
create policy compensation_adjustments_select_admin on public.compensation_adjustments
  for select to authenticated using ((select private.is_admin()));
create policy cancellation_settlements_select_admin on public.cancellation_settlements
  for select to authenticated using ((select private.is_admin()));

-- ---------------------------------------------------------------------------
-- revision_requests: the admin's "extra pay must be agreed first" flag (F2 a, d)
-- ---------------------------------------------------------------------------
alter table public.revision_requests add column adjustment_required boolean not null default false;

-- ---------------------------------------------------------------------------
-- client_milestones: what an extra_work row charges for (a scope quote or an extra round) and
-- which settlement a refund row belongs to. Fixed once written.
-- ---------------------------------------------------------------------------
alter table public.client_milestones
  add column scope_quote_id uuid references public.scope_change_quotes (id) on delete restrict,
  add column revision_request_id uuid references public.revision_requests (id) on delete restrict,
  add column settlement_id uuid references public.cancellation_settlements (id) on delete restrict,
  add constraint client_milestones_links_chk check (
    ((scope_quote_id is not null or revision_request_id is not null) <= (kind = 'extra_work'))
    and not (scope_quote_id is not null and revision_request_id is not null)
    and (settlement_id is null or kind = 'refund'));
create unique index client_milestones_quote_key on public.client_milestones (scope_quote_id)
  where voided_at is null and scope_quote_id is not null;
create unique index client_milestones_round_key on public.client_milestones (revision_request_id)
  where voided_at is null and revision_request_id is not null;
create index client_milestones_quote_idx on public.client_milestones (scope_quote_id);
create index client_milestones_revision_idx on public.client_milestones (revision_request_id);
create index client_milestones_settlement_idx on public.client_milestones (settlement_id);

create function private.guard_client_milestone_links()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (new.scope_quote_id, new.revision_request_id, new.settlement_id)
     is distinct from (old.scope_quote_id, old.revision_request_id, old.settlement_id) then
    raise exception 'A client milestone''s amount and identity cannot change.' using errcode = 'ES409';
  end if;
  return new;
end;
$$;

create trigger client_milestones_links_guard
  before update on public.client_milestones
  for each row execute function private.guard_client_milestone_links();

-- ---------------------------------------------------------------------------
-- payments
-- ---------------------------------------------------------------------------
alter table public.payments
  add column adjustment_id uuid references public.compensation_adjustments (id) on delete restrict,
  add column settlement_id uuid references public.cancellation_settlements (id) on delete restrict;
-- Extra lines (accepted extra pay, a settlement's shortfall) are not milestones.
alter table public.payments alter column milestone_seq drop not null;
alter table public.payments
  add constraint payments_line_chk check (
    not (adjustment_id is not null and settlement_id is not null and kind = 'assignment')
    and (kind <> 'assignment'
         or ((milestone_seq is null) = (adjustment_id is not null or settlement_id is not null)
             and (adjustment_id is not null) = coalesce(payable_reason = 'adjustment_accepted', false)
             and (settlement_id is not null) = coalesce(payable_reason = 'cancellation_settlement', false)))),
  drop constraint payments_hold_chk,
  add constraint payments_hold_chk check (
    (status = 'on_hold') = (held_from_status is not null)
    and (status = 'on_hold') = (on_hold_reason is not null)
    and (held_from_status is null or held_from_status not in ('on_hold', 'paid', 'cancelled')));

drop index public.payments_open_key;
-- At most one open row per editor milestone; cancelled rows are closed like paid ones.
create unique index payments_open_key on public.payments (assignment_id, milestone_seq)
  where kind = 'assignment' and status not in ('paid', 'cancelled') and split_from_payment_id is null
    and milestone_seq is not null;
-- At most one open row per accepted offer and per settlement.
create unique index payments_open_adjustment_key on public.payments (adjustment_id)
  where kind = 'assignment' and status not in ('paid', 'cancelled') and adjustment_id is not null;
create unique index payments_open_settlement_key on public.payments (settlement_id)
  where kind = 'assignment' and status not in ('paid', 'cancelled') and settlement_id is not null;
create index payments_adjustment_idx on public.payments (adjustment_id);
create index payments_settlement_idx on public.payments (settlement_id);

-- Insert guard (12D part 1 body, extended): milestone rows (net of reversals, cancelled rows
-- excluded) stay within the agreed amount; an extra pay row stays within its accepted offer; a
-- settlement row within the settlement's shortfall; a reversal matches the paid row it reverses
-- (a settlement may reverse part of a paid row to reconcile an overpayment).
create or replace function private.check_payment_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_assignment public.assignments;
  v_original public.payments;
  v_adj public.compensation_adjustments;
  v_set public.cancellation_settlements;
begin
  select * into v_assignment from public.assignments where id = new.assignment_id;
  if not found or v_assignment.project_id <> new.project_id or v_assignment.editor_id <> new.editor_id then
    raise exception 'A payment must match its assignment.' using errcode = 'ES409';
  end if;
  if new.amount_before_split is not null then
    raise exception 'A payment starts unsplit.' using errcode = 'ES409';
  end if;
  if new.status = 'cancelled' then
    raise exception 'A payment cannot start cancelled.' using errcode = 'ES409';
  end if;
  if new.kind = 'assignment' then
    if v_assignment.confirmed_at is null then
      raise exception 'A payment needs a confirmed assignment.' using errcode = 'ES409';
    end if;
    if new.currency is distinct from v_assignment.agreed_currency then
      raise exception 'A payment must be for the agreed amount.' using errcode = 'ES409';
    end if;
    if new.adjustment_id is not null then
      select * into v_adj from public.compensation_adjustments where id = new.adjustment_id;
      if not found or v_adj.assignment_id <> new.assignment_id or v_adj.status <> 'accepted'
         or v_adj.currency <> new.currency or new.split_from_payment_id is not null
         or new.amount + coalesce((select sum(p.amount) from public.payments p
                                   where p.adjustment_id = new.adjustment_id and p.status <> 'cancelled'), 0)
            > v_adj.amount then
        raise exception 'An extra pay payment must match its accepted offer.' using errcode = 'ES409';
      end if;
    elsif new.settlement_id is not null then
      select * into v_set from public.cancellation_settlements where id = new.settlement_id;
      if not found or v_set.assignment_id <> new.assignment_id or new.split_from_payment_id is not null
         or new.amount + coalesce((select sum(p.amount) from public.payments p
                                   where p.settlement_id = new.settlement_id and p.milestone_seq is null
                                     and p.adjustment_id is null and p.status <> 'cancelled'), 0)
            > v_set.editor_settlement_amount then
        raise exception 'A settlement payment must match the settlement.' using errcode = 'ES409';
      end if;
    elsif new.amount + coalesce((select sum(p.amount) from public.payments p
                                 where p.assignment_id = new.assignment_id and p.milestone_seq is not null
                                   and p.status <> 'cancelled'), 0) > v_assignment.agreed_amount then
      raise exception 'A payment must be for the agreed amount.' using errcode = 'ES409';
    end if;
    if new.split_from_payment_id is not null then
      select * into v_original from public.payments where id = new.split_from_payment_id;
      if not found or v_original.kind <> 'assignment' or v_original.status in ('paid', 'cancelled')
         or v_original.split_from_payment_id is not null or v_original.milestone_seq is null
         or new.milestone_seq is null
         or v_original.assignment_id <> new.assignment_id or v_original.milestone_seq <> new.milestone_seq
         or v_original.currency <> new.currency or new.status <> 'on_hold' then
        raise exception 'A disputed part must be split from an unpaid milestone and start on hold.'
          using errcode = 'ES409';
      end if;
    end if;
  elsif new.kind = 'reversal' then
    select * into v_original from public.payments where id = new.reverses_payment_id;
    if not found or v_original.kind <> 'assignment' or v_original.status <> 'paid'
       or v_original.assignment_id <> new.assignment_id then
      raise exception 'Only a paid payment can be reversed.' using errcode = 'ES409';
    end if;
    if new.currency <> v_original.currency or new.milestone_seq is distinct from v_original.milestone_seq
       or new.adjustment_id is distinct from v_original.adjustment_id then
      raise exception 'A reversal must match the payment it reverses.' using errcode = 'ES409';
    end if;
    if new.settlement_id is not distinct from v_original.settlement_id then
      if new.amount <> -v_original.amount then
        raise exception 'A reversal must be for the whole paid amount.' using errcode = 'ES409';
      end if;
    elsif v_original.settlement_id is not null or new.amount < -v_original.amount
          or not exists (select 1 from public.cancellation_settlements s
                         where s.id = new.settlement_id and s.assignment_id = new.assignment_id) then
      raise exception 'A settlement reversal cannot exceed the paid amount.' using errcode = 'ES409';
    end if;
  end if;
  return new;
end;
$$;

-- Update/delete guard (12D part 1 body, extended): cancelled is final like paid; only a
-- settlement (transaction-local flag naming the project) cancels a row, from any unpaid status;
-- the extra-line identity is fixed.
create or replace function private.guard_payments()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actors text[] := array['approved_by', 'marked_paid_by', 'created_by'];
  v_col text;
  v_splitting boolean;
begin
  if tg_op = 'DELETE' then
    raise exception 'Payments cannot be deleted.' using errcode = 'ES409';
  end if;

  if old.status in ('paid', 'cancelled') then
    -- Only clearing actor columns (on delete set null) with every other column unchanged.
    if (to_jsonb(new) - v_actors - 'updated_at') <> (to_jsonb(old) - v_actors - 'updated_at') then
      if old.status = 'cancelled' then
        raise exception 'This payment was cancelled by the cancellation settlement and cannot be changed.'
          using errcode = 'ES409';
      end if;
      raise exception 'This payment has been paid and cannot be changed.' using errcode = 'ES409';
    end if;
    foreach v_col in array v_actors loop
      if (to_jsonb(new) ->> v_col) is distinct from (to_jsonb(old) ->> v_col)
         and (to_jsonb(new) ->> v_col) is not null then
        raise exception 'This payment cannot be changed.' using errcode = 'ES409';
      end if;
    end loop;
    return new;
  end if;

  v_splitting := coalesce(current_setting('es.payment_split', true), '') = old.id::text
    and old.amount_before_split is null and new.amount_before_split = old.amount
    and new.amount > 0 and new.amount < old.amount;
  if (new.amount, new.amount_before_split) is distinct from (old.amount, old.amount_before_split)
     and not v_splitting then
    raise exception 'This part of a payment cannot change.' using errcode = 'ES409';
  end if;

  if (new.assignment_id, new.project_id, new.editor_id, new.kind, new.currency,
      new.reverses_payment_id, new.reversal_reason, new.created_at, new.milestone_seq, new.split_from_payment_id,
      new.adjustment_id, new.settlement_id)
     is distinct from
     (old.assignment_id, old.project_id, old.editor_id, old.kind, old.currency,
      old.reverses_payment_id, old.reversal_reason, old.created_at, old.milestone_seq, old.split_from_payment_id,
      old.adjustment_id, old.settlement_id)
     or (new.created_by is distinct from old.created_by and new.created_by is not null)
     or (old.payable_at is not null
         and (new.payable_at, new.payable_reason) is distinct from (old.payable_at, old.payable_reason)) then
    raise exception 'This part of a payment cannot change.' using errcode = 'ES409';
  end if;

  if new.status = 'cancelled' then
    if coalesce(current_setting('es.payment_cancel', true), '') <> old.project_id::text then
      raise exception 'Only a cancellation settlement can cancel a payment.' using errcode = 'ES409';
    end if;
    return new;
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

-- Audit (Phase 9 body): a settlement's cancellation is its own action.
create or replace function private.audit_payments()
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
    v_action := case when new.status = 'cancelled' then 'payment.cancelled'
                     when old.status = 'on_hold' then 'payment.hold_released'
                     else 'payment.' || new.status::text end;
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

-- Unpaid and not cancelled (Phase 9 body).
create or replace function private.require_unpaid(p public.payments)
returns void
language plpgsql
immutable
security definer
set search_path = ''
as $$
begin
  if p.status = 'paid' then
    raise exception 'This payment has been paid and cannot be changed.' using errcode = 'ES409';
  end if;
  if p.status = 'cancelled' then
    raise exception 'This payment was cancelled by the cancellation settlement and cannot be changed.'
      using errcode = 'ES409';
  end if;
end;
$$;

revoke all on function private.guard_scope_change_quotes(), private.guard_compensation_adjustments(),
  private.guard_client_milestone_links()
from public, anon, authenticated;
