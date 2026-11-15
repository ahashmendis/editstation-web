-- Phase 12D part 1 (2/3): editor pay milestones and partial-dispute splits on payments. Spec
-- docs/superpowers/specs/2026-11-15-phase12-commercial-terms-design.md §4.3, §4.5, call 9;
-- decisions KB9, KB9a-1, KB9a-4, KB9a-5, KB9b-3.
--
-- payments gains:
--   milestone_seq          which editor milestone (1..10) the row pays; reversals copy it
--   payable_reason/at      why and when the row became payable (enum; never free text)
--   split_from_payment_id  a disputed child row split from an unpaid milestone (§4.5)
--   amount_before_split    the parent's amount before the split (the sum invariant's reference)
--   waiting_on_client      client-safe flag: not_due only because client money is unverified
-- payments_open_key moves from one open row per assignment to one per (assignment, milestone).
-- Guards hold for the table owner too; amounts change only through the split function.

create type public.payment_payable_reason as enum (
  'client_deposit_verified', 'client_balance_verified', 'late_balance_protection', 'adjustment_accepted',
  'cancellation_settlement');
-- What an editor may see about a hold or wait (KB9a-5): a fixed label, never the admin's reason.
create type public.payment_hold_label as enum ('under_review', 'assignment_ended', 'waiting_for_client_payment');

alter table public.payments
  add column milestone_seq smallint default 1 check (milestone_seq between 1 and 10),
  add column payable_reason public.payment_payable_reason,
  add column payable_at timestamptz,
  add column split_from_payment_id uuid references public.payments (id) on delete restrict,
  add column amount_before_split numeric(12, 2),
  add column waiting_on_client boolean not null default false;

-- Existing (local-only, call 10) rows pay the whole agreed amount as milestone 1. The guard would
-- refuse touching paid rows, so it is paused for the backfill only.
alter table public.payments disable trigger payments_guard;
update public.payments set milestone_seq = 1;
alter table public.payments enable trigger payments_guard;

alter table public.payments
  alter column milestone_seq set not null,
  add constraint payments_payable_chk check ((payable_reason is null) = (payable_at is null)),
  add constraint payments_waiting_chk check (not waiting_on_client or status = 'not_due'),
  add constraint payments_split_chk check (
    (split_from_payment_id is null or kind = 'assignment')
    and (amount_before_split is null or (kind = 'assignment' and split_from_payment_id is null
                                         and amount_before_split > amount)));

drop index public.payments_open_key;
-- At most one unpaid row per editor milestone (split children are extra rows of the same milestone).
create unique index payments_open_key on public.payments (assignment_id, milestone_seq)
  where kind = 'assignment' and status <> 'paid' and split_from_payment_id is null;
-- One dispute split per milestone row.
create unique index payments_split_from_key on public.payments (split_from_payment_id);

-- A row that is not not_due is never "waiting for the client" (holds and approvals clear it).
create function private.clear_payment_waiting()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status <> 'not_due' then
    new.waiting_on_client := false;
  end if;
  return new;
end;
$$;

-- Runs before payments_guard / payments_set_updated_at (alphabetical order of before triggers).
create trigger payments_clear_waiting
  before insert or update on public.payments
  for each row execute function private.clear_payment_waiting();

-- ---------------------------------------------------------------------------
-- Insert guard (Phase 9 body, extended): milestone rows (net of reversals) pay at most the agreed
-- amount in the agreed currency; a split child matches its unpaid parent and starts on hold; a reversal matches
-- the paid row it reverses.
-- ---------------------------------------------------------------------------
create or replace function private.check_payment_row()
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
  if new.amount_before_split is not null then
    raise exception 'A payment starts unsplit.' using errcode = 'ES409';
  end if;
  if new.kind = 'assignment' then
    if v_assignment.confirmed_at is null then
      raise exception 'A payment needs a confirmed assignment.' using errcode = 'ES409';
    end if;
    -- Milestones (net of reversals) never add up to more than the agreed amount.
    if new.currency is distinct from v_assignment.agreed_currency
       or new.amount + coalesce((select sum(p.amount) from public.payments p
                                 where p.assignment_id = new.assignment_id), 0) > v_assignment.agreed_amount then
      raise exception 'A payment must be for the agreed amount.' using errcode = 'ES409';
    end if;
    if new.split_from_payment_id is not null then
      select * into v_original from public.payments where id = new.split_from_payment_id;
      if not found or v_original.kind <> 'assignment' or v_original.status = 'paid'
         or v_original.split_from_payment_id is not null
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
    if new.amount <> -v_original.amount or new.currency <> v_original.currency then
      raise exception 'A reversal must be for the whole paid amount.' using errcode = 'ES409';
    end if;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Update/delete guard (Phase 9 body, extended). Milestone and split identity are fixed; the amount
-- changes once, only inside admin_split_payment_for_dispute (transaction-local flag naming the
-- row); payable reason and time are fixed once set.
-- ---------------------------------------------------------------------------
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

  v_splitting := coalesce(current_setting('es.payment_split', true), '') = old.id::text
    and old.amount_before_split is null and new.amount_before_split = old.amount
    and new.amount > 0 and new.amount < old.amount;
  if (new.amount, new.amount_before_split) is distinct from (old.amount, old.amount_before_split)
     and not v_splitting then
    raise exception 'This part of a payment cannot change.' using errcode = 'ES409';
  end if;

  if (new.assignment_id, new.project_id, new.editor_id, new.kind, new.currency,
      new.reverses_payment_id, new.reversal_reason, new.created_at, new.milestone_seq, new.split_from_payment_id)
     is distinct from
     (old.assignment_id, old.project_id, old.editor_id, old.kind, old.currency,
      old.reverses_payment_id, old.reversal_reason, old.created_at, old.milestone_seq, old.split_from_payment_id)
     or (new.created_by is distinct from old.created_by and new.created_by is not null)
     or (old.payable_at is not null
         and (new.payable_at, new.payable_reason) is distinct from (old.payable_at, old.payable_reason)) then
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

-- ---------------------------------------------------------------------------
-- Sum invariant (§4.5): a split parent's amount plus its child equals amount_before_split, and a
-- child always has a split parent. Checked after each statement; the split function defers it
-- while it writes both rows and then checks immediately.
-- ---------------------------------------------------------------------------
create function private.check_payment_split()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent public.payments;
  v_children numeric(12, 2);
begin
  select * into v_parent from public.payments where id = coalesce(new.split_from_payment_id, new.id);
  select coalesce(sum(c.amount), 0) into v_children from public.payments c where c.split_from_payment_id = v_parent.id;
  if v_parent.amount_before_split is null then
    if new.split_from_payment_id is not null or v_children <> 0 then
      raise exception 'The parts of a split payment must add up to the original.' using errcode = 'ES409';
    end if;
  elsif v_parent.amount + v_children <> v_parent.amount_before_split then
    raise exception 'The parts of a split payment must add up to the original.' using errcode = 'ES409';
  end if;
  return null;
end;
$$;

create constraint trigger payments_split_sum
  after insert or update of amount, amount_before_split, split_from_payment_id on public.payments
  deferrable initially immediate
  for each row execute function private.check_payment_split();

revoke all on function private.clear_payment_waiting(), private.check_payment_split()
from public, anon, authenticated;
