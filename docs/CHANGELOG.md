# Changelog

Detailed implementation and verification history, newest first. Read only when you need the
specifics of an earlier phase; `CURRENT_STATUS.md` is the session starting point.

## 2026-11-17: Notification emails (feature A)

- **Uncommitted, pending review.** Spec `docs/superpowers/specs/2026-11-17-notification-emails-and-avatars-design.md`
  §A (owner approved 2026-11-17). Feature B (profile pictures) not started.
- Migration `20261117143615_notification_email_worker`: outbox columns `attempts`, `last_error`,
  `claimed_at`, `digest` (set by trigger from `private.email_is_digest(kind)`, existing rows
  backfilled); helpers `private.require_service_role()`, `private.fail_exhausted_emails()`;
  public `worker_claim_emails`, `worker_claim_admin_digest`, `worker_mark_email` (service_role
  only, ES403 otherwise; anon + authenticated + service_role executable per the guardrail).
- App: `src/lib/supabase/service.ts` (server-only secret-key client);
  `src/features/notifications/email/` (layout, individual and admin-summary templates with plain
  text, Brevo sender over `fetch`, worker run, constant-time bearer check);
  `POST /api/cron/send-emails` (25 per run, counts only, `maxDuration` 60). `next.config.ts`:
  `X-Robots-Tag: noindex` on `/api/:path*`. `.env.example`: `CRON_SECRET`, `BREVO_API_KEY`,
  `EMAIL_FROM`. No new dependency.
- Tests: pgTAP `115` (columns, every kind mapped, catalogue rules, no API role on the outbox,
  ES403 as anon/admin aal1/admin aal2/editor A/editor B/applicant, service_role passes, confirmed
  recipients only, no body returned, no double claim, sent/retry/failed after 3, exhausted lease,
  one summary per Colombo day and the next day's summary). Vitest: templates (escaping, fixed
  text, no body, link from `SITE_URL`) and the route (auth, unset secret, not configured, counts,
  provider and network failures, no echo/log of details).
- Review fixes (db-security, code-reviewer): the migration fails the pre-launch queue
  (`pre-launch backlog`); summary day judged by the Colombo date of `claimed_at`;
  `worker_mark_email` takes `p_claimed_at` (stale report ES409; claims return `claimed_at`);
  rows queued over 14 days for unconfirmed or inactive recipients are failed; the service check
  also requires the database role `service_role`; the worker stops new sends after 45 s and keeps
  summaries already sent if the individual claim fails. Delivery is at least once (RUNBOOKS §8).
  pgTAP `115` now 38 tests.
- Implementation calls (flag for owner): attempts are counted when a row is claimed and a claim
  is a 15-minute lease, so a crashed run retries later and a row stuck at 3 attempts is failed;
  rows for unconfirmed recipients wait up to 14 days (sent if they confirm in time); the admin summary uses
  a non-blocking transaction advisory lock so overlapping runs cannot both send one; summaries are
  claimed before individual emails and count toward the 25 cap; hosted scheduling is documented in
  `RUNBOOKS.md` section 8 for the owner to run.

## 2026-11-16: Open opportunities (B/C amended)

- Branch `open-opportunities`, **uncommitted, pending owner review**. Spec
  `docs/superpowers/specs/2026-11-16-open-opportunities-design.md`, approved with every
  recommended §7 call.
- Migrations `20261116152005` (notification kinds `interest_registered`, `opportunity_selected`,
  `opportunity_not_selected`), `20261116152008` (types, `project_opportunities`,
  `opportunity_interests`, guard triggers, RLS helper `private.editor_can_see_opportunity`,
  notifications entity type `project_opportunity`), `20261116152010` (functions and the
  `projects_close_opportunity` trigger). `admin_make_offer` is unchanged and reused.
- Tests: pgTAP `112` (34, schema/RLS as admin, admin without MFA, editors A/B, another editor,
  applicant, suspended), `113` (77, workflow, limits, races and states, selection equals a direct
  offer field by field), `114` (10, function security); `046` allow-list gains the RLS helper.
  Vitest: `src/features/opportunities/schemas.test.ts`, notification href and activity label
  cases. e2e: "open opportunities" (publish, interest, choose, not selected, 375px); cleanup also
  deletes notifications pointing at e2e entities.
- Implementation calls (flag for owner): the pay shown is stored only when shown (hidden pay is
  never saved, so editors cannot read it through RLS); the closing date stops new interest only
  and is the end of that day in Sri Lanka time (the admin can still choose afterwards; there is no
  scheduled job); admin close and a project leaving the open stage for good (confirmed directly,
  cancelled, completed, archived) make every interested editor "not selected"; draft and on hold
  only hide the opportunity; publishing a closed or filled opportunity reopens it, and editors not
  selected before cannot register again (rule 3 applied literally); "previously declined" means a
  `declined` or `not_selected` assignment or a `not_selected` interest on that project
  (`withdrawn`/`reassigned` assignments do not block); an editor with a live offer on the project
  cannot register and cannot be chosen (continue in the Editors card); an editor may withdraw
  while interested and register again (a new row); only `interested` rows on opportunities still taking interest count towards the 10;
  the chosen editor gets `opportunity_selected` plus the existing `invitation` bell when the offer
  creates their access row (two bells); editor bells use the opportunity title, admin bells the
  project title; the "Choose this editor" offer form is prefilled with the shown pay or the
  project's editor pay, never the proposed rate; the selected interest stays "Selected" even if
  the editor later declines the offer; there is no editor profile page to link to, so the admin
  list shows the editor's name and access status only.
