# Security and Privacy

Derived from KB §7.3, §8.2, §11.3, §12.3 and the owner clarification of 2026-11-11. Not legal advice.

## Owner security requirements (2026-11-11)

1. Default-deny RLS. 2. Never rely on frontend visibility. 3. Pending applicants cannot access
   editor-only resources. 4. Only authorised admins approve/reject applications. 5. Only authorised
   admins change editor roles or activation status. 6. Editors cannot directly modify assignments,
   agreed compensation, payment status or admin review fields. 7. Internal client information is kept
   apart from editor-visible project information. 8. Secrets and service-role credentials stay
   server-side. 9. RLS tested as anonymous, pending applicant, approved editor A, approved editor B,
   admin. 10. Important admin actions are audit-logged.

The public registration flow must not weaken any of these.

## Threat model additions from public entry points

| Threat                                                                     | Mitigation                                                                                                                                                                                                    |
| -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Self-registered user tries to become editor/admin                          | No role in sign-up metadata is trusted; trigger always creates `access_status = 'none'`; `admin_users` and `access_status` are writable only through admin-only functions; pgTAP tests attempt the escalation |
| Applicant reads projects or other editors                                  | Every editor-facing policy requires `is_active_editor()`, not just "signed in"                                                                                                                                |
| Applicant edits their own application after submission, or sets its status | Column-level grants plus policies limit applicant edits to non-status fields while `draft` / `info_requested`; status changes only via functions                                                              |
| Inquiry form spam / bot sign-ups                                           | Captcha (Supabase Auth supports captcha on sign-up) and rate limits (question O); honeypot field                                                                                                              |
| Anonymous user reads inquiries                                             | `anon` has execute on `submit_client_inquiry()` only; no SELECT on any table                                                                                                                                  |
| Suspended editor keeps working                                             | Access helpers read the table on every query; optional forced sign-out                                                                                                                                        |
| Admin account takeover                                                     | TOTP MFA required for admins (decision A), enforced in admin policies and the admin gate via the session assurance level (`aal2`)                                                                             |
| Malicious links in inquiries/applications                                  | Store and display as plain text/escaped links; never fetch or embed them server-side                                                                                                                          |

## Access helpers (implemented in Phase 1)

`private.is_admin()` (admin row **and** `aal2` MFA session), `private.is_admin_account()` (routing
only, never for authorisation), `private.is_active_editor()`; `current_editor_id()` to follow when
needed. `security definer`, `stable`, `set search_path = ''`, in the non-exposed `private` schema,
called as `(select private.is_admin())` in policies so they run once per statement.

## Function placement rule (Phase 1 finding)

In the local Supabase Postgres image (17.6.1.106), a "permission denied for function" raised for
`anon`/`authenticated` crashes the database (supautils permission-hint bug). Therefore:

- Internal functions go in `private` (not reachable through the API).
- Every function in `public` must be executable by both `anon` and `authenticated` and enforce
  authorisation inside its body. A pgTAP guardrail (`000_rls_guardrail.test.sql`) enforces this.
- Tests check function privileges with `has_function_privilege`, never by calling a forbidden
  function as an API role.
- Re-check on hosted Supabase before launch.

## Admin bootstrap

`private.grant_admin_by_email(email, note)`: executable only by `postgres` (SQL editor or psql).
Audited. The first admin must then enrol TOTP before any admin data becomes visible.

## Application workflow controls (implemented in Phase 2)

- Applicants write only their own profile, options and links (RLS + column grants, or the atomic
  `public.save_editor_profile`). Applications, requests and decisions change only through
  `public.*` functions that check the caller and the current status; no direct writes.
- Admin functions call `private.require_admin()` (admin row **and** MFA). Approval is the only path
  that sets `access_status = 'active'`; revoked is final; activation from `none` is impossible
  except by approval.
- Submissions store a frozen `submitted_snapshot`, so later profile edits cannot change what was
  reviewed.
- Vetting notes are admin-only (RLS); `decision_message` is the only decision text the applicant sees.
- Links: https only (DB check + zod); rendered with `rel="noopener noreferrer nofollow"`; never
  fetched server-side.
- Errors: functions raise `ES401`/`ES403`/`ES409`/`ES422` with user-safe messages; any other
  database error is shown as a generic message.
- Account deletion anonymises audit entries (actor cleared) rather than failing; the log stays
  append-only otherwise. Sessions whose account no longer exists are treated as signed out.

## Public inquiry controls (implemented in Phase 3)

- Anonymous visitors: `select` on **active** `service_types` and `budget_ranges` only (needed by
  the public form); execute on `public.submit_client_inquiry`, which returns nothing. No access to
  inquiries, links, notes or the throttle table.
- Abuse limits in the database (3/hour per email, 5/hour per hashed source, 100/hour overall) plus
  an app honeypot. Turnstile is required before public launch (decision O).
- The client IP is never stored: only a SHA-256 hash, kept one hour, for rate limiting.
- Inquiry audit entries contain no personal data; an actor is recorded only if that profile exists.
- Inquiry data is admin-only (MFA); `converted` is set only by `admin_convert_inquiry` (Phase 4).

