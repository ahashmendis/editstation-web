-- Phase 12E (3/3): payout details functions, the interim attestation (call 1) and the mark-paid
-- gate. Spec §4.8, call 1; decision E; SECURITY_AND_PRIVACY S10.
-- Rules: every write refuses while payout_details_enabled is false (ES409). Audit rows and
-- notifications hold ids and field names only, never bank values. Lock order: payments row, then
-- the payout_details_enabled settings row (for share), then the editor_payout_details row. Every
-- function that acts on the flag's value holds the settings row for share, so a concurrent
-- admin_set_payout_enabled (row lock) waits or is waited for: no write sees a stale flag.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
-- Holds the flag row for share until the transaction ends and returns its value.
create function private.lock_payout_flag()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v jsonb;
begin
  select s.value into v from public.app_settings s where s.key = 'payout_details_enabled' for share;
  return coalesce(v = 'true'::jsonb, false);
end;
$$;

create function private.require_payout_enabled()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.lock_payout_flag() then
    raise exception 'Payout details are not enabled yet. They stay off until Lenscape confirms how bank details are protected.'
      using errcode = 'ES409';
  end if;
end;
$$;

-- "****1234": only the last 4 letters or digits. A number with fewer than 6 is never shown.
create function private.mask_account_number(p_number text)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select case when p_number is null then null
    when char_length(regexp_replace(p_number, '[^A-Za-z0-9]', '', 'g')) < 6 then '****'
    else '****' || right(regexp_replace(p_number, '[^A-Za-z0-9]', '', 'g'), 4) end;
$$;

