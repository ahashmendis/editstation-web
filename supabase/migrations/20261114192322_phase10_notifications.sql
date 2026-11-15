-- Phase 10 (1/2): in-app notifications (KB10, adopted 2026-11-14) and a private email outbox.
-- Spec: docs/superpowers/specs/2026-11-14-phase10-notifications-design.md.
-- Notifications are written by one trigger on activity_logs, so every workflow event that is
-- already audited can notify without changing earlier functions. Text never holds client data.

create type public.notification_kind as enum (
  -- to admins
  'inquiry_new', 'application_new', 'applicant_response', 'counteroffer', 'submission',
  -- to the applicant
  'application_decision', 'application_request',
  -- to the editor
  'invitation', 'assignment_confirmed', 'revision_requested', 'payment_paid');

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  kind public.notification_kind not null,
  entity_type text not null check (entity_type in ('client_inquiry', 'editor_application', 'project', 'payment')),
  entity_id uuid not null,
  title text not null check (char_length(title) between 1 and 200),
  body text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default clock_timestamp(),
  read_at timestamptz
);
create index notifications_recipient_idx on public.notifications (recipient_id, created_at desc);
create index notifications_unread_idx on public.notifications (recipient_id) where read_at is null;
comment on table public.notifications is
  'In-app notifications. Written only by private.notify_from_activity(); recipients read their own. No client data.';

-- Email outbox: queued for when production SMTP exists (launch gate). Nothing sends it yet.
create table private.notification_outbox (
  id bigint generated always as identity primary key,
  notification_id uuid not null references public.notifications (id) on delete cascade,
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  kind public.notification_kind not null,
  status text not null default 'queued' check (status in ('queued', 'sent', 'failed')),
  created_at timestamptz not null default now(),
  sent_at timestamptz
);
create index notification_outbox_notification_idx on private.notification_outbox (notification_id);
create index notification_outbox_recipient_idx on private.notification_outbox (recipient_id);
create index notification_outbox_queued_idx on private.notification_outbox (created_at) where status = 'queued';
revoke all on private.notification_outbox from public, anon, authenticated;

alter table public.notifications enable row level security;
revoke all on public.notifications from anon, authenticated;
grant select on public.notifications to authenticated;
create policy notifications_select_own on public.notifications
  for select to authenticated using (recipient_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Writing
-- ---------------------------------------------------------------------------
create function private.notify(p_recipients uuid[], p_kind public.notification_kind, p_entity_type text,
  p_entity_id uuid, p_title text, p_body text)
returns void
language sql
security definer
set search_path = ''
as $$
  with ins as (
    insert into public.notifications (recipient_id, kind, entity_type, entity_id, title, body)
    select distinct r, p_kind, p_entity_type, p_entity_id, p_title, left(p_body, 500)
    from unnest(p_recipients) r
    where r is not null and p_entity_id is not null
    returning id, recipient_id, kind)
  insert into private.notification_outbox (notification_id, recipient_id, kind)
  select id, recipient_id, kind from ins;
$$;

create function private.active_admin_ids()
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(user_id), '{}') from public.admin_users where revoked_at is null;
$$;

create function private.project_title(p_project_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select title from public.projects where id = p_project_id), 'a project');
$$;

create function private.notify_from_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  d jsonb := new.details;
  v_project uuid;
  v_editor uuid;
  v_app uuid;
  v_kind text;