## Project, brief and client controls (implemented in Phase 4)

- `clients`, `projects`, `project_internal`, `brief_versions`, `project_deliverables` and
  `project_references` have RLS on and an admin-only (`private.is_admin()`, MFA) `select` policy.
  Editors, applicants and anonymous users have no access. Nobody, admins included, has a direct
  insert/update/delete grant: writes go only through `public.admin_*` functions (`require_admin()`
  in the body, `ES4xx` errors).
- Client identity and client price live only in `project_internal` / `clients`, never on `projects`.
- Brief versions are immutable after the project's first opening (`first_opened_at`, set once and
  guarded by trigger): before it, version 1 is edited in place; after it, any content change
  inserts version n+1 with a required change summary, and a trigger blocks changing existing
  versions.
- Phase 5-6 editor `select` policies may cover `projects`, `project_deliverables`,
  `project_references` and `brief_versions` only, never `project_internal` or `clients`.

## Editor access controls (Phases 5-6, implemented on branch, pending owner review)

- Editor reads are tiered by `private.editor_project_stage(project_id)` (`none` / `opportunity` /
  `assigned`, decision B), granted to `authenticated` only because RLS policies call it. Each table
  has one combined `select` policy (`(select private.is_admin()) or <editor rule>`).
- Every editor rule requires `private.is_active_editor()`: suspending or revoking an editor hides
  everything immediately, their own assignments and history included. Cancelled and archived
  projects are `none` for every editor.
- `asset_access_grants` and `project_notes` are admin-only; editor-readable new tables
  (`project_assets`, `project_access`, `assignments`, `negotiation_offers`) hold no client data.
- Editors write only through `editor_respond_offer` (own offer, from `offered`, project open);
  another editor's offer and an unknown id both return "Offer not found.". Only an admin confirms
  (one confirmed per project, enforced by a partial unique index and row locks); confirmation
  revokes every other editor's access.
- Assignment transitions are enforced in the functions and by a guard trigger; negotiation
  history and notes are append-only (update and delete refused by trigger, for postgres too).
- Folder shares are recorded by hand; `admin_pending_revocations()` lists live shares whose editor
  is not active, whose project is closed, or whose editor has no live assignment.
- Audit details hold ids and statuses only (no amounts, messages, emails, links or note text).

## Confirmation gate controls (Phase 7, implemented on branch, pending owner review)

- `editor_interpretations` and `brief_confirmations`: select-only grants, one combined policy each
  (admin, or own rows and `private.is_active_editor()`); no client data or client pricing.
- Editors write only through `editor_submit_interpretation`, `editor_confirm_brief` and
  `editor_start_work`; another editor's and an unknown assignment both return "Assignment not
  found."; locks follow project → assignment (`private.lock_assignment`). Admins review
  interpretations and may start work on the editor's behalf (`admin_start_work`, editor must be
  active).
- In-progress gate enforced in the database: `BEFORE UPDATE` triggers refuse moving an assignment
  to `in_progress` unless `private.assignment_gate(..).ready` (admin-approved pay, current brief
  version confirmed without deadline/pay drift, interpretation accepted where required), and a
  project to `in_progress` without an `in_progress` assignment. This holds for the table owner too.
- Confirmations are immutable (`guard_append_only`); interpretations allow one review update and
  actor clearing only. Brief versions referenced by confirmations cannot be deleted (trigger and FK).
- Brief confirmation is optimistic: the editor sends the version, deadline and pay they saw; a
  mismatch is refused.
- Audit details: ids, version numbers and kind only (no amounts, deadlines, deliverables or text).

## Submission and review controls (Phase 8, implemented on branch, pending owner review)

- `submissions` and `revision_requests`: select-only grants, one policy each (admin aal2, or the
  owning editor while `private.editor_project_stage(project) <> 'none'`); no write grants; no
  client data, client pricing or money columns. Links only (https), never media.
- Editors write only through `editor_submit_work` (own `in_progress` assignment, Phase 7 gate
  `ready`, no pending submission, no disputed request) and `editor_acknowledge_revision`. Admins
  use `admin_review_submission`, `admin_approve_project`, `admin_classify_revision`,
  `admin_complete_project`. All raise `ES4xx` only.
- Guards hold for the table owner: submission content immutable (one review update, actor
  clearing), revision links immutable and status moves limited to the lifecycle, no deletes; the
  project statuses `in_review`/`revision_requested`/`approved`/`completed` need their facts
  (pending submission, open request, approved latest submission, prior `approved`).
- Audit details: ids, version, `is_late`, outcome/type/status names and round number only (no
  links, notes, export details, feedback, reasons or dates).

## Notification and metrics controls (Phase 10, implemented on branch, pending owner review)