create function private.payout_attestation_current(p_editor_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not private.payout_details_enabled()
    and exists (select 1 from public.editor_payout_attestations a where a.editor_id = p_editor_id);
$$;

-- Why an editor payment cannot be marked paid yet, or null when it can (E-1, call 1).
create function private.payout_block_reason(p_editor_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when not private.payout_details_enabled() then
      case when private.payout_attestation_current(p_editor_id) then null
        else 'Before marking this paid, record on the payout card that the editor''s payout account was verified outside the app.' end
    when not exists (select 1 from public.editor_payout_details d where d.editor_id = p_editor_id) then
      'The editor has not added payout details yet. Ask them to add them on their Earnings page, then verify them by phone.'
    when exists (select 1 from public.editor_payout_details d
                 where d.editor_id = p_editor_id and d.verification_status = 'verified') then null
    else 'The editor''s payout details are not verified. Verify them by phone on the payout card first.'
  end;
$$;

create function private.require_editor_exists(p_editor_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_editor_id is null or not exists (select 1 from public.editor_profiles e where e.user_id = p_editor_id) then
    raise exception 'Editor not found.' using errcode = 'ES422';
  end if;
end;
$$;

create function private.admin_display_name(p_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(nullif(p.full_name, ''), p.email) from public.profiles p where p.id = p_id;
$$;

-- ---------------------------------------------------------------------------
-- editor_save_payout_details: active editor, own row. Any change resets to unverified, writes a
-- version and flags admins. Saving identical details changes nothing.
-- ---------------------------------------------------------------------------
create function public.editor_save_payout_details(p_account_holder text, p_bank text, p_branch text,
  p_account_number text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_editor();
  v_holder text;
  v_bank text;
  v_branch text;
  v_number text;
  v_old public.editor_payout_details;
  v_version int;
  v_fields text[] := '{}';
begin
  perform private.require_payout_enabled();
  v_holder := private.clean_text(p_account_holder, 120, 'account holder name');
  v_bank := private.clean_text(p_bank, 120, 'bank');
  v_branch := private.clean_text(p_branch, 120, 'branch');
  v_number := regexp_replace(coalesce(private.clean_text(p_account_number, 34, 'account number'), ''), '\s+', ' ', 'g');
  if v_holder is null or v_bank is null or v_branch is null or v_number = '' then
    raise exception 'Please fill in the account holder name, bank, branch and account number.' using errcode = 'ES422';
  end if;
  if v_number !~ '^[A-Za-z0-9 -]{6,34}$' or v_number !~ '[0-9]'
     or char_length(regexp_replace(v_number, '[^A-Za-z0-9]', '', 'g')) < 6 then
    raise exception 'Please enter a valid account number (at least 6 letters or digits; spaces and hyphens allowed).'
      using errcode = 'ES422';
  end if;

  select * into v_old from public.editor_payout_details where editor_id = v_uid for update;
  if found then
    if v_old.account_holder is distinct from v_holder then v_fields := array_append(v_fields, 'account_holder'); end if;
    if v_old.bank is distinct from v_bank then v_fields := array_append(v_fields, 'bank'); end if;
    if v_old.branch is distinct from v_branch then v_fields := array_append(v_fields, 'branch'); end if;
    if v_old.account_number is distinct from v_number then v_fields := array_append(v_fields, 'account_number'); end if;
    if cardinality(v_fields) = 0 then
      return;
    end if;
    v_version := v_old.version + 1;
    update public.editor_payout_details
    set account_holder = v_holder, bank = v_bank, branch = v_branch, account_number = v_number,
        version = v_version, verification_status = 'unverified', verified_by = null, verified_at = null,
        verified_method = null, verification_note = null, last_changed_at = now()
    where editor_id = v_uid;
  else
    v_fields := array['account_holder', 'bank', 'branch', 'account_number'];
    v_version := coalesce((select max(v.version) from public.editor_payout_detail_versions v
                           where v.editor_id = v_uid), 0) + 1;
    insert into public.editor_payout_details (editor_id, account_holder, bank, branch, account_number, version)
    values (v_uid, v_holder, v_bank, v_branch, v_number, v_version);
  end if;

  insert into public.editor_payout_detail_versions (editor_id, version, account_holder, bank, branch,
    account_number, changed_by)
  values (v_uid, v_version, v_holder, v_bank, v_branch, v_number, v_uid);

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_uid, 'payout_details.changed', 'editor_profile', v_uid::text,
    jsonb_build_object('editor_id', v_uid, 'version', v_version, 'fields', to_jsonb(v_fields)));

  perform private.notify(private.active_admin_ids(), 'payout_details_changed', 'editor_profile', v_uid,
    'Payout details changed', 'An editor saved new payout details. They are unverified until you confirm them by phone.');
end;
$$;

-- ---------------------------------------------------------------------------
-- editor_get_payout_details: own details, account number masked
-- ---------------------------------------------------------------------------
create function public.editor_get_payout_details()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_editor();
  d public.editor_payout_details;
begin
  select * into d from public.editor_payout_details where editor_id = v_uid;
  if not found then
    return jsonb_build_object('enabled', private.payout_details_enabled(), 'saved', false);
  end if;
  return jsonb_build_object(
    'enabled', private.payout_details_enabled(), 'saved', true,
    'account_holder', d.account_holder, 'bank', d.bank, 'branch', d.branch,
    'account_number_masked', private.mask_account_number(d.account_number),
    'verification_status', d.verification_status, 'verified_at', d.verified_at,
    'last_changed_at', d.last_changed_at);
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_get_payout_details_masked: details (masked), verification, attestation and the
-- mark-paid status for one editor
-- ---------------------------------------------------------------------------
create function public.admin_get_payout_details_masked(p_editor_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  d public.editor_payout_details;
  a public.editor_payout_attestations;
  v jsonb;
begin
  perform private.require_editor_exists(p_editor_id);
  v := jsonb_build_object(
    'enabled', private.payout_details_enabled(),
    'saved', false,
    'mark_paid_block', private.payout_block_reason(p_editor_id),
    'attestation_current', private.payout_attestation_current(p_editor_id));
  select * into a from public.editor_payout_attestations where editor_id = p_editor_id
  order by attested_at desc, id desc limit 1;
  if found then
    v := v || jsonb_build_object('attestation', jsonb_build_object(
      'attested_at', a.attested_at, 'attested_by', private.admin_display_name(a.attested_by), 'note', a.note));
  end if;
  select * into d from public.editor_payout_details where editor_id = p_editor_id;
  if found then
    v := v || jsonb_build_object(
      'saved', true, 'version', d.version,
      'account_holder', d.account_holder, 'bank', d.bank, 'branch', d.branch,
      'account_number_masked', private.mask_account_number(d.account_number),
      'verification_status', d.verification_status, 'verified_at', d.verified_at,
      'verified_by', private.admin_display_name(d.verified_by), 'verified_method', d.verified_method,
      'verification_note', d.verification_note, 'last_changed_at', d.last_changed_at);
  end if;
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_reveal_payout_details: the full account number. Refused while payout details are locked
-- (masked reads stay allowed). A reason is required (no digit runs: it is logged) and every call
-- writes an audit row (admin, editor, reason; never the number).
-- ---------------------------------------------------------------------------
create function public.admin_reveal_payout_details(p_editor_id uuid, p_reason text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_reason text := private.clean_text(p_reason, 500, 'reason');
  v_number text;
begin
  perform private.require_payout_enabled();
  perform private.require_editor_exists(p_editor_id);
  if v_reason is null then
    raise exception 'Please give a reason for revealing the full account number.' using errcode = 'ES422';
  end if;
  if regexp_replace(v_reason, '[\s.-]', '', 'g') ~ '[0-9]{6,}' then
    raise exception 'Do not type bank details here: give the reason in words.' using errcode = 'ES422';
  end if;
  select account_number into v_number from public.editor_payout_details where editor_id = p_editor_id;
  if not found then
    raise exception 'This editor has no payout details saved.' using errcode = 'ES409';
  end if;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'payout_details.revealed', 'editor_profile', p_editor_id::text,
    jsonb_build_object('editor_id', p_editor_id, 'admin_id', v_admin, 'reason', v_reason,
      'fields', '["account_number"]'::jsonb));
  return v_number;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_verify_payout_details: records an out-of-band (phone) verification of the version the
-- admin looked at. Any later change resets it.
-- ---------------------------------------------------------------------------
create function public.admin_verify_payout_details(p_editor_id uuid, p_version int, p_method text, p_note text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_note text := private.clean_text(p_note, 500, 'note');
  d public.editor_payout_details;
begin
  perform private.require_payout_enabled();
  perform private.require_editor_exists(p_editor_id);
  if p_method is null or p_method not in ('phone', 'in_person', 'other') then
    raise exception 'Choose how you verified the details.' using errcode = 'ES422';
  end if;
  if v_note is null then
    raise exception 'Please add a short note about the verification (for example who you spoke to).' using errcode = 'ES422';
  end if;
  select * into d from public.editor_payout_details where editor_id = p_editor_id for update;
  if not found then
    raise exception 'This editor has no payout details saved.' using errcode = 'ES409';
  end if;
  if p_version is null or d.version <> p_version then
    raise exception 'The payout details changed since you opened them. Reload and verify the new details.'
      using errcode = 'ES409';
  end if;
  if d.verification_status = 'verified' then
    raise exception 'These payout details are already verified.' using errcode = 'ES409';
  end if;
  update public.editor_payout_details
  set verification_status = 'verified', verified_by = v_admin, verified_at = now(),
      verified_method = p_method, verification_note = v_note
  where editor_id = p_editor_id;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'payout_details.verified', 'editor_profile', p_editor_id::text,
    jsonb_build_object('editor_id', p_editor_id, 'version', d.version, 'method', p_method,
      'fields', '["verification_status", "verified_method", "verification_note"]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_set_payout_enabled: the lock. Must stay off until counsel confirms PDPA handling.
-- ---------------------------------------------------------------------------
create function public.admin_set_payout_enabled(p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
begin
  if p_enabled is null then
    raise exception 'Choose on or off.' using errcode = 'ES422';
  end if;
  insert into public.app_settings (key, value, updated_by) values ('payout_details_enabled', to_jsonb(p_enabled), v_admin)
  on conflict (key) do update set value = excluded.value, updated_by = excluded.updated_by;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'app_settings.changed', 'app_settings', 'payout_details_enabled',
    jsonb_build_object('fields', '["payout_details_enabled"]'::jsonb, 'enabled', p_enabled));
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_attest_payout_outside_app (call 1): only while payout details are off. Admin and date,
-- no bank data. Retired automatically once the flag is on.
-- ---------------------------------------------------------------------------
create function public.admin_attest_payout_outside_app(p_editor_id uuid, p_note text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_note text := private.clean_text(p_note, 500, 'note');
  v_id uuid;
begin
  if private.lock_payout_flag() then
    raise exception 'Payout details are live: verify the editor''s payout account in the app instead.'
      using errcode = 'ES409';
  end if;
  perform private.require_editor_exists(p_editor_id);
  if v_note is null then
    raise exception 'Please add a short note (how and when the account was verified). Do not enter bank details.'
      using errcode = 'ES422';
  end if;
  insert into public.editor_payout_attestations (editor_id, note, attested_by)
  values (p_editor_id, v_note, v_admin) returning id into v_id;
  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'payout_attestation.recorded', 'editor_profile', p_editor_id::text,
    jsonb_build_object('editor_id', p_editor_id, 'attestation_id', v_id, 'fields', '["note"]'::jsonb));
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_mark_payment_paid (replaces Phase 9): every existing check and the payments_audit trigger
-- unchanged; adds the payout gate (E-1 / call 1) after them, holding the payout row (payment
-- first, then payout details) so a concurrent change cannot slip between check and update.
-- ---------------------------------------------------------------------------
create or replace function public.admin_mark_payment_paid(p_payment_id uuid, p_transaction_reference text, p_transfer_date date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v public.payments;
  v_reference text;
  v_confirmed date;
  v_block text;
begin
  v := private.lock_payment(p_payment_id);
  perform private.require_unpaid(v);
  if not private.payment_transition_allowed(v.status, 'paid') then
    raise exception 'This payment cannot move from % to paid.', replace(v.status::text, '_', ' ')
      using errcode = 'ES409';
  end if;
  v_reference := private.clean_text(p_transaction_reference, 120, 'transaction reference');
  if v_reference is null then
    raise exception 'Please enter the transaction reference.' using errcode = 'ES422';
  end if;
  if p_transfer_date is null then
    raise exception 'Please enter the transfer date.' using errcode = 'ES422';
  end if;
  if p_transfer_date > (now() at time zone 'Asia/Colombo')::date then
    raise exception 'The transfer date cannot be in the future.' using errcode = 'ES422';
  end if;
  select (a.confirmed_at at time zone 'Asia/Colombo')::date into v_confirmed
  from public.assignments a where a.id = v.assignment_id;
  if v_confirmed is not null and p_transfer_date < v_confirmed then
    raise exception 'The transfer date cannot be before the editor was confirmed.' using errcode = 'ES422';
  end if;
  perform private.lock_payout_flag();
  perform 1 from public.editor_payout_details d where d.editor_id = v.editor_id for share;
  v_block := private.payout_block_reason(v.editor_id);
  if v_block is not null then
    raise exception '%', v_block using errcode = 'ES409';
  end if;
  update public.payments
  set status = 'paid', transaction_reference = v_reference, transfer_date = p_transfer_date,
      marked_paid_by = v_admin, marked_paid_at = now()
  where id = v.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges
-- ---------------------------------------------------------------------------
revoke all on function private.lock_payout_flag(), private.require_payout_enabled(), private.mask_account_number(text),
  private.payout_attestation_current(uuid), private.payout_block_reason(uuid),
  private.require_editor_exists(uuid), private.admin_display_name(uuid)
from public, anon, authenticated;

grant execute on function
  public.editor_save_payout_details(text, text, text, text), public.editor_get_payout_details(),
  public.admin_get_payout_details_masked(uuid), public.admin_reveal_payout_details(uuid, text),
  public.admin_verify_payout_details(uuid, int, text, text), public.admin_set_payout_enabled(boolean),
  public.admin_attest_payout_outside_app(uuid, text), public.admin_mark_payment_paid(uuid, text, date)
to anon, authenticated;
revoke execute on function
  public.editor_save_payout_details(text, text, text, text), public.editor_get_payout_details(),
  public.admin_get_payout_details_masked(uuid), public.admin_reveal_payout_details(uuid, text),
  public.admin_verify_payout_details(uuid, int, text, text), public.admin_set_payout_enabled(boolean),
  public.admin_attest_payout_outside_app(uuid, text), public.admin_mark_payment_paid(uuid, text, date)
from public;
