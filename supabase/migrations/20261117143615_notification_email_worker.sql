-- Notification emails (feature A). Spec: docs/superpowers/specs/2026-11-17-notification-emails-and-avatars-design.md §A
-- (owner approved 2026-11-17).
--
-- The outbox gains retry/claim bookkeeping and a digest flag. Three public worker functions are
-- called only by the server route /api/cron/send-emails with the service key: they refuse every
-- other caller with ES403. They never return a notification body (it can name a project), only
-- the recipient's confirmed email, the notification title and kind, or per-kind counts for the
-- daily admin summary. The scheduler (pg_cron + pg_net on hosted) is not part of this migration:
-- the local stack has no pg_net, see docs/RUNBOOKS.md "Notification emails".

-- ---------------------------------------------------------------------------
-- Outbox columns
-- ---------------------------------------------------------------------------
alter table private.notification_outbox
  add column attempts integer not null default 0 check (attempts between 0 and 3),
  add column last_error text check (char_length(last_error) <= 200),
  add column claimed_at timestamptz,
  add column digest boolean not null default false;

comment on column private.notification_outbox.attempts is
  'Send attempts so far (incremented when a worker claims the row). After 3 the row is failed.';
comment on column private.notification_outbox.last_error is
  'Short machine reason from the worker (e.g. "provider 400"). Never an address, key or body.';
comment on column private.notification_outbox.claimed_at is
  'When a worker last claimed the row. A claim is a 15-minute lease; rows sent in one admin digest share it.';
comment on column private.notification_outbox.digest is
  'true = goes into the daily admin summary, false = individual email. Set on insert from the kind.';

-- Who receives each kind decides how it is emailed (decision 1 of the spec):
--   Admin kinds -> daily summary (digest = true):
--     inquiry_new, application_new, applicant_response, counteroffer, submission,
--     asset_inaccessible, project_auto_held, late_balance_payable, adjustment_answered,
--     payout_details_changed, interest_registered
--   Editor and applicant kinds -> one email each (digest = false):
--     application_decision, application_request (applicant); invitation, assignment_confirmed,
--     revision_requested, payment_paid, adjustment_offered, opportunity_selected,
--     opportunity_not_selected (editor)
-- An unmapped (future) kind returns null; the insert trigger then treats it as individual so no
-- email is silently lost, and a pgTAP test fails until the new kind is mapped here.
create function private.email_is_digest(p_kind public.notification_kind)
returns boolean
language sql
immutable
security definer
set search_path = ''
as $$
  select case p_kind::text
    when 'inquiry_new' then true
    when 'application_new' then true
    when 'applicant_response' then true
    when 'counteroffer' then true
    when 'submission' then true
    when 'asset_inaccessible' then true
    when 'project_auto_held' then true
    when 'late_balance_payable' then true
    when 'adjustment_answered' then true
    when 'payout_details_changed' then true
    when 'interest_registered' then true
    when 'application_decision' then false
    when 'application_request' then false
    when 'invitation' then false
    when 'assignment_confirmed' then false
    when 'revision_requested' then false
    when 'payment_paid' then false
    when 'adjustment_offered' then false
    when 'opportunity_selected' then false
    when 'opportunity_not_selected' then false
  end;
$$;

-- Trigger function: only sets a column on the row being inserted. Security definer like every
-- function since Phase 4 (046 catalogue rule); no API role can execute it.
create function private.set_outbox_digest()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.digest := coalesce(private.email_is_digest(new.kind), false);
  return new;
end;
$$;

create trigger notification_outbox_set_digest
  before insert on private.notification_outbox
  for each row execute function private.set_outbox_digest();

update private.notification_outbox set digest = coalesce(private.email_is_digest(kind), false);

-- Pre-launch backlog: everything still queued when this migration runs was written while no
-- sender existed and was never meant to be emailed. Failing it means the first hosted cron run
-- sends only notifications created after the worker went live. A function so the rule is tested;
-- it is called once, here.
create function private.fail_prelaunch_backlog()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  n integer;
begin
  update private.notification_outbox
  set status = 'failed', last_error = 'pre-launch backlog'
  where status = 'queued';
  get diagnostics n = row_count;
  return n;
end;
$$;

select private.fail_prelaunch_backlog();

-- Claiming reads queued rows oldest first; the digest check reads an admin's sent digest rows.
create index notification_outbox_digest_idx on private.notification_outbox (recipient_id, status) where digest;