- `notifications`: RLS on; `select` only where `recipient_id = auth.uid()`; no insert/update/delete
  grants. Read state changes only through `mark_notification_read` (ES401 signed out, ES422 not
  the caller's) and `mark_all_notifications_read` (own rows only).
- The notification trigger swallows its own errors (warning only), so a malformed log entry can
  never roll back the audited action. Accepted: a revoked admin keeps read access to notifications
  already received (content is ids-free fixed text and project titles only).
- Rows are written by a security-definer trigger on `activity_logs`; text is generic and uses at most
  the project title (already editor-visible). No client names, contacts, prices or inquiry content.
- `private.notification_outbox`: no API access (private schema, all privileges revoked from
  anon, authenticated and service_role). Read and changed only through the three `worker_*`
  functions, which authorise in their body that both the database role and the JWT role claim are
  `service_role` (ES403 for anon, every signed-in account and admins, MFA or not).
- **Service key (`SUPABASE_SECRET_KEY`)**: used by exactly one server route,
  `/api/cron/send-emails`, through `src/lib/supabase/service.ts` (`import "server-only"`, never
  `NEXT_PUBLIC_`). The route requires `Authorization: Bearer <CRON_SECRET>` (constant-time compare;
  every request is rejected when `CRON_SECRET` is unset), returns counts only, sends `noindex`
  (`X-Robots-Tag` on `/api/:path*`) and has no CORS. Logs carry database error codes only: no
  addresses, keys or provider responses. Hosted scheduling is `pg_cron` + `pg_net` with the bearer
  in Supabase Vault (`RUNBOOKS.md` section 8).
- **No client data in emails.** An email carries the notification title (escaped), fixed text and
  a link to `/notifications`; the notification body (which can name a project) is never read by
  the worker. Admin summaries carry counts per kind only. No email goes to an unconfirmed address.
  Brevo (the email processor) receives the recipient address, subject and this fixed content.
- `admin_dashboard_metrics()` and `/admin/activity` are admin-only (MFA `aal2` via
  `private.require_admin()` / `activity_logs` RLS). The activity view is read-only and accepts
  only known filter values. pgTAP `090`-`092`.

## Project terms controls (Phase 12A, implemented on branch, pending owner review)

- `project_terms` and `project_terms_stages` hold client pricing (extra-round charge, client
  cancellation percentages): RLS on, `select` for MFA admins only, no write grants for any API
  role. Editors, applicants and anon read nothing from them.
- Editors reach terms only through `editor_get_terms` (active editor, opportunity or assigned stage,
  otherwise ES422 not found): included rounds, editor milestone shares and editor kill-fee shares.
  pgTAP checks its result columns and values carry no client data.
- Immutability is enforced by triggers for every caller: agreed terms cannot be edited or deleted,
  only superseded; stage rows change only on drafts; `projects.revision_allowance` can only follow
  the agreed terms.
- `admin_agree_terms` locks the project row and accepts only the current draft, so concurrent
  agreements cannot both succeed. Editor pay terms cannot change while an editor is confirmed.
- Audit rows hold ids, version and field names only (no amounts, percentages or reasons). pgTAP
  `093`-`095` (admin, editor A, editor B, applicant, anon, suspended).

## Asset access controls (Phase 12B, implemented on branch, pending owner review)

- A working URL is never proof of access (KB7a-1): only `admin_verify_asset` (MFA admin) sets
  `verified`; an editor's "I can open this" is stored separately and never changes the status. A
  changed link or provider resets verification.
- `asset_access_reports` is append-only for every caller (trigger: no delete, no edits except
  resolving once and foreign keys going null). No write grants; reports are inserted only by
  `editor_report_asset_inaccessible`, which requires the active editor at the `assigned` stage of
  the asset's project (unknown and foreign assets both ES403, so asset ids are not confirmed).
  RLS: an active editor reads only their own reports; a suspended editor reads none.
- Editor-readable `project_assets` columns hold no client identity or pricing (pgTAP); the asset
  form warns admins not to put passwords in access instructions. Folder shares (with the editor's
  email and the access type) stay admin-only. `anyone_with_link` shares carry a security warning
  on the admin screens.
- Revocation: the client owns the folder, so the checklist records a removal request and the
  client's confirmation; ending an assignment never marks access removed (pgTAP).
- Notifications to admins say only that an asset on a named project cannot be opened; the
  editor's note is not copied. Audit rows hold ids only. pgTAP `096`-`098` (admin, editor A,
  editor B, applicant, suspended, anon).

## Client billing controls (Phase 12C, implemented on branch, pending owner review)

- `client_milestones` (client amounts, transfer references, due dates) and `app_settings` are
  admin-only: RLS select for MFA admins, no write grants, no anon access. Editors A and B, the
  pending applicant and a suspended editor read nothing (pgTAP `099`).
- Editors learn only a yes/no `client_deposit_verified` from `get_assignment_gate` (their own
  assignment) and the status text "Waiting for the client deposit"; never amounts, due dates or
  references (KB9a-5). Every public function that reads `client_milestones` calls
  `require_admin` (pgTAP `100`). Auto-hold notifications go to admins only.
