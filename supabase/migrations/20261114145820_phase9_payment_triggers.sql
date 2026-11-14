-- Phase 9 (2/3): payment lifecycle triggers on assignments. Spec §4.2, §4.3, §8; plan calls 3, 4.
-- They run inside the assignment functions' project -> assignment locks and lock payments last.
-- No Phase 6/7 function is replaced.

-- accepted -> confirmed: one not_due payment for the agreed amount (decision I).
create function private.create_assignment_payment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.payments (assignment_id, project_id, editor_id, kind, amount, currency, status, created_by)
  values (new.id, new.project_id, new.editor_id, 'assignment', new.agreed_amount, new.agreed_currency, 'not_due',
    new.confirmed_by);
  return null;
end;
$$;

create trigger assignments_create_payment
  after update of status on public.assignments
  for each row
  when (old.status = 'accepted' and new.status = 'confirmed')
  execute function private.create_assignment_payment();

-- confirmed | in_progress -> reassigned | withdrawn: unpaid payments go on hold with a fixed,
-- editor-visible reason (flag F). Rows already on hold keep their reason; paid rows are untouched.
create function private.hold_payments_on_close()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
begin
  for r in
    select p.id, p.status from public.payments p
    where p.assignment_id = new.id and p.status in ('not_due', 'pending_approval', 'approved', 'processing')
    order by p.id
    for update
  loop
    update public.payments
    set status = 'on_hold', held_from_status = r.status,
        on_hold_reason = 'The assignment ended before the work was finished. Lenscape will contact you about this payment.'
    where id = r.id;
  end loop;
  return null;
end;
$$;

create trigger assignments_hold_payments
  after update of status on public.assignments
  for each row
  when (old.status in ('confirmed', 'in_progress') and new.status in ('reassigned', 'withdrawn'))
  execute function private.hold_payments_on_close();

revoke all on function private.create_assignment_payment(), private.hold_payments_on_close()
from public, anon, authenticated;