-- No API role (service_role included) touches the outbox directly; only the worker functions.
revoke all on private.notification_outbox from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Caller check: the service key. Both must hold: the database role is service_role (PostgREST
-- switches to it for the secret key; a security definer function does not change the `role`
-- setting) and the JWT role claim is service_role (minted by the Supabase API gateway for the
-- secret key). User sessions are 'authenticated', the publishable key 'anon'.
-- ---------------------------------------------------------------------------
create function private.require_service_role()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if coalesce(current_setting('role', true), '') <> 'service_role'
     or coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Not allowed.' using errcode = 'ES403';
  end if;
end;
$$;

-- Housekeeping before each claim:
--  * rows whose last attempt never reported back (worker died) are failed once the lease ends;
--  * rows queued for more than 14 days are failed when the recipient still has no confirmed,
--    non-deleted address ('no confirmed address') or, for admin summary rows, is no longer an
--    active admin ('recipient inactive'). Younger rows wait: the person may still confirm.
create function private.fail_exhausted_emails(p_at timestamptz)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.notification_outbox
  set status = 'failed', last_error = coalesce(last_error, 'no result after the last attempt')
  where status = 'queued' and attempts >= 3
    and (claimed_at is null or claimed_at < p_at - interval '15 minutes');

  update private.notification_outbox o
  set status = 'failed', last_error = 'no confirmed address'
  where o.status = 'queued' and o.created_at < p_at - interval '14 days'
    and (o.claimed_at is null or o.claimed_at < p_at - interval '15 minutes')
    and not exists (
      select 1 from auth.users u
      where u.id = o.recipient_id and u.email is not null
        and u.email_confirmed_at is not null and u.deleted_at is null);

  update private.notification_outbox o
  set status = 'failed', last_error = 'recipient inactive'
  where o.status = 'queued' and o.digest and o.created_at < p_at - interval '14 days'
    and (o.claimed_at is null or o.claimed_at < p_at - interval '15 minutes')
    and not exists (
      select 1 from public.admin_users a where a.user_id = o.recipient_id and a.revoked_at is null);
end;
$$;

revoke all on function private.email_is_digest(public.notification_kind), private.set_outbox_digest(),
  private.fail_prelaunch_backlog(), private.require_service_role(),
  private.fail_exhausted_emails(timestamptz)