begin
  -- A notification failure (e.g. malformed details) must never roll back the audited action.
  begin
  case new.action
  when 'inquiry.submitted' then
    perform private.notify(private.active_admin_ids(), 'inquiry_new', 'client_inquiry', new.entity_id::uuid,
      'New client inquiry', 'A client inquiry was submitted through the public form.');
  when 'application.submitted' then
    perform private.notify(private.active_admin_ids(), 'application_new', 'editor_application', new.entity_id::uuid,
      'New editor application', 'An applicant submitted an application for review.');
  when 'application_request.answered' then
    perform private.notify(private.active_admin_ids(), 'applicant_response', 'editor_application',
      (d ->> 'application_id')::uuid, 'Applicant responded', 'An applicant answered an information or test request.');
  when 'assignment.counteroffer_pending' then
    v_project := (d ->> 'project_id')::uuid;
    perform private.notify(private.active_admin_ids(), 'counteroffer', 'project', v_project,
      'Counteroffer received', format('An editor sent a counteroffer on "%s".', private.project_title(v_project)));
  when 'submission.submitted' then
    v_project := (d ->> 'project_id')::uuid;
    perform private.notify(private.active_admin_ids(), 'submission', 'project', v_project,
      'Work submitted', format('Version %s was submitted on "%s".', coalesce(d ->> 'version', '?'),
        private.project_title(v_project)));
  when 'application.approved', 'application.rejected' then
    v_app := new.entity_id::uuid;
    v_editor := coalesce((d ->> 'editor_id')::uuid,
      (select editor_id from public.editor_applications where id = v_app));
    if new.action = 'application.approved' then
      perform private.notify(array[v_editor], 'application_decision', 'editor_application', v_app,
        'Your application was approved', 'Your editor application was approved. Your editor workspace is ready.');
    else
      perform private.notify(array[v_editor], 'application_decision', 'editor_application', v_app,
        'Application decision', 'A decision was made on your application. Open it to read the message.');
    end if;
  when 'application_request.created' then
    v_app := (d ->> 'application_id')::uuid;
    v_kind := d ->> 'kind';
    perform private.notify(array[(select editor_id from public.editor_applications where id = v_app)],
      'application_request', 'editor_application', v_app,
      case when v_kind = 'test' then 'Practical test requested' else 'More information requested' end,
      'An admin sent you a request about your application.');
  when 'project_access.granted' then
    if d ->> 'reason' = 'invited' then
      v_project := (d ->> 'project_id')::uuid;
      perform private.notify(array[(d ->> 'editor_id')::uuid], 'invitation', 'project', v_project,
        'Project invitation', format('You were invited to view "%s".', private.project_title(v_project)));
    end if;
  when 'assignment.confirmed' then
    v_project := (d ->> 'project_id')::uuid;
    perform private.notify(array[(d ->> 'editor_id')::uuid], 'assignment_confirmed', 'project', v_project,
      'Assignment confirmed', format('Your agreed rate for "%s" is confirmed.', private.project_title(v_project)));
  when 'revision_request.created' then
    select a.editor_id, a.project_id into v_editor, v_project
    from public.assignments a where a.id = (d ->> 'assignment_id')::uuid;
    perform private.notify(array[v_editor], 'revision_requested', 'project', v_project,
      'Revision requested', format('A change was requested on "%s".', private.project_title(v_project)));
  when 'payment.paid' then
    select a.editor_id, a.project_id into v_editor, v_project
    from public.assignments a where a.id = (d ->> 'assignment_id')::uuid;
    perform private.notify(array[v_editor], 'payment_paid', 'payment', (d ->> 'payment_id')::uuid,
      'Payment marked paid', format('A payment for "%s" was marked paid.', private.project_title(v_project)));
  else
    null;
  end case;
  exception when others then
    raise warning 'notification skipped for activity % (%)', new.id, sqlstate;
  end;
  return null;
end;
$$;

create trigger activity_logs_notify
  after insert on public.activity_logs
  for each row execute function private.notify_from_activity();

revoke all on function
  private.notify(uuid[], public.notification_kind, text, uuid, text, text), private.active_admin_ids(),
  private.project_title(uuid), private.notify_from_activity()
from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Read state (recipient only)
-- ---------------------------------------------------------------------------
create function public.mark_notification_read(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
begin
  update public.notifications set read_at = coalesce(read_at, now())
  where id = p_id and recipient_id = v_uid;
  if not found then
    raise exception 'Notification not found.' using errcode = 'ES422';
  end if;
end;
$$;

create function public.mark_all_notifications_read()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_user();
  n integer;
begin
  update public.notifications set read_at = now() where recipient_id = v_uid and read_at is null;
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke all on function public.mark_notification_read(uuid), public.mark_all_notifications_read()
from public, anon, authenticated;
grant execute on function public.mark_notification_read(uuid), public.mark_all_notifications_read()
to anon, authenticated;