- Review fixes (2026-11-16, db-security PASS and code-reviewer APPROVE, notes only): column-level
  `select` on `project_opportunities` (no `project_id`, `published_by`, `closed_by` via the API;
  admins use the new `admin_get_opportunity`, one round trip); stale interests no longer count
  towards the limit; project-triggered closes record `closed_by_project_change` and the changed
  project field names; lock-order comment corrected; the admin card loads in its own Suspense
  boundary; impossible dates refused; the typed rate currency survives an error.
- Not verified: true concurrency (two sessions) for the races; the locks and ES409 paths are
  exercised sequentially in pgTAP `113`.

## 2026-11-16: Phase 12E payout details (locked), interim attestation, mark-paid gate

- Branch `phase12e-payout`, **uncommitted, pending owner review**. Spec 4.8 and call 1; decision E
  (2026-11-11 and the 2026-11-15 go-ahead); SECURITY_AND_PRIVACY S10.
- Migrations `20261116103247` (notification kind `payout_details_changed`), `20261116103251`
  (schema: `app_settings.payout_details_enabled` default false, `editor_payout_details`,
  `editor_payout_detail_versions`, `editor_payout_attestations`, guard triggers, notifications
  entity type `editor_profile`), `20261116103254` (functions; `admin_mark_payment_paid` replaced in
  place with every Phase 9 check and the payments audit kept, gate added last).
- **Locked:** while the flag is off every payout write function refuses (ES409) and the guard
  trigger refuses inserts into the details and versions tables even for the table owner. pgTAP
  turns the flag on only inside its own transaction with obviously fake values.
- Implementation calls (flag for owner): verification methods are phone, in person or other, with a
  required note; verification names the version the admin saw (a newer save refuses with ES409);
  saving identical details is a no-op (no version, no notification); the account number allows
  6-34 letters, digits, spaces or hyphens with at least 6 letters or digits and one digit (a
  shorter stored value would mask as `****`); the editor sees holder, bank and
  branch in full and the number masked to the last 4 (admins the same until they reveal); the
  reveal reason is stored in the audit row and may not contain a run of 6+ digits; reveal is
  refused while locked (masked reads stay); turning the flag off again re-locks writes and makes
  attestations count again (stored details are not purged); an attestation is per editor, not per payment,
  and is never revoked (append-only); every function acting on the flag holds the settings row `for share`
  (lock order payment, settings, payout row); no field-level encryption (documented in S10).
- Review fixes (2026-11-16, both reviews, no blockers): flag row held `for share`; reveal refused
  while locked; digit runs refused in reveal reasons (UI warning); 6+ alphanumeric account
  numbers; details guard enforces next version + unverified on any content change and no version
  change otherwise (owner too); the revealed number travels in its own field, shown until Hide or
  30 s, never in the message; the account number input clears after a save; "Payout account"
  link per editor on `/admin/earnings`; e2e cleanup keeps `app_settings` rows (it used to delete
  rows last changed by an e2e admin); e2e turns the flag on and straight back off (teardown
  upserts false).
- **Follow-up test (not built):** the flag races (enable vs. save/attest/mark-paid) need a
  two-session test; pgTAP runs in one session, so the `for share` locking is reviewed, not tested.
- Tests: pgTAP `109`-`111`; older tests seed an attestation before marking paid (073, 074, 076,
  103, 107) and 099 counts two settings rows. Unit tests for payout schemas, notification links
  and activity labels.
- App: `/editor/earnings` payout card ("Not available yet" while locked; form with masked number
  and verification status in words when on); admin payout card on `/admin/earnings/[id]` and on
  `/admin/earnings?editor=<id>` (where the notification leads) with Attest (locked), Verify and
  Reveal (reason required); the mark-paid action explains why it is blocked; `/admin/settings`
  toggle with the PDPA warning and a confirmation box.

## 2026-11-15: Phase 12D part 2 extra pay, scope quotes, cancellation settlement

- Branch `phase12d2-adjustments`, **uncommitted, pending owner review**. Spec 4.3 (`cancelled`),
  4.4, 4.6, 6; calls 2, 5, 6, 8; decisions F, F2 (a-d), KB9a-3, Phase 12 principles.