from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- worker_claim_emails: individual emails (editor and applicant kinds), oldest first, at most
-- p_limit (1..100, default 25). Only recipients with a confirmed, non-deleted account. Each row
-- is leased for 15 minutes and its attempt counted; worker_mark_email reports the result and is
-- given claimed_at back, so a late report from an expired lease cannot settle a newer claim.
-- ---------------------------------------------------------------------------
create function public.worker_claim_emails(p_limit integer default 25)
returns table (id bigint, email text, title text, kind public.notification_kind, claimed_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_at timestamptz := clock_timestamp();
  v_limit integer := least(greatest(coalesce(p_limit, 25), 1), 100);
begin
  perform private.require_service_role();
  perform private.fail_exhausted_emails(v_at);

  return query
  with c as (
    select o.id
    from private.notification_outbox o
    join auth.users u on u.id = o.recipient_id
    where o.status = 'queued' and not o.digest and o.attempts < 3
      and (o.claimed_at is null or o.claimed_at < v_at - interval '15 minutes')
      and u.email is not null and u.email_confirmed_at is not null and u.deleted_at is null
    order by o.created_at, o.id
    limit v_limit
    for update of o skip locked
  ), upd as (
    update private.notification_outbox o
    set claimed_at = v_at, attempts = o.attempts + 1
    from c
    where o.id = c.id
    returning o.id, o.recipient_id, o.notification_id, o.kind, o.created_at
  )
  select upd.id, u.email::text, n.title, upd.kind, v_at
  from upd
  join auth.users u on u.id = upd.recipient_id
  join public.notifications n on n.id = upd.notification_id
  order by upd.created_at, upd.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- worker_claim_admin_digest: at most one summary per active admin per Asia/Colombo calendar day
-- (the day of p_now). "Already sent that day" uses the Colombo date of a sent summary's
-- claimed_at (when it was taken for sending), so a summary claimed at 23:59 and reported after
-- midnight counts for the earlier day. Only admins with a confirmed email, queued admin-kind rows,
-- no summary sent that day and none in flight. Returns the lowest row id as the summary's handle,
-- its claimed_at and per-kind counts; all rows of the summary share one claimed_at so
-- worker_mark_email settles them together. Locks: outbox rows plus one non-blocking transaction
-- advisory lock, so two overlapping runs cannot each send a summary.
-- ---------------------------------------------------------------------------
create function public.worker_claim_admin_digest(p_now timestamptz default now())
returns table (id bigint, email text, counts jsonb, total integer, claimed_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_at timestamptz := clock_timestamp();
  v_day date := (coalesce(p_now, now()) at time zone 'Asia/Colombo')::date;
begin
  perform private.require_service_role();
  if not pg_try_advisory_xact_lock(hashtextextended('editstation.admin_digest', 0)) then
    return;
  end if;
  perform private.fail_exhausted_emails(v_at);

  return query
  with eligible as (
    select a.user_id, u.email::text as email
    from public.admin_users a
    join auth.users u on u.id = a.user_id
    where a.revoked_at is null
      and u.email is not null and u.email_confirmed_at is not null and u.deleted_at is null
      and not exists (
        select 1 from private.notification_outbox s
        where s.recipient_id = a.user_id and s.digest and s.status = 'sent'
          and (s.claimed_at at time zone 'Asia/Colombo')::date = v_day)
      and not exists (
        select 1 from private.notification_outbox s
        where s.recipient_id = a.user_id and s.digest and s.status = 'queued'
          and s.claimed_at >= v_at - interval '15 minutes')
  ), c as (
    select o.id
    from private.notification_outbox o
    join eligible e on e.user_id = o.recipient_id
    where o.status = 'queued' and o.digest and o.attempts < 3
      and (o.claimed_at is null or o.claimed_at < v_at - interval '15 minutes')
    for update of o skip locked
  ), upd as (
    update private.notification_outbox o
    set claimed_at = v_at, attempts = o.attempts + 1
    from c
    where o.id = c.id
    returning o.id, o.recipient_id, o.kind
  ), per_kind as (
    select upd.recipient_id, upd.kind, min(upd.id) as first_id, count(*)::integer as n
    from upd
    group by upd.recipient_id, upd.kind
  )
  select min(p.first_id), e.email, jsonb_object_agg(p.kind::text, p.n), sum(p.n)::integer, v_at
  from per_kind p
  join eligible e on e.user_id = p.recipient_id
  group by p.recipient_id, e.email
  order by min(p.first_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- worker_mark_email: report the result for a claimed row (for a summary: its handle id, which
-- settles every row claimed with it). ok -> sent. Not ok -> back to queued for the next run, or
-- failed once 3 attempts are used. When p_claimed_at (from the claim) is given it must equal the
-- row's current claim, else ES409: a report from an expired lease cannot settle a newer claim.
-- Delivery is at least once: a send that succeeded but was never reported is sent again after the
-- lease. p_error is stored trimmed to 200 characters; callers pass a short machine reason only.
-- ---------------------------------------------------------------------------
create function public.worker_mark_email(p_id bigint, p_ok boolean, p_error text default null,
  p_claimed_at timestamptz default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r private.notification_outbox%rowtype;
begin
  perform private.require_service_role();
  if p_id is null or p_ok is null then
    raise exception 'Missing result.' using errcode = 'ES422';
  end if;

  select * into r from private.notification_outbox o where o.id = p_id for update;
  if not found then
    raise exception 'Email not found.' using errcode = 'ES422';
  end if;
  if r.status <> 'queued' or r.claimed_at is null
     or (p_claimed_at is not null and r.claimed_at <> p_claimed_at) then
    raise exception 'Email is not waiting for this result.' using errcode = 'ES409';
  end if;

  update private.notification_outbox o
  set status = case when p_ok then 'sent' when o.attempts >= 3 then 'failed' else 'queued' end,
      sent_at = case when p_ok then now() else null end,
      last_error = case when p_ok then null
                        else coalesce(left(nullif(btrim(p_error), ''), 200), 'send failed') end,
      claimed_at = case when p_ok or o.attempts >= 3 then o.claimed_at else null end
  where o.status = 'queued'
    and (o.id = r.id
         or (r.digest and o.digest and o.recipient_id = r.recipient_id and o.claimed_at = r.claimed_at));
end;
$$;

-- Project guardrail: public functions are executable by anon and authenticated (a permission
-- error crashes this Postgres image) and authorise in their body; service_role is the only caller
-- that passes. No PUBLIC grant.
revoke all on function public.worker_claim_emails(integer), public.worker_claim_admin_digest(timestamptz),
  public.worker_mark_email(bigint, boolean, text, timestamptz)
from public, anon, authenticated, service_role;
grant execute on function public.worker_claim_emails(integer), public.worker_claim_admin_digest(timestamptz),
  public.worker_mark_email(bigint, boolean, text, timestamptz)
to anon, authenticated, service_role;
