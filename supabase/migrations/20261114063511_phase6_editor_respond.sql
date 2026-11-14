-- Phase 6 (4/5): editor_respond_offer. Spec §7 (editor). Plan calls 10, 11, 12, 20.
-- An active editor answers their own offer: accept, decline or counter, only from `offered`, only
-- while the project is open. Another editor's offer and an unknown id give the same
-- "Offer not found." (no existence leak). Editors never write money or status columns directly.

create function public.editor_respond_offer(
  p_assignment_id uuid, p_action text, p_amount numeric default null, p_currency text default null,
  p_message text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_editor uuid := private.require_active_editor();
  v public.assignments;
  v_amount numeric;
  v_message text;
begin
  -- Ownership first, without locks, so a caller can never lock another editor's project row.
  if not exists (select 1 from public.assignments where id = p_assignment_id and editor_id = v_editor) then
    raise exception 'Offer not found.' using errcode = 'ES422';
  end if;
  v := private.lock_assignment(p_assignment_id);
  if v.editor_id <> v_editor then
    raise exception 'Offer not found.' using errcode = 'ES422';
  end if;
  perform private.require_negotiable_project(v.project_id);
  if v.status <> 'offered' then
    raise exception 'This offer is not waiting for your answer.' using errcode = 'ES409';
  end if;
  if p_action is null or p_action not in ('accept', 'decline', 'counter') then
    raise exception 'Please choose accept, decline or counter.' using errcode = 'ES422';
  end if;
  v_message := private.clean_text(p_message, 2000, 'message');

  if p_action = 'accept' then
    update public.assignments
    set status = 'accepted', agreed_amount = proposed_amount, agreed_currency = currency
    where id = v.id;
    perform private.add_negotiation(v.id, 'editor', 'accept', v.proposed_amount, v.currency, v_message, v_editor);
  elsif p_action = 'decline' then
    update public.assignments set status = 'declined', closed_at = now() where id = v.id;
    perform private.add_negotiation(v.id, 'editor', 'decline', null, null, v_message, v_editor);
  else
    v_amount := private.check_amount(p_amount, 'counteroffer amount');
    if private.check_currency(p_currency, v.currency) <> v.currency then
      raise exception 'A counteroffer must use the same currency as the offer.' using errcode = 'ES422';
    end if;
    if v_amount = v.proposed_amount then
      raise exception 'Your counteroffer is the same as the offer. Accept it instead.' using errcode = 'ES422';
    end if;
    update public.assignments set status = 'counteroffer_pending', proposed_amount = v_amount where id = v.id;
    perform private.add_negotiation(v.id, 'editor', 'counter', v_amount, v.currency, v_message, v_editor);
  end if;
end;
$$;

revoke all on function public.editor_respond_offer(uuid, text, numeric, text, text) from public, anon, authenticated;
grant execute on function public.editor_respond_offer(uuid, text, numeric, text, text) to anon, authenticated;