- Guard trigger (holds for the table owner): no delete; amount, currency, kind and identity are
  frozen; `expected -> received_unverified -> verified`; verified is final except
  `admin_correct_client_payment` (reason required; refused for a deposit once work began or for a
  refunded payment); refunds are negative rows that never exceed the payment they reverse.
- Start gate: `private.assignment_gate` requires a verified deposit (start functions, the
  `in_progress` guard trigger and submissions all use it). `assigned -> on_hold` happens only in
  `private.apply_timed_rules`; `admin_set_project_status` refuses it.
- Audit rows hold ids and field names only (no amounts, references, dates or reasons). pgTAP
  `099`-`101` (admin, admin without MFA, editor A, editor B, applicant, suspended, anon).

## Editor pay milestones and dispute splits (Phase 12D part 1, implemented on branch, pending owner review)

- Editors still never read `payments` rows directly. `editor_list_payments` (replaced) returns
  their own rows with the milestone number, an enum `hold_label` (`under_review`,
  `assignment_ended`, `waiting_for_client_payment`) and `waiting_on_client`. It never returns the
  free-text `on_hold_reason` (including dispute reasons) or `reversal_reason`, the `payable_reason` (it would reveal a
  late client balance), admin ids or any client money (KB9a-5; pgTAP `103`, `075`, `076`).
- `waiting_on_client` is a boolean maintained only by database functions/triggers from client
  milestone facts; it says only that client money is outstanding, never how much or when.
- Dispute split (`admin_split_payment_for_dispute`): MFA admin only (anon ES401; admin without
  MFA, editors A and B, suspended editor and applicant ES403; pgTAP `104`). Guards hold for the
  table owner: amounts change once, only inside the function; parts always sum to the original
  (`payments_split_sum`); paid rows stay final.
- Accepted inference (coordinator, 2026-11-15): an editor can work out the day the client balance
  was verified (or protection applied) from a later milestone's `due_date` minus the editor pay
  days. Only the day leaks, never amounts or references.
- `reversal_reason` is not editor-visible either: editors see a reversal row as "Reversed" only.

## Extra pay, scope quotes and cancellation settlement (Phase 12D part 2, implemented on branch, pending owner review)

- `compensation_adjustments`, `scope_change_quotes` and `cancellation_settlements`: RLS on, MFA
  admin select only, no write grants for any API role; guards hold for the table owner (pgTAP
  `105`). Editors read their own offers only through `editor_list_adjustments` (editor pay, note,
  status; never admin ids, the quote or client money) and the gate code of their own request
  through `editor_revision_gate` (`ok`, `needs_extra_pay`, `waiting_for_scope_approval`; no client
  amounts or dates). Editor B sees nothing of editor A (pgTAP `106`, `108`).
- Client quotes, extra-round and scope charges, refunds, client charge percentages and the
  client side of a settlement stay in admin-only tables (`scope_change_quotes`,
  `client_milestones`, `cancellation_settlements`, `project_terms_stages`). Adjustment rows hold
  only editor pay in the agreed currency.
- `editor_list_payments` adds a fixed `line_kind` label (milestone, extra round, scope change,
  extra cancellation pay, cancellation settlement, cancellation reconciliation); settlement
  reversal reasons and the admin's adjustment reason stay admin-only.
- The extra-work gate is enforced by the revision-request guard trigger, so no API path
  (acknowledge, start, submit) can begin a blocked change. `cancelled` payments are final and set
  only inside `admin_settle_cancellation` (transaction-local flag), never by hand or by the table
  owner without it (pgTAP `107`).
- Every new public function is executable by anon and authenticated, revoked from PUBLIC,
  `security definer` with an empty `search_path`, and authorises in its body: admin functions
  ES401 for anon and ES403 without an MFA admin session; editor functions ES403 for admins,
  suspended editors and applicants (pgTAP `108`). Audit rows hold ids, enum names and field names
  only (never amounts, reasons, notes or dates).
- A begun change request cannot be reclassified as a scope change (it would skip the quote and
  extra pay gate), and a scope offer needs the client's accepted quote (pgTAP `106`).
- Extra-work client payments are excluded from the settlement refund; reassignment (not
  cancellation) keeps the Phase 9 hold on the ended editor's unpaid payments for the admin to
  resolve, and a later cancel does not settle them (owner to confirm).
- Accepted inference: an editor who accepts extra pay learns that Lenscape agreed extra work for
  the client, not its price.
- Late-balance protection runs in `private.apply_timed_rules` (no API grant); its audit rows hold
  ids and the enum reason, and only admins are notified. Lock order is project, assignments,
  payments everywhere the payable rules run.

## Payout details controls (Phase 12E, LOCKED, implemented on branch, pending owner review)

- **Locked by default.** `app_settings.payout_details_enabled` is `false`. While false, every
  payout write function raises ES409 ("not enabled yet") and guard triggers refuse inserts into
  `editor_payout_details` and `editor_payout_detail_versions` even for the table owner, so no bank
  data can be stored (pgTAP `109`). Only `admin_set_payout_enabled` (MFA admin) changes it; each
  change is audited. `/admin/settings` warns that it must stay off until counsel confirms PDPA
  handling and needs a confirmation box. pgTAP enables it only inside its own rolled-back
  transaction with obviously fake values.
