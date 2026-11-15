# Phase 10: notifications, metrics and audit view (design)

Decision: KB10 adopted 2026-11-14 (owner: "accept recommended"). In-app delivery now; every
notification also queues an email row in an outbox that nothing sends until production SMTP exists
(launch gate). No external services.

## 1. Schema

- `notification_kind` enum: `inquiry_new`, `application_new`, `applicant_response`,
  `counteroffer`, `submission` (to admins); `application_decision`, `application_request` (to
  applicant); `invitation`, `assignment_confirmed`, `revision_requested`, `payment_paid` (to editor).
- `public.notifications`: `id uuid`, `recipient_id` (profiles, cascade), `kind`, `entity_type`
  (`client_inquiry` | `editor_application` | `project` | `payment`), `entity_id uuid`, `title`,
  `body` (safe text), `created_at`, `read_at`. Index `(recipient_id, created_at desc)` and a
  partial unread index.
- `private.notification_outbox`: `notification_id` (cascade), `recipient_id`, `kind`, `status`
  (`queued` | `sent` | `failed`, default `queued`), `created_at`. Private schema: no API access.

## 2. Writing notifications

One trigger, `after insert on activity_logs` → `private.notify_from_activity()` (security
definer). It reuses the audit rows every earlier phase already writes, so no workflow function
changes:

| Audit action                                | Kind                   | Recipients              | Entity      |
| ------------------------------------------- | ---------------------- | ----------------------- | ----------- |
| `inquiry.submitted`                         | `inquiry_new`          | all active admins       | inquiry     |
| `application.submitted`                     | `application_new`      | all active admins       | application |
| `application_request.answered`              | `applicant_response`   | all active admins       | application |
| `assignment.counteroffer_pending`           | `counteroffer`         | all active admins       | project     |
| `submission.submitted`                      | `submission`           | all active admins       | project     |
| `application.approved` / `.rejected`        | `application_decision` | the applicant           | application |
| `application_request.created`               | `application_request`  | the applicant           | application |
| `project_access.granted` (reason `invited`) | `invitation`           | the editor              | project     |
| `assignment.confirmed`                      | `assignment_confirmed` | the editor              | project     |
| `revision_request.created`                  | `revision_requested`   | the assignment's editor | project     |
| `payment.paid` (kind `assignment`)          | `payment_paid`         | the payment's editor    | payment     |

Active admins = `admin_users.revoked_at is null`. Text never contains client names, contacts,
client pricing or inquiry content; editor/applicant text uses at most the project title (already
editor-visible). Admin text is generic too. Each notification inserts one outbox row.

## 3. RLS and functions

- `notifications`: RLS on; `select` for `authenticated` where `recipient_id = auth.uid()`; no
  insert/update/delete grants. Read state changes only via functions.
- `public.mark_notification_read(p_id uuid)` → void; `ES401` signed out, `ES422` if not the
  caller's. `public.mark_all_notifications_read()` → int (rows marked). Both granted to `anon` and
  `authenticated` (guardrail), authorise in the body.
- `public.admin_dashboard_metrics()` → jsonb; `private.require_admin()` (aal2). Computed live from
  stored data only (KB §14):
  - inquiries by status, conversion rate (`converted` / non-spam total);
  - applications by status; active editors;
  - projects by status (not archived);
  - median hours from project creation to confirmed assignment;
  - editor acceptance rate (accepted/confirmed/in progress over decided offers) and counteroffer
    rate (assignments with an editor `counter`);
  - on-time submission rate (`not is_late`), first-submission approval rate (reviewed version 1);
  - average client revision rounds per project with submissions, editor-caused corrections count;
  - payments (kind `assignment`) count and sum by status and currency.
    Not computable yet (no data): gross contribution (client pricing per project not normalised),
    admin time per project, editor abandonment.

## 4. Screens

- Bell with unread count in the shared `AppShell` (admin, editor); the applicant area has no shell,
  so `/apply` gets a small header link. Count read server-side inside `<Suspense>`.
- `/notifications` (any signed-in account): list newest first (limit 100), unread marked by text
  and weight, "Mark read" per row and "Mark all read" (server actions), links by entity:
  inquiry → `/admin/inquiries/{id}`, application → `/admin/applications/{id}` (admin) or `/apply`,
  project → `/admin/projects/{id}` or `/editor/projects/{id}`, payment → `/editor/earnings`.
- `/admin` Overview: metric cards and CSS bar charts (labelled values, no new dependencies).
- `/admin/activity`: read-only `activity_logs` list (latest 200), filter by entity type and action
  via query params, plain labels from `activity-labels.ts`.

## 5. Calls

- Notifications from the audit trail, not from each workflow function (one place, no regressions).
- Applicant decision on approval links to `/editor` (the applicant becomes an editor).
- Outbox is private; sending is a launch task (SMTP, KB2 domain).
- Tests: pgTAP `090`–`093` (schema/RLS, triggers per event, functions, metrics/security).