- Migrations `20261115093806`-`20261115093821` (see DATABASE_SCHEMA "Extra pay, scope quotes and
  cancellation settlement"). Replaced in place: `private.check_payment_row`,
  `private.guard_payments`, `private.audit_payments`, `private.require_unpaid`,
  `private.guard_revision_requests` (the gate), `admin_reverse_payment`, `admin_set_project_status`
  (settle-instead rule). `editor_list_payments` dropped and recreated (`line_kind`). No Phase 8
  function body changed: the gate lives in the revision guard trigger.
- Implementation calls (flag for owner): an accepted offer is payable at once (due editor pay
  days later), not tied to client payment of the extra charge; the settlement counts accepted
  extra pay as earned in full and leaves its rows alone (paid stays paid, unpaid stays payable;
  only milestones are cancelled or reconciled; the admin's figure is between the extra pay and
  agreed + extra pay); client charge base = deposit + balance milestones (extra-work
  charges excluded); a recorded but unverified client payment blocks settling; settlement is
  required only with a confirmed editor and a schedule row for the stage, otherwise the Phase 9
  hold stays (also for reassignment, and a later cancel does not settle the reassigned editor's
  held rows); a scope change always needs both the accepted quote and then an accepted offer
  (offer only after the quote is accepted); a begun request cannot be reclassified as a scope
  change (review fix); accepting a quote records it as invoiced with the admin's due
  date; "withdraw the change request" is not built (no revision status for it; options are a new
  offer, clearing the requirement, or reassignment); extra cancellation pay can be offered only
  after a settlement; offer notifications link to `/editor/earnings`, where open offers are also
  answered.
- Tests: pgTAP `105`-`108`; older tests updated: 070 (status matrix 49 pairs, new columns), 075
  (editor list type), 080 (revision columns), 081 (unlocks the scope change before resubmitting),
  102 (`milestone_seq` nullable). Unit tests for adjustment schemas, payment line labels,
  editor list labels, notification links and activity labels.
- Review fixes: scope offers only after quote acceptance; no begun-request reclassification to
  scope change; settlement earned includes accepted extra pay; editor offers shown whenever the
  project is visible; quote currency kept after an error; gate errors show a neutral notice;
  settlement label formats money; reason marked aria-required once an amount is typed; signed-in
  e2e for a changed amount without a reason.
- App: admin project page "Extra pay and client charges" (mark round, offer, withdraw, charge
  extra round, scope quote draft/send/answer) and "Cancellation settlement" (proposed figures,
  change with reason, confirm; record and extra cancellation pay afterwards); editor project page
  and `/editor/earnings` show offers with Accept/Decline and the blocked state; earnings show
  extra pay, Cancelled and settlement lines with fixed labels; admin earnings label extra lines.

## 2026-11-15: Phase 12D part 1 editor pay milestones, late-balance protection, dispute splits

- Branch `phase12d-editor-pay`, **uncommitted, pending owner review**. Spec 4.2 note, 4.3, 4.5, 5
  (late-balance protection), call 9; decisions KB9, KB9a-1, KB9a-4, KB9a-5, KB9b-3.
- Migrations `20261115071328`-`20261115071334` (see DATABASE_SCHEMA "Editor pay milestones").
  Replaced in place: `private.check_payment_row`, `private.guard_payments`,
  `private.create_assignment_payment`, `private.review_submission` (no direct payments update),
  `private.client_deposit_verified`, `private.apply_timed_rules`, `admin_release_payment_hold`,
  `admin_reverse_payment`. `editor_list_payments` dropped and recreated (only the app calls it).
- Implementation calls (flag for owner): milestones 2..n are all "after approval" rows and
  late-balance protection makes all of them payable; protection starts only once every unverified
  balance row has an invoice, and skips an assignment while any of its rows is on hold (review
  fix, owner to confirm); "client
  balance verified" also requires the (net) deposit; a later client correction or refund does not
  un-pay a milestone already payable (no `pending_approval -> not_due` move exists; the admin can
  hold it); one dispute split per milestone row.
- Review fixes: `admin_set_payment_status` refuses `not_due -> pending_approval` by hand (the
  "Send for approval" button is gone for not-due rows); editors no longer receive
  `reversal_reason` (a reversal shows "Reversed"); `late_balance_due` also requires an issued
  invoice; `admin_reverse_payment` locks project, assignment, payment; the editor may infer the
  balance-verification day from a due date (accepted, documented); split form caps the amount in
  the browser; e2e sign-in waits longer and pages are warmed in global setup.
  milestone rows (net of reversals) may never exceed the agreed amount (replaces "equals").
- Tests: pgTAP `102`-`104`; older payment tests (070, 072-076, 081) updated for milestones (100%
  editor share where one row per assignment is assumed; 081 now checks only milestone 2 moves on
  approval). Unit tests for labels, split schema, notification link, activity labels.
- App: `/editor/earnings` shows each milestone with fixed labels; `/admin/earnings` adds milestone
  and payable reason; `/admin/earnings/[id]` adds milestone, payable reason/time, split links and
  the "Partial dispute" form. The hold-reason hint now says editors never see it.

## 2026-11-15: Phase 12C client billing, deposit gate, timed rules

- Branch `phase12c-billing`, **uncommitted, pending owner review**. Spec 4.2, 5 (start gate,
  auto-hold, scheduler), calls 3, 4, 7, 9; decisions KB9, KB9a-2, KB9b; notification
  `project_auto_held` (section 6).
- Migrations `20261115050654`-`20261115050706` (see DATABASE_SCHEMA "Client billing"). The gate
  dependents were listed from the catalog first (pg_depend empty; bodies referencing it:
  gate_refusal, guard_assignment_start, get_assignment_gate, editor_submit_interpretation,
  start_work, editor_confirm_brief, editor_submit_work); only `get_assignment_gate` was dropped and
  recreated with it.
- Implementation calls (flag for owner): hold from the calendar day after the due date; extension
  releases the hold; on_hold -> cancelled allowed only for the deposit hold; a manual release ends the hold
  but does not re-arm the rule for the same due date (`auto_held_for_due`); only `assigned`
  projects are auto-held; verifying the deposit does not auto-release a hold; an
  audited `admin_correct_client_payment` reverses a mistaken verification (not for a deposit once
  work began); milestones can be replaced (old rows voided) until an invoice or payment exists;
  `timed_rules.run` is audited only when the run acted; refund rows are enforced by the schema but
  created only in 12D (cancellation settlement).
- Tests: pgTAP `099`-`101`; older tests that start work (061, 063-066, 072, 080-082, 094) now
  verify a deposit first. Unit tests for billing schemas/helpers, gate state, labels, notification
  link. Signed-in e2e "client billing (Phase 12C)".
- App: `src/features/billing` (Client billing panel on `/admin/projects/[id]`, timed rules on
  `/admin` and `/admin/earnings` load, business timezone on `/admin/settings`); editor panel
  shows "Waiting for the client deposit"; auto-held projects offer Resume or Cancel.

## 2026-11-15: Phase 12B asset access

- Branch `phase12b-assets`, **uncommitted, pending owner review**. Spec section 4.7 and the
  asset-inaccessible notification (section 6); decisions KB7, KB7a.
- Migrations: `20261115042630_phase12b_notification_kind.sql` (`asset_inaccessible`, alone in its
  migration), `20261115042633_phase12b_assets_schema.sql` (enums `asset_access_status`,
  `asset_access_type`; new columns on `project_assets` and `asset_access_grants`; append-only
  `asset_access_reports` with `private.guard_asset_access_reports`) and
  `20261115042637_phase12b_assets_functions.sql` (`editor_report_asset_inaccessible`,
  `editor_confirm_asset_access`, `admin_verify_asset`, `admin_resolve_asset_report`,
  `admin_request_access_removal`, `admin_confirm_access_removal`; replaced `private.parse_assets`,
  `private.sync_asset_rows`, `admin_record_asset_grant` (+ `p_access_type`) and
  `admin_pending_revocations` (+ access type, removal requested)).
- Implementation calls (flag for owner): the editor's "I can open this" is stored on the asset
  (`editor_confirmed_at` only, no editor id since editors read the row; stale when older than the current assignment's `confirmed_at`) as a hint, never a verification; verifying is refused while a report
  is open; resolving the last open report puts an inaccessible asset back to `awaiting_access`; a
  changed link or provider resets verification; a report note is required (max 1000); one open
  report per editor and asset; confirming removal also closes the share (`revoked_at`); the old
  "Mark as removed" button is gone from the UI (the Phase 5 `admin_revoke_asset_grant` function
  still exists); reports keep their history when an asset is removed (`asset_id` set null).
- Tests: pgTAP `096_phase12b_assets_schema`, `097_phase12b_assets_functions`,
  `098_phase12b_function_security`; `058` now pins the six-argument `admin_record_asset_grant`.
  Unit tests for the new schemas, activity labels and the notification link.
- App: `src/features/access` (`verifyAssetAction`, `resolveReportAction`, `requestRemovalAction`,
  `confirmRemovalAction`, `reportAssetAction`, `confirmAssetAccessAction`; `RemovalForms`,
  `VerifyAssetForm`, `ResolveReportForm`, `ReportAssetForm`, `ConfirmAssetAccessForm`; Asset access
  card); `revokeGrantAction` / `RevokeGrantForm` / `revokeGrantSchema` removed. Activity labels for
  the six new audit actions.

## 2026-11-15: Phase 12A project terms

- Branch `phase12a-terms`, **uncommitted, pending owner review**. Spec
  `docs/superpowers/specs/2026-11-15-phase12-commercial-terms-design.md` section 4.1, the confirm
  gate (section 5), calls 6, 9 and 10.
- Migrations: `20261115032846_phase12a_terms_schema.sql` (enums `project_terms_status`,
  `terms_stage`; tables `project_terms`, `project_terms_stages`; guards
  `private.guard_project_terms`, `guard_project_terms_stages`, `guard_revision_allowance`;
  `private.create_initial_terms` trigger; backfill) and `20261115032849_phase12a_terms_functions.sql`
  (`admin_save_terms_draft`, `admin_agree_terms`, `editor_get_terms`; replaced
  `admin_confirm_assignment` and `admin_update_project`).
- Implementation calls (flag for owner): backfilled projects with a confirmed editor got agreed v1
  (others draft); once an editor is confirmed, editor milestone shares and editor kill-fee shares
  cannot change (until 12D adjustments); day counts are fixed once work has begun ("work begun" =
  an assignment is or was `in_progress`, or a submission exists); the change reason may be stored
  on the draft or given when agreeing; agreeing terms does not require a cancellation schedule.
- Tests: pgTAP `093_phase12a_terms_schema`, `094_phase12a_terms_functions`,
  `095_phase12a_function_security`; existing tests 044 (no `revision_allowance` on update) and the
  confirm helpers in 054-082 now agree terms before confirming. Unit tests for the terms schemas and
  activity labels; signed-in e2e "project terms (Phase 12A)".
- App: `src/features/projects` (`saveTermsDraftAction`, `agreeTermsAction`, `termsDraftSchema`,
  `agreeTermsSchema`, `getProjectTerms`, `getEditorTerms`, `TermsCard`, `TermsDraftForm`,
  `EditorTermsSummary`); activity labels `project_terms.draft_saved`, `project_terms.agreed`.

## 2026-11-15: Phase 11 hardening

- Branch `phase11-hardening` from `main` (`94f68b3`), **uncommitted, pending owner review**. No
  migrations.
- E2E: `tests/e2e/signed-in.spec.ts` (inquiry submit; applicant sign-up via Mailpit link, gated
  `/apply`, redirected from `/editor` and `/admin`; editors A/B each see only their own offered
  project, 404 UI on the other's; admin password-only lands on `/mfa`, TOTP opens `/admin` and
  `/admin/activity`). Helpers `tests/e2e/support/local-stack.ts` refuse non-local URLs, read keys
  from `supabase status -o env` at runtime, run SQL via `docker exec`; `totp.ts` (RFC 6238, unit
  test `tests/unit/totp.test.ts`, no new dependency). Global setup/teardown (`cleanup.ts`) deletes
  e2e data by walking foreign keys as the local superuser in replica mode, because pgTAP counts
  rows in a clean database. CI e2e job renamed; no new secrets.
- Security review: added baseline headers in `next.config.ts` (frame denial, nosniff,
  referrer and permissions policy) with a smoke test. No missing server-side gates or raw error
  leaks found (details in `CURRENT_STATUS.md`).
- Restore drill: `npm run db:restore-test` (`scripts/db-restore-test.mjs`): dump, restore into
  scratch `restore_check`, compare row counts, migrations, functions, RLS. Passed (63 tables).
- Docs: `docs/RUNBOOKS.md` (backup/restore, admin MFA reset, revoking editors/admins,
  cancellation/withdrawal/reassignment, incident response, deploy checklist; owner items TODO);
  KB §16 evidence table in `CURRENT_STATUS.md`; roadmap rows 4-10 marked committed.
- Verification: `npm run check` (Vitest 250/250), pgTAP 1545/1545, Playwright 24/24.

## 2026-11-14: Phase 10 notifications, metrics and audit view

- Branch `phase10-notifications`, **uncommitted, pending owner review**. KB10 adopted (owner:
  "accept recommended"). Spec `docs/superpowers/specs/2026-11-14-phase10-notifications-design.md`.
  Migrations `20261114192322_phase10_notifications`, `20261114192400_phase10_metrics`.
- DB: `notifications` (recipient-only RLS), `private.notification_outbox` (queued, unsent),
  trigger `activity_logs_notify` mapping 11 audited events to notifications (admin fan-out to all
  non-revoked admins), `mark_notification_read`, `mark_all_notifications_read`,
  `admin_dashboard_metrics` (inquiries/applications/projects by status, conversion, acceptance and
  counteroffer rates, median time to assignment and to first submission, on-time and
  first-submission approval rates, average client rounds, editor corrections, payments by currency).
  Not computable from stored data: gross contribution, admin time, editor abandonment.
- UI: notification bell with unread count in the admin/editor shell and on `/apply`;
  `/notifications` (list, mark read, mark all, entity links); `/admin` metric cards and CSS bar
  charts (no new dependencies); `/admin/activity` (filter by record type and action, plain labels).
- Verification: pgTAP 1543/1543 (`090`-`092` new), Vitest 245/245, `npm run check` green,
  db:advisors clean, Playwright smoke 19/19 (signed-out gates for `/admin/activity`,
  `/notifications`). Signed-in screens not yet checked in a browser.

## 2026-11-14: Phase 8 submissions, review and revision classification

- Branch `phase8-submissions`, **uncommitted, pending owner review**. Spec
  `docs/superpowers/specs/2026-11-14-phase8-submissions-design.md` (calls §7). Migrations
  `20261114154439_phase8_schema`, `..154444_phase8_functions`, `..154448_phase8_earlier_phase_changes`.
- `submissions`, `revision_requests` (enums `submission_outcome`, `revision_type`,
  `revision_status`), guards, project review-status guard, audit trigger. Functions
  `editor_submit_work`, `editor_acknowledge_revision`, `admin_review_submission`,
  `admin_approve_project`, `admin_classify_revision`, `admin_complete_project`. Replaced
  `project_transition_allowed`, `admin_reassign`, `private.require_working_assignment` (review
  statuses). Approval moves `not_due` payments to `pending_approval`.
- Screens: editor project page Submissions card (submit, change requests with acknowledge/start,
  history); admin project page Review card (pending version, approve, outcome/feedback/classify,
  rounds x/allowance with beyond warning, late count, classify open requests, complete, history).
- Verification: pgTAP 1482/1482 (080-082 new, 044 updated), advisors clean, `npm run check` green
  (Vitest 223), Playwright 17/17. Not checked in a signed-in browser.

## 2026-11-14: Phase 9 payments and earnings tracker

- Branch `phase4-followups`, **uncommitted, pending owner review**. Migrations
  `20261114145816_phase9_payments_schema`, `..145820_phase9_payment_triggers`,
  `..145824_phase9_payment_functions`.
- `payments` (enums `payment_status`, `payment_kind`; insert/update/delete guards that hold for the
  table owner; paid rows immutable except actor clears) and admin-only append-only
  `payment_notes`; select-only grants, one policy each. Triggers on `assignments`: payment created at
  `accepted → confirmed`; unpaid payments held on `confirmed|in_progress → reassigned|withdrawn`.
  Functions `admin_set_payment_status`, `admin_release_payment_hold`, `admin_mark_payment_paid`,
  `admin_set_payment_due_date`, `admin_reverse_payment`, `admin_add_payment_note`,
  `editor_list_payments`. Audit details: ids and enum names only.
- Screens: `/editor/earnings`, `/admin/earnings` (summary per currency, filters, by editor,
  project margin), `/admin/earnings/[id]` (actions, notes, history); nav "Earnings". Summaries are
  pure TypeScript (`src/features/payments/summary.ts`, Asia/Colombo month).
- pgTAP 070-076 added (role refusals for all seven functions consolidated in 076). 1357/1357.
  Advisors: no issues. Types regenerated. Vitest 212/212. Playwright 17/17 (gates for the three
  earnings routes). Signed-in browser check not done yet.

## 2026-11-14: Phase 7 database layer (interpretation, brief confirmation, in-progress gate)

- Branch `phase4-followups`, **uncommitted, pending owner review**. Migrations
  `20261114115858_phase7_in_progress_enum`, `..115902_phase7_schema`, `..120257_phase7_gate`,
  `..120611_phase7_interpretations`, `..120727_phase7_confirm_and_start`,
  `..121138_phase7_phase6_changes`.
- `assignment_status.in_progress`; `assignments.started_at/started_by`; one active
  (`confirmed`/`in_progress`) assignment per project. Tables `editor_interpretations`
  (append-only, one review) and `brief_confirmations` (immutable, carried-forward rows recorded).
- `private.assignment_gate` + `BEFORE UPDATE` triggers on `assignments` and `projects`; carry-forward
  trigger on `brief_versions`; editor stage `assigned` for `in_progress`. Functions:
  `editor_submit_interpretation`, `admin_review_interpretation`, `editor_confirm_brief`,
  `editor_start_work`, `admin_start_work`, `get_assignment_gate`; Phase 6 replacements for
  reassign/withdraw/revoke/offer/checklist/cancel.
- Confirmation rows set `confirmed_at = clock_timestamp()` so several confirmations in one
  transaction stay ordered (the column default stays `now()`).
- pgTAP 060-066 added; 044 and 052 matrices updated (052's amount-hygiene check scoped to its seeded
  row: random matrix uuids could contain the digits). 1133/1133. Advisors: no issues. Types
  regenerated (additions only).

## 2026-11-14: Phases 5-6 database layer (assets, editor access, offers, assignments)

- Branch `phase4-followups`, **uncommitted, pending owner review**. Migrations
  `20261114061439_phase5_assets_schema`, `..061746_phase5_assets_functions`,
  `..062112_phase6_access_schema`, `..062429_phase6_editor_visibility`,
  `..062924_phase6_admin_negotiation`, `..063511_phase6_editor_respond`,
  `..063650_phase6_project_status_changes`.
- Tables `project_assets`, `asset_access_grants`, `project_access`, `assignments`,
  `negotiation_offers`, `project_notes`; `project_references.early_access`. Editor reads tiered by
  `private.editor_project_stage`; one combined select policy per table (avoids the
  multiple-permissive-policies advisor). Append-only history and notes refuse update and delete.
- `admin_set_project_status`: `open → draft` refused once editors had access; cancel allowed from
  `assigned`, closing live assignments and revoking access.
- pgTAP 050-058 added, 044 (expected transitions) and 046 (RLS-helper allow-list) updated: 842/842.
  Advisors: no issues. Types regenerated.
- Spec and plan: `docs/superpowers/specs/2026-11-14-phase5-6-editor-access-design.md`,
  `docs/superpowers/plans/2026-11-14-phase5-6-database.md`.

## 2026-11-14: Phase 4, projects, briefs, clients, inquiry conversion

- Branch `phase4-projects`, **uncommitted**. Migrations `20261114050211_phase4_schema`,
  `..050359_phase4_inquiry_link`, `..050658_phase4_brief_helpers_and_create`,
  `..051059_phase4_brief_versioning`, `..051417_phase4_project_status`,
  `..051655_phase4_clients_and_conversion`.
- Tables: `clients`, `projects`, `project_internal`, `brief_versions`, `project_deliverables`,
  `project_references` (pulled forward from Phase 5), `client_inquiries.converted_project_id`.
  Admin-read-only RLS; writes via `admin_create_project`, `admin_save_brief`, `admin_update_project`,
  `admin_set_project_status`, `admin_archive_project`, `admin_create_client`, `admin_update_client`,
  `admin_merge_clients`, `admin_convert_inquiry`. Brief versions immutable after first opening.
- UI: `/admin/projects` (list, new, detail), `/admin/clients`, "Convert to project" on the inquiry
  page. Statuses draft/open/on_hold/cancelled; others pending.
- pgTAP tests 040-046; 465/465 passing in total. Not yet checked in a signed-in browser.
- Follow-up found: pre-Phase-4 functions executable by PUBLIC (exceptions listed in test 046).
- Spec and plan: `docs/superpowers/specs/2026-11-13-phase4-projects-briefs-design.md`,
  `docs/superpowers/plans/2026-11-14-phase4-database.md`.

## 2026-11-13: decisions J and T

- Owner chose the recommendations. **T:** minimal admin-only `clients` table, created when the
  first inquiry is converted (`client_contacts` not decided). **J:** coarse project status;
  Invited, Negotiation and Awaiting confirmation are assignment states shown as derived labels on
  the project (WORKFLOWS §5, no longer PROPOSED). Recorded in OPEN_QUESTIONS (log, index, section
  headings); DATABASE_SCHEMA, WORKFLOWS, DEVELOPMENT_ROADMAP (also: Phases 1-3 marked with their
  commits) and CURRENT_STATUS updated. Phase 4 has no remaining blocking questions.

## 2026-11-12: development environment

- **Claude Code guardrails (Essential tier):** project `.claude/settings.json` with permission
  rules and two deterministic hooks (`.claude/hooks/guard.mjs`: protects env files and committed
  migrations, asks before push/commit and hosted Supabase/Vercel operations;
  `.claude/hooks/format.mjs`: Prettier on edited files). Duplicate plugins and skills disabled for
  this project. `CURRENT_STATUS.md` split into status + this changelog; decision index added to
  `OPEN_QUESTIONS.md`; workflow and method routing added to `CLAUDE.md`.
- **Design system, part 4 (states):** `EmptyState`, skeleton `Loading`, root `error.tsx` (shows
  only the digest reference; verified that a thrown error message never reaches the page) and
  `not-found.tsx`; admin applications, inquiries and activity use `EmptyState`. New smoke test for
  the 404 page (9 total). Gotcha found: `export const dynamic` in any route is a build error under
  `cacheComponents` and breaks the whole dev server, not only that route.
- **Design system, part 3 (status pills):** `StatusPill` (text label in the normal text colour,
  tone shown by a dot: success, warning = needs admin attention, info = in progress/waiting,
  danger, neutral) replaces the shadcn badge variants for application and inquiry statuses so
  every status looks the same. Checked visually in dark and light on a temporary page (deleted).
- **TokenEconomizer (Microsoft) installed, trial, 2026-11-13:** cloned to
  `C:\Users\ahash\tools\TokenEconomizer` at commit `7042ea8` (reviewed: no network code, hooks
  fail open, paid side-calls are `claude -p --tools "" --max-turns 1`), installed with
  `--scope local` (this project, git-ignored `.claude/settings.local.json`). **Claude Code 2.1.212
  is below its supported range 2.1.300-2.1.310, so behaviour is unverified.** Per-repository config
  (outside the repo, `~/.tokeneconomizer/repos/editstation-*/config.json`): `microskills=envfacts`
  (no model calls), `toolprune=propose` (its default is `auto`, changed before first use; nothing
  is applied until `toolprune apply`), `loopguard=nudge` (redirects, never stops a turn),
  `history_import=on` for this repository only. Take effect from the next session. Disable one
  session: `TE_DISABLE=1`; remove: `claude plugin uninstall tokeneconomizer@tokeneconomizer
--scope local`. Baseline before trial (RTK, all projects): 524 commands, 39% of command output
  saved. To judge it, compare `/context`, `/cost` and `/tokeneconomizer:status` over several real
  tasks, plus repeated failures and test results, not token counts alone.
- **Design system, part 2 (app shell):** `src/components/app-shell/` (`AppShell`, `NavLinks`,
  `MobileNav`) wired into `/admin` and `/editor` layouts: sidebar on large screens, top bar with a
  menu sheet (new shadcn `sheet` component) below `lg`; current page marked with a purple bar and
  `aria-current`. Replaced `admin-nav.tsx`. `AreaShell` hides its "EDITSTATION" eyebrow inside the
  shell. Checked visually (dark, light, 375px, menu open) on a temporary route that was deleted;
  active-link logic unit-tested (`is-current.test.ts`); not exercised behind real admin MFA / editor sign-in. Applicants (`/apply`) are unchanged.
- **Design system, part 1:** `docs/DESIGN_SYSTEM.md` (owner-approved recommended answers).
  `globals.css` now has brand tokens: dark default (near-black, brand purple `#9643E5`), light
  theme via `prefers-color-scheme`, `--brand-text`, success/warning tokens; `dark:` utilities
  follow the same rule. `Wordmark` component in the public header and auth pages.
  `src/lib/design-tokens.test.ts` checks WCAG contrast for the token pairs (34 tests).
  **Bug fixed:** `--font-sans` referenced itself, so Geist was never applied and the app rendered
  in Times New Roman. Pending: shared admin/editor shell, status badges, empty/loading/error
  states, transparent logo from the owner.
- **Playwright smoke tests (Recommended tier, part 2):** `@playwright/test` 1.65.0 (dev
  dependency, Chromium only), `playwright.config.ts`, `tests/e2e/smoke.spec.ts` (8 tests: home
  entry points, inquiry form loads service types and lists missing fields, 375px no horizontal
  scroll, signed-out redirects for `/apply`, `/editor`, `/admin`, `/admin/applications`, `/mfa`
  keeping `next`). They create no data. Run `npm run test:e2e`. Not in CI yet. Not covered:
  signed-in flows (sign-up confirmation via Mailpit and admin TOTP are the hard parts).
- **Specialist agents and path rules (Recommended tier, part 1):** `.claude/agents/` with
  `db-security` (Opus), `code-reviewer` and `qa-browser` (Sonnet), all read-only with concise
  output formats; `.claude/rules/db.md` (`supabase/**`) and `ui.md` (app, components, feature UI).
  Not yet exercised: agents load from the next session. Still pending from the Recommended tier:
  Playwright e2e tests, design system. TokenEconomizer is blocked (needs Claude Code
  2.1.300-2.1.310; installed 2.1.212).
- **Moved from macOS to Windows.** Removed macOS metadata files (`._*`, `.DS_Store`), reinstalled
  `node_modules` for Windows, added `.gitattributes` (LF everywhere), and made the Supabase CLI a
  pinned dev dependency (`supabase@2.122.1`; CI pinned to the same version). Re-verified on
  Windows: `npm run check` (58), `npm run db:test` (151), `npm run db:advisors` (no issues),
  `/inquire` renders with data from local Supabase.

## Phase 3: public website and client inquiries (2026-11-11)

**Database** (`20261111140306_phase3_public_inquiries.sql`):

- `service_types` (admin-managed; seeded with placeholder categories from KB §7.1 + "Not sure"),
  `budget_ranges` (admin-managed; **none seeded**: no invented pricing), `client_inquiries`
  (status per decision N; service and budget labels copied at submission; privacy-notice version),
  `client_inquiry_links` (https only, max 10), `inquiry_notes` (admin-only),
  `private.inquiry_throttle` (SHA-256 of client IP, kept one hour).
- `public.submit_client_inquiry` (anon-callable, returns nothing; validation; limits: 3/hour per
  email, 5/hour per source, 100/hour overall). `public.admin_set_inquiry_status` (MFA admin;
  `converted` cannot be set by hand: reserved for Phase 4 conversion).
- Anonymous visitors can read only **active** service types and budget ranges; they cannot read
  any inquiry data. Audit entries for inquiries contain no personal data.

**App:** public home page with two separate entry points (inquiry vs editor sign-up), shared site
header/footer, `/inquire` form (honeypot, privacy acknowledgement, input kept on errors),
`/admin/inquiries` list + detail (status changes with notes, internal notes, history),
`/admin/settings` (service types and budget ranges), "new inquiries" count on the admin overview.

**Tests:** pgTAP 151 (Phase 3 adds 40), Vitest 58.

**Fixed during Phase 3:** a stale session cookie (token for a deleted account) made public inquiry
submissions fail on the audit foreign key; the inquiry audit now records an actor only if that
profile exists.

**Verified (2026-11-11):** all DB tests (151), advisors (no issues), unit tests (58), lint,
typecheck, build. Browser: home page and `/inquire` (desktop and 375px mobile, no horizontal
overflow); empty submit lists required fields; privacy acknowledgement required with input kept;
successful submission stored with link, "Prefer to discuss" budget and deadline; honeypot
submission shows the thank-you but stores nothing; admin overview count; inquiry list and detail;
status change to Contacted with note and audit history; adding a budget range in Settings shows it
on the public form.

## Phase 2: editor applications and vetting (2026-11-11)

**Database** (`20261111133128_phase2_editor_applications.sql`):

- Editor profile fields (KB §7.3) and admin-set `level`; `profile_options` (specialisations and
  software, seeded from KB §7.1/§7.3, admin-managed); `editor_profile_options`;
  `editor_portfolio_links` (https only, max 10); `editor_applications` (statuses per decision L,
  one active per editor, frozen `submitted_snapshot`, terms/privacy versions);
  `application_requests` (info requests and practical tests, with assessment result);
  `editor_vetting_notes` (admin-only).
- Functions (each authorises itself; ES4xx errors): `save_editor_profile`,
  `submit_editor_application`, `withdraw_editor_application`, `respond_to_application_request`,
  `admin_start_application_review`, `admin_create_application_request`,
  `admin_record_assessment_result`, `admin_approve_application` (the only path to `active`),
  `admin_reject_application`, `admin_reopen_application` (decision M),
  `admin_set_editor_access` (suspend/reactivate/revoke; revoke is final).
- Audit: application status changes, requests, answers, assessments.
- **Fix to Phase 1:** account deletion was impossible (append-only trigger blocked
  `actor_id → null`). Deletion now anonymises the actor; all other log changes stay blocked.

**App:**

- `/apply`: application form (save draft or submit; validation errors never wipe input), status,
  information/test requests with responses, withdraw (two-step), frozen "what you submitted" view,
  rejected/withdrawn messages, reopened-application notice.
- `/admin/applications`: filterable list (needs attention / decided / reopened drafts / all).
- `/admin/applications/[id]`: frozen submission, start review, info/test requests, record test
  result, approve with level (confirm step), reject with optional applicant message, reopen,
  suspend/reactivate/revoke with reason, vetting notes, attempt history, audit trail.
- Admin nav; placeholder `/legal/editor-terms` and `/legal/privacy` (no legal text; version
  `placeholder-2026-11-11` recorded on each submission).
- Stale sessions (token for a deleted account) are treated as signed out.

**Tests:** pgTAP 111 (Phase 2 adds 67: full workflow, every escalation path, state machine, decision
M, snapshot immutability, link limits, account deletion). Vitest 45.

**Verified (2026-11-11):** `npm run check`, `npm run build`, `npm run db:test` (111),
`npm run db:advisors` (no issues). Browser, end to end on local Supabase: incomplete submission
lists missing fields; terms required; insecure link rejected without losing input; submit shows
status and snapshot; applicant blocked from `/editor`; admin (MFA) list → detail → start review →
vetting note → info request (approval blocked meanwhile); applicant sees request but not notes;
response returns to review; approve refused without level, then approved as Professional; suspend
and reactivate with reasons, audited; approved applicant lands on `/editor`; stale session
redirects to sign-in. Not exercised in the browser (covered by pgTAP only): reject, reopen,
withdraw, practical-test result recording.

## Phase 1: auth and access gating

- DB (`20261111122133_phase1_auth_access.sql`): `profiles` (no role), `admin_users`,
  `editor_profiles.access_status`, append-only `activity_logs`; sign-up trigger (no access, ignores
  metadata); `private.is_admin()` (requires MFA `aal2`), `is_admin_account()`, `is_active_editor()`;
  admin bootstrap `private.grant_admin_by_email()`; audit triggers; explicit grants.
- Auth config: email confirmation (R), TOTP MFA (A), password ≥ 10 chars letters+digits,
  `token_hash` email templates.
- App: SSR Supabase clients, `proxy.ts`, Data Access Layer (`src/lib/auth/access.ts`), sign-up/in/out,
  password reset, admin MFA enrol/verify, gated `/apply`, `/editor`, `/admin`.

## Phase 0: repository foundation

Next.js 16.4 (App Router, `src/`, TS strict), Tailwind v4, shadcn/ui (base-ui), ESLint + Prettier,
Vitest, local Supabase config, pgTAP, CI workflow, split docs, `CLAUDE.md`.

### Open opportunities: owner approval and verification (2026-11-16)

Owner approved all calls: closing date ends new interest at the end of that day in Asia/Colombo (admin can still select, no job); admin close or project cancelled, completed, archived or confirmed directly marks interested editors Not selected; draft and on-hold only hide; republishing reopens and previously Not selected editors cannot register; previously declined = declined or not_selected assignment or a not_selected interest (withdrawn and reassigned do not count); an editor with a live offer cannot register or be selected; withdraw and re-register allowed; the chosen editor gets `opportunity_selected` plus the usual invitation; Choose this editor prefills shown pay or the project's editor pay, never the proposed rate; Selected stays Selected if the offer is later declined; the admin list shows name and access status only.

Verification: db:test 2,297 pass, advisors clean, `npm run check` pass; final full `npm run test:e2e`: 27 passed, 3 flaky (passed on retry: client inquiry, pending applicant, payout details), 0 failed. Not resolved: real two-session concurrency for the race cases (tested one step at a time only); the billing (12C) e2e test failed in earlier parallel runs with or without this feature and passes alone. Local only; not pushed.