- **No API grants.** The three payout tables have RLS on, no policies and no privileges for anon,
  authenticated or PUBLIC (pgTAP `109`). Every read and write is a `security definer` function
  with an empty `search_path`, executable by anon and authenticated, revoked from PUBLIC, that
  authorises in its body (pgTAP `111`).
- **Masking and reveal.** Editors read only their own row through `editor_get_payout_details`
  (account number masked to the last 4); editor B never sees editor A (pgTAP `110`). Admins see
  the masked view; `admin_reveal_payout_details` requires a reason and always writes
  `payout_details.revealed` (admin, editor, reason). The number is shown once in the action result
  and never written to the page or logs.
- **Payment-redirection protection.** Any change creates a version row, resets the status to
  unverified, audits the changed field names and notifies admins (`payout_details_changed`).
  Verification records method, note, admin and time for the exact version the admin saw.
- **Mark-paid gate (E-1, call 1).** `admin_mark_payment_paid` refuses (ES409, with how to fix it)
  unless the editor has verified details (flag on) or a current "payout account verified outside
  the app" attestation (flag off; admin and date, no bank data; retired once the flag is on).
- **Never logged.** Audit rows and notifications hold ids, versions and field names only; pgTAP
  `110` asserts no fake bank value appears in `activity_logs` or `notifications`.
- **Locked means no new data, not no data.** Turning the flag off again does not purge stored
  rows: masked reads stay, but saving, verifying and revealing the full number are refused (ES409)
  and attestations count again. Purging is a separate owner decision (retention, question P).
- **Flag races.** Every function acting on the flag holds the settings row `for share`
  (`private.lock_payout_flag`); `admin_set_payout_enabled` takes the row lock, so a save, attest,
  verify, reveal or mark-paid cannot act on a stale value. Lock order: payment, settings, payout
  row. Not covered by an automated test (needs two sessions; see CHANGELOG follow-up).
- **Reveal reasons are logged**, so a reason with a run of 6+ digits is refused (ES422) and the UI
  warns not to type bank details there.
- **Backups and PITR.** Once the flag is on, bank values sit in plaintext in database backups,
  point-in-time-recovery WAL and any `pg_dump` (including `npm run db:restore-test` dumps).
  Restricting who can download backups, their retention, and that restored copies hold the same
  data must be part of counsel's review; field-level encryption (below) is the main mitigation.
- **No field-level encryption in this slice (decision recorded 2026-11-16).** Bank values are
  protected by the absence of API grants, function-only access, audited reveals, Supabase disk
  encryption at rest and TLS. Options if counsel or the owner require more before turning the
  flag on: Supabase Vault / `pgsodium` column encryption (keys managed by Supabase; note pgsodium
  is being deprecated in favour of Vault), or app-level encryption with a server-only key (the
  database then never sees plaintext, but masking and reveal move to the server). Both need an
  owner decision and a migration; neither is built.

## Open opportunity controls (B/C amended 2026-11-16, implemented on branch, pending owner review)

- **Summary only, written separately.** `project_opportunities` holds only what the admin writes
  for editors; it is never a filtered copy of brief or client columns. pgTAP `112` pins its column
  list and refuses any client/price/brief/link column; `113` checks the editor projection never
  contains the project title or the client price. Hidden pay is not stored (null), because RLS is
  row-level and cannot hide a column.
