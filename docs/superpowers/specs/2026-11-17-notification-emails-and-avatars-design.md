# Notification emails and profile pictures: design

**Status: approved by the owner 2026-11-17 ("go with your recommendations"). Two independent
features, built one after the other: A (emails), then B (pictures).** Local database and local
tests first; hosted steps are separate and need their own go-ahead.

## A. Emails for in-app notifications

### Goal

Editors and applicants get an email when something that needs them happens; admins get one
summary email per day instead of one per event. Nothing about client data, prices, briefs or
amounts is ever put in an email.

### What exists

`private.notify()` writes `public.notifications` and queues one `private.notification_outbox` row
(`status` queued | sent | failed) per recipient. Nothing sends them. SMTP (Brevo, sender
`no-reply@editstation.work`) works for auth emails only.

### Decisions (owner-approved)

1. **Who gets what.** Individual email: editor and applicant kinds (`application_decision`,
   `application_request`, `invitation`, `assignment_confirmed`, `revision_requested`,
   `payment_paid`, and the opportunity and payout kinds that go to editors). Admin kinds
   (`inquiry_new`, `application_new`, `applicant_response`, `counteroffer`, `submission`, and any
   other kind sent to admins) go into **one summary per admin per Colombo calendar day**.
2. **Content.** Subject and short heading come from the notification `title`. The body is fixed
   text ("Open EDITSTATION to read the details") plus a sign-in link to `/notifications`. The
   notification `body` is **never** put in an email (it can contain project titles). Admin summary:
   counts per kind only.
3. **Service key.** Used by exactly one server route, server-only, never `NEXT_PUBLIC_`, never
   imported from client code.
4. **Limits.** Free-plan daily send limit is respected by a per-run cap and by claiming oldest
   first; excess stays queued.

### Architecture

- **Migration** (new, never edit applied ones): add to `private.notification_outbox`:
  `attempts int not null default 0`, `last_error text` (short, no PII), `claimed_at timestamptz`.
  Add `digest boolean` (true for admin kinds, decided at insert by kind via a helper).
- **Public functions** (anon + authenticated executable per the project guardrail; each authorises
  in its body that the caller is the `service_role` and raises `ES403` otherwise; `search_path ''`,
  revoke from public): `worker_claim_emails(p_limit int)` returns queued individual rows (claim with
  `for update skip locked`, join recipient email and notification title, only for recipients with a
  confirmed email); `worker_claim_admin_digest(p_now timestamptz)` returns at most one row per
  active admin per Colombo day with kind counts (only when there are queued admin-kind rows and no
  digest was sent that Colombo day; marks those rows claimed); `worker_mark_email(p_id bigint,
p_ok boolean, p_error text)` sets sent/failed (3 attempts then failed). Locks: outbox rows plus one non-blocking transaction advisory lock.
- **Route** `src/app/api/cron/send-emails/route.ts` (POST): requires
  `Authorization: Bearer ${CRON_SECRET}` compared in constant time; creates a server-only Supabase
  client with `SUPABASE_SECRET_KEY` (new `src/lib/supabase/service.ts`, `import "server-only"`);
  claims, renders, sends via Brevo's transactional API (`POST https://api.brevo.com/v3/smtp/email`,
  `BREVO_API_KEY`, plain `fetch`, **no new dependency**), marks results. Returns counts only.
  Not part of any page, `noindex`, no CORS.
- **Templates** in `src/features/notifications/email/`: one shared HTML layout (same look as the
  auth emails), one individual template, one admin summary template, plain-text alternative.
  Pure functions, unit tested (no body leakage, escaping, link built from `SITE_URL`).
- **Scheduler:** Postgres `pg_cron` + `pg_net` on hosted calls the route every 5 minutes with the
  secret. Hosted setup is documented in `docs/RUNBOOKS.md`; the owner runs the SQL (the
  automatic permission check blocks the assistant from running it). Not built in the migration
  (local stack has no pg_net), so no migration depends on it.
- **Env** (documented in `.env.example`): `SUPABASE_SECRET_KEY`, `CRON_SECRET`, `BREVO_API_KEY`,
  `EMAIL_FROM` (default `EDITSTATION <no-reply@editstation.work>`).

### Anti-goals

No client data, prices, brief text, links or amounts in any email. No marketing email. No
unsubscribe-from-essential. No email to unconfirmed addresses. No raw errors to users.

### Tests

pgTAP (as admin, editor A, editor B, applicant, anon, service role): the worker functions raise
`ES403` for everyone except `service_role`; a claimed row is not claimed twice; digest rows are
grouped once per Colombo day; failed rows stop after 3 attempts; recipients cannot read the outbox.
Vitest: templates and the route's auth and result handling with a fake sender.

## B. Profile pictures

### Goal

Any signed-in account (admin, applicant, editor) can add an optional picture of themselves. It is
shown to the owner and to admins only.

### Decisions (owner-approved)

1. **Who sees it:** the owner and admins. Never clients, never other editors, never public.
2. **Who can set one:** any registered account (admin, applicant, editor).
3. **Optional**, replaceable, removable.

### Architecture

- **Storage bucket** `avatars`, **private**, file size limit 2 MB, allowed types jpeg, png, webp.
  Object path `<user_id>/avatar.<ext>` (one current picture per user).
- **Migration:** `public.profiles.avatar_path text` (nullable, check it matches
  `^<own id>/avatar\.(jpg|png|webp)$` in the writer function, not as a table check) and the bucket
  plus `storage.objects` RLS policies: insert/update/delete only for the owner's own folder
  (`(storage.foldername(name))[1] = (select auth.uid())::text`); select for the owner or
  `(select private.is_admin())`. Writes to `profiles.avatar_path` only through
  `public.set_my_avatar(p_path text)` and `public.clear_my_avatar()` (authorise in body, ES
  errors, audited with ids and field names only). Admin read is via signed URLs created
  server-side after `requireAdmin()`.
- **Upload path:** server action validates type and size and re-checks the file's real type
  (magic bytes), uploads with the user's own session (RLS enforces the folder), then calls
  `set_my_avatar`. Images are not processed server-side (no new dependency); the form tells the
  user the size and type limits. Display via a small `Avatar` component with initials fallback;
  signed URLs expire in minutes and are never cached across users.
- **Where it shows:** the app header user menu, the editor profile form (upload, replace,
  remove), the admin application review page and the admin editor access view.
- **Anti-goals:** no public URL, no hotlinking, no storing images in Postgres, no moderation
  queue in this version (an admin can clear a picture via the existing admin tools if added later;
  out of scope now).

### Tests

pgTAP as admin, editor A, editor B, applicant, anon: owner can write only their own folder; another
editor and anon cannot read or write it; admin can read all; `set_my_avatar` rejects another
user's path and bad extensions; `clear_my_avatar` clears only own. Vitest for validation and the
signed-URL helper. A note in the plan if the local stack lacks storage-api (then pgTAP covers
policies against the `storage` schema if present, and the upload path is exercised on hosted
smoke test only).

## Order, boundaries, constraints

A first (no storage dependency), then B. Each: builder, `db-security` and `code-reviewer` reviews,
fixes, `npm run check`, `npm run db:test`, `npm run db:advisors`, `npm run db:types`, my own
verification, then commit and push (owner's standing rule), then hosted steps one at a time with
the owner. Never edit applied migrations. No change to RLS elsewhere, payments, or workflows. No
new dependency without a stated reason.