- **Active editors only.** Pending applicants, suspended or revoked editors, admins without MFA
  and anon read no row and `editor_list_opportunities` refuses them (ES401/ES403); an editor reads
  only their own interest rows (editor B never sees editor A's interest or proposed rate).
- **No API writes.** Both tables have RLS on and no write grants. `project_opportunities` has a
  column-level `select` for authenticated that omits `project_id`, `published_by` and `closed_by`
  (pgTAP `112`); admins read those through `admin_get_opportunity`.
  Every write is a security definer function with an empty `search_path`, executable by anon and
  authenticated, revoked from PUBLIC, authorising in its body with ES401/403/409/422 only
  (pgTAP `114`). Guard triggers keep interests append-style even for the table owner.
- **Pay is unchanged.** Choosing an editor calls `admin_make_offer`; the proposed rate is never
  used as the offer (pgTAP `113` compares the result with a direct offer field by field).
- **Races.** Selection locks project, opportunity, then interests: a second selection, a
  withdrawal, a cancelled or on-hold project, a suspended editor or an editor with a live offer
  gets ES409 with a clear message. The limit uses a per-editor advisory lock. Concurrency is not
  exercised by a two-session test (single-session pgTAP).
- **Notifications** to editors use the opportunity title only, never the project title (pgTAP
  `113`); audit rows hold ids and field names only.
- **Confidentiality notice** on `/editor/opportunities` (call 7). It is a reminder, not a control.

## Profile picture controls (2026-11-17, uncommitted, pending review)

- **Who sees it:** the owner and admins with an MFA session only. Never clients, other editors or
  the public. Enforced twice: `profiles` RLS for `avatar_path`, and `storage.objects` RLS on the
  private `avatars` bucket. There is no public URL; the app shows pictures through signed URLs
  that expire after 5 minutes, created server-side per request with the viewer's own session
  (owner after `requireSignedIn()`, admin after `requireAdmin()`), never cached across requests
  or users, and never through the secret key.
- **Writes:** any signed-in account may upload only into its own folder (`<user_id>/avatar.<ext>`;
  other names, renames, sub-folders and other users' folders are refused by RLS, admins
  included). `profiles.avatar_path` has no column grant: `set_my_avatar` requires the caller's own
  path and an existing object; `clear_my_avatar` touches only the caller's row. Errors are
  ES401/ES422 only; the UI shows only `userMessageFromDbError` messages and a fixed
  upload-failure message.
- **File checks: two paths, different strength.**
  - _App path (the server action):_ declared type and size (Zod), then the file's real type from
    its magic bytes, so SVG/HTML or other content renamed as an image is refused; the object is
    stored with the detected content type. No server-side image processing (no new dependency).
  - _Direct Storage API path:_ a signed-in user can call the Storage API with their own session
    and bypass the server action. That path is limited only by the bucket's declared-type and size
    limits (JPEG/PNG/WebP content type, 2 MB, enforced by storage-api) and by the folder policies;
    the magic-byte check does **not** apply, so the bytes may not be an image.
  - _Mitigation on read:_ before signing, the app reads the object's stored content type
    (`info()`, same session) and signs only `image/jpeg`, `image/png` or `image/webp`; anything
    else is treated as no picture. Pictures are only ever rendered as `<img>` elements, never
    linked or opened as documents. A failed or refused signed URL, or an image that fails to load,
    shows the initials fallback.
- **Audit:** set and clear through the functions are logged with ids and the field name only (no
  path). A delete made directly through the Storage API is **not** audited (it leaves
  `avatar_path` pointing at a missing object, which then shows as no picture).
- **Server action body limit (accepted knowingly):** `next.config.ts` raises
  `serverActions.bodySizeLimit` app-wide to 2 MB + 64 KB so a 2 MB picture fits. Next.js has no
  per-action limit, so every server action, including the public inquiry and sign-up actions,
  now accepts bodies up to that size (default was 1 MB). Each action still validates its own
  fields. **Follow-up:** rate limiting for uploads and public actions (not built).
- **Tests:** pgTAP `116` (admin with and without MFA, editor A, editor B, pending applicant,
  anon). Bucket size/MIME limits are enforced by storage-api, so they are covered by a local
  storage-api smoke run (own-folder upload and replace, cross-folder refused, gif/html and
  over-2 MB refused, stored content type readable by the owner only, signed URL for owner only,
  no public URL, cross-user delete refused), not by pgTAP. Vitest covers the action (magic bytes,
  size, stale clean-up, safe messages) and the signed-URL helper (type allow-list, failures).
- **Out of scope now:** moderation queue; admin removal of someone else's picture.

## Client area controls (C1, 2026-11-17, uncommitted, pending review)

- **Accounts:** only an admin (MFA) creates client access. The server action
  (`src/features/client-area/admin-actions.ts`, after `requireAdmin()`) creates the auth account
  with the secret key (`src/lib/supabase/service.ts`, server-only): confirmed email, no password
  (Supabase stores a random hash nobody knows) and `app_metadata.client_invite = true`. The
  database function then re-authorises the admin and links the account; if it refuses, an account
  just created by the action is deleted again. Chosen over Supabase's invite API: no emailed
  invite link (a bearer token) exists to be forwarded or replayed, and no extra template or
  `/auth/confirm` invite type is needed. The admin tells the person to sign in at
  `/client/sign-in` (client emails are C4).
- **Pre-registration takeover:** a self-registered sign-up (which someone else could have created
  with the client's address) is never linked: `admin_invite_client_user` requires the
  service-only app_metadata flag and a confirmed email (user_metadata is ignored).
- **Sign-in:** emailed one-time code (`signInWithOtp` with `shouldCreateUser: false`, then
  `verifyOtp` type `email`); locally 8 digits valid for 10 minutes (`[auth.email]` otp_length 8,
  otp_expiry 600; hosted not changed, needs approval). The same Auth setting also bounds the
  confirmation and password-reset links. The code request always shows the same message, so it
  does not reveal whether an email is invited; the per-email send limit (only reachable for an
  existing account) gets that same message, and only the per-IP request limit differs. The e2e test proves an unknown email
  creates no account. Supabase sends a code to **any** existing confirmed account, so an editor or
  admin could also sign in by code: no weaker than the existing password-reset email, and admins
  still need MFA (aal2) for anything admin.
- **Separation:** a client account is never an admin or an editor (guard triggers on
  `client_users`, `editor_profiles` and `admin_users`). Routing (`src/lib/auth/home-path.ts`)
  checks the client membership before editor access, so the sign-up trigger's `editor_profiles`
  row (status none) never sends a client to `/apply`. A client account cannot save an editor
  profile or apply (ES403, plus a trigger on `editor_applications`). In the database a client
  otherwise has the powers of a signed-in account with no role (its own profile rows only).
- **Data:** clients have no table grants. Every read goes through `client_*` functions that check
  an active membership on every call and return fixed client-safe projections (DATABASE_SCHEMA
  "Client area C1"); the app also parses them with Zod, which drops any unexpected key. pgTAP
  proves the projection's exact key set and that it holds no editor id, pay, notes or price.
- **What clients see:** only projects past draft, never a deadline (editor-facing, may include a
  buffer), internal `approved` reads "Finalising".
- **Revocation** applies at once (archiving the client too): the next function call is refused (ES403) and routing sends the
  account to `/client/access-ended`. The session itself is not ended server-side; it has nothing
  left to read.
- **Bank details:** studio business data, admin-editable, hidden until set; the audit row records
  only that the field changed. Unrelated to editor payout details (still locked, decision E).
- **Open (owner):** client terms and privacy notice (counsel), OTP email wording, client session
  length, optional client two-step verification, and a client-facing delivery date (separate from
  the editor deadline). Runbook: RUNBOOKS §9. The OTP template
  (`supabase/templates/magic_link.html`, `[auth.email.template.magic_link]`) is configured locally
  only; pushing it to hosted needs owner approval.

## Access matrix (target; each cell becomes pgTAP tests)

| Data                               | Anonymous              | Applicant (own)                                                     | Active editor                                                                                                                                                | Admin                                |
| ---------------------------------- | ---------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------ |
| Client inquiry                     | submit only (function) | —                                                                   | —                                                                                                                                                            | full                                 |
| Own profile                        | —                      | read/update permitted fields                                        | read/update permitted fields                                                                                                                                 | full                                 |
| Own application                    | —                      | read; edit while draft/info requested; submit/withdraw via function | read                                                                                                                                                         | full; decide via function            |
| Vetting notes, assessments results | —                      | — (own test instructions only)                                      | —                                                                                                                                                            | full                                 |
| `admin_users`, `access_status`     | —                      | read own status only                                                | read own status only                                                                                                                                         | change via audited function          |
| Projects, briefs, references       | —                      | —                                                                   | project + deliverables at `opportunity`; early-access references at `opportunity`; all references and brief versions at `assigned`                           | read; write via functions only       |
| Assets                             | —                      | —                                                                   | early-access assets at `opportunity`; all at `assigned`                                                                                                      | full; write via functions only       |
| Folder shares, admin notes         | —                      | —                                                                   | —                                                                                                                                                            | read; write via functions only       |
| Asset access reports (12B)         | —                      | —                                                                   | own rows (read); report/confirm via `editor_*` functions at `assigned` only                                                                                  | read; resolve via function           |
| Client milestones, settings (12C)  | —                      | —                                                                   | none; deposit verified yes/no via `get_assignment_gate` (own assignment)                                                                                     | read; write via `admin_*` functions  |
| `project_internal`, clients        | —                      | —                                                                   | —                                                                                                                                                            | read; write via functions only       |
| Access, assignments, offers        | —                      | —                                                                   | own rows (read); answer own offer via `editor_respond_offer`                                                                                                 | read; write via functions only       |
| Interpretations, confirmations     | —                      | —                                                                   | own rows (read); submit/confirm/start via `editor_*` functions while `confirmed`/`in_progress`                                                               | read; review/start via functions     |
| Submissions, revisions             | —                      | —                                                                   | own; submit via function; no review fields                                                                                                                   | full                                 |
| Payments (Phase 9)                 | —                      | —                                                                   | no direct read (rows hold admin actor ids); own rows via `editor_list_payments` only (project, milestone, hold label; no reasons, actor ids or client money) | read; write via `admin_*` functions  |
| Payment notes (Phase 9)            | —                      | —                                                                   | —                                                                                                                                                            | read; append via function            |
| Payout details (E, 12E, locked)    | —                      | —                                                                   | own only via `editor_get_payout_details` (masked) and `editor_save_payout_details` (only when enabled)                                                       | masked via function; audited reveal  |
| Open opportunities (B/C amended)   | —                      | —                                                                   | summaries taking interest now, or with own interest; own interest rows; register/withdraw via `editor_*` functions                                           | read; write via `admin_*` functions  |
| Activity logs                      | —                      | —                                                                   | —                                                                                                                                                            | read only (no one can update/delete) |

`—` = no access. Editors B cannot see anything belonging to editor A.

## Access-control model (general)

- RLS enabled on **every** `public` table (pgTAP guardrail enforces this). Default deny.
- Editors' workflow writes go through Postgres functions that check the caller, current state and
  allowed transition. No direct UPDATE grants on `assignments`, `payments`, `submissions` review
  fields, `revision_requests`, `editor_applications.status` or `editor_profiles.access_status`.
- RLS filters rows, not columns: client data and pricing live in separate admin-only tables.
- `security definer` functions: fixed `search_path`, explicit caller checks, no dynamic SQL from input.
- Supabase's automatically exposed API: revoke default privileges from `anon` on new tables; grant
  only what each policy needs.

## Data handling

- Collect only operationally necessary data. Inquiries come from people without accounts, so the
  form must show a privacy notice and record which version they saw.
- No ID documents without a documented reason (KB §7.3).
- Bank details (decision E): built in Phase 12E but locked: nothing can be stored until counsel
  confirms PDPA handling and the owner turns the setting on. Collected after approval, before the
  first payment: account holder name, bank, branch, account number. Owner editor + admins only;
  account number masked by default. Changes are audited, flagged to the admin and held as
  unverified until confirmed out of band (anti payment-redirection fraud); no payment to
  unverified details. Never store banking passwords, PINs or auth codes.
- Retention: unconverted inquiries and rejected applications need a retention period (question P).
- Secrets in environment variables. Public keys are not authorisation; RLS is.
- Asset links: no permanent public links to confidential footage; review access on assign,
  unassign, suspension and close (question K).
- Plan for: privacy notice, data-subject requests, incident response, vendor review (KB §12.3).
  Confirm PDPA obligations with local counsel.

## Operational

Rate limits and Supabase Auth protections on sign-up/sign-in/inquiry. Production auth emails via
custom SMTP on a verified domain. Backups and a **tested** restore before the pilot. Audit log for
sensitive actions.

## Outstanding findings for a future authorised assessment (recorded 2026-11-15)

The owner will run a separate security assessment with tools they provide. No security tools are
installed and no penetration testing has been done. Carry these known items into that assessment;
none has been exploited or confirmed beyond local review.

| #   | Finding                                                                                                                                                       | Where                                                                     | Severity (internal view) | Status                                                                                                                                                                                                                                                                                                                       |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- | ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| S1  | Some Phase 1-3 functions keep the default PUBLIC execute grant (access helpers such as `private.is_admin`, Phase 2-3 public functions, two trigger functions) | listed in `supabase/tests/database/046_phase4_function_security.test.sql` | Low-medium               | Needs an owner-approved migration; helpers are used by RLS policies                                                                                                                                                                                                                                                          |
| S2  | Suspended or revoked users keep their session until their next request                                                                                        | auth/session handling                                                     | Low                      | Accepted for now; access is re-checked on every request                                                                                                                                                                                                                                                                      |
| S3  | Only `frame-ancestors` is set in the CSP; no script CSP (nonces)                                                                                              | `next.config.ts`                                                          | Low-medium               | Follow-up; affects rendering under `cacheComponents`                                                                                                                                                                                                                                                                         |
| S4  | A "permission denied for function" error crashes this Supabase Postgres image (17.6.1.106)                                                                    | database                                                                  | Medium (availability)    | Mitigated by the function placement rule and pgTAP guardrail; re-check on the hosted image                                                                                                                                                                                                                                   |
| S5  | Inquiry form protection is honeypot + rate limit only; Turnstile not yet added                                                                                | `/inquire`                                                                | Medium before launch     | Launch gate (decision O)                                                                                                                                                                                                                                                                                                     |
| S6  | 7 moderate `npm audit` advisories in dev-only lint tooling                                                                                                    | dev dependencies                                                          | Low                      | Do not `npm audit fix --force`                                                                                                                                                                                                                                                                                               |
| S7  | A revoked admin can still read notifications already received (fixed text and project titles only)                                                            | `notifications` RLS                                                       | Low                      | Accepted (Phase 10 review)                                                                                                                                                                                                                                                                                                   |
| S8  | Hosted configuration untested: MFA plan, SMTP, backups, network restrictions, auth rate limits                                                                | hosted Supabase / Vercel                                                  | Unknown                  | No hosted project yet; once payout details are on, backups/PITR hold bank data in plaintext (restrict backup access and retention)                                                                                                                                                                                           |
| S9  | Asset links are client-owned; Lenscape cannot revoke access or see who opened a link (KB7, KB7a)                                                              | process                                                                   | Medium (data exposure)   | Process controls: removal request and confirmation recorded (Phase 12B)                                                                                                                                                                                                                                                      |
| S10 | Payout details (E) hold bank account data once enabled                                                                                                        | `editor_payout_details`, `editor_payout_detail_versions` (12E)            | High sensitivity         | Built locked (flag off, no rows possible); no API grants, masked reads, audited reveals; no field-level encryption yet (options in "Payout details controls"); stays off until counsel confirms PDPA handling; reveal refused while locked; rows are not purged when turned off; backups/PITR would hold plaintext bank data |

Suggested scope for the assessment: RLS and function authorisation (all `public` functions),
auth and MFA flows, server actions and route gates, headers/CSP, the public forms, the e2e helper
that uses the local service key (local only), and the hosted configuration once it exists.
