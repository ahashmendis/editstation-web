# Current Status

**Phase:** Phases 0-11, Phase 12 (12A-12E), the landing page upgrade and open opportunities are built and merged into `main`, pushed to GitHub with CI green on `12c4d84` (2026-11-17). Older bullets below that say "branch ... uncommitted" are historical: every one of those branches is merged. Launch readiness (milestones, blockers, owner actions): `docs/LAUNCH_READINESS.md`.
Phase 11 added signed-in Playwright e2e, security headers, a local backup/restore drill,
`docs/RUNBOOKS.md` and the KB §16 evidence table (below). Full report:
`docs/reports/editstation-system-report.html`. Owner flags still open from
earlier phases: Phase 9 (a) F: ended assignments put unpaid payments on hold automatically (12D part 2 settles scheduled cancellations instead), (b) E:
mark paid now checks the payout account (12E, on branch: interim attestation while payout details stay locked), (c)
suspended/revoked editors lose the earnings screen; Phase 7 (1) admin confirmation before
interpretation, (2) deadline/pay drift requires re-confirmation; Phase 8 spec calls §7.
Development machine: Windows. Decisions applied: A, D, E, H, J, L, M, N, O, R, S, T, U, V, I,
KB10; KB3 placeholder list (OPEN_QUESTIONS). Recorded 2026-11-15: F partly built (12A terms), KB7/KB7a built on branch (12B), KB9 client side built (12C), editor milestones, late-balance protection and dispute splits built on branch (12D part 1), extra pay offers, scope quotes and cancellation settlement built on branch (12D part 2). 2026-11-16: E built LOCKED with the interim attestation (12E, branch `phase12e-payout`).
**Last updated:** 2026-11-17 (decisions adopted, launch readiness report)

Per-phase implementation details and verification history: `docs/CHANGELOG.md` (read only when
needed). Phase 4 design: `docs/superpowers/specs/2026-11-13-phase4-projects-briefs-design.md`.

## What exists

- **Open opportunities (branch `open-opportunities`, uncommitted, pending owner review,
  2026-11-16; B/C amended, spec approved with every recommended call):** admin-written summary
  table `project_opportunities` (editor-visible, no client data; pay stored only when shown) and
  append-style `opportunity_interests` (an editor reads only their own). Functions
  `admin_publish_opportunity` (also reopens), `admin_update_opportunity`,
  `admin_close_opportunity`, `editor_list_opportunities` (allow-list projection),
  `editor_register_interest` (optional proposed rate and note; max 10 live; not after
  declined/not selected/live offer), `editor_withdraw_interest`, `admin_list_interests`,
  `admin_select_editor` (calls `admin_make_offer`, others not selected, opportunity filled). A
  project leaving the open stage for good closes its opportunity. Notification kinds
  `interest_registered`, `opportunity_selected`, `opportunity_not_selected`. App:
  `/editor/opportunities` (nav link, confidentiality notice), "Open opportunity" card on
  `/admin/projects/[id]`. pgTAP `112`-`114` (046 allow-list updated); e2e "open opportunities".
  Owner calls to confirm are in `CHANGELOG.md`.

- **Phase 12E payout details, LOCKED (branch `phase12e-payout`, uncommitted, pending owner review,
  2026-11-16):** `editor_payout_details`, append-only `editor_payout_detail_versions` and
  `editor_payout_attestations`, no API grants (functions only). `app_settings.payout_details_enabled`
  is **false**: while off every payout write refuses (ES409) and a guard trigger refuses any insert,
  so no bank data can be stored. Functions: `editor_save_payout_details` (any change -> unverified,
  version row, admin notification `payout_details_changed`), `editor_get_payout_details` (masked),
  `admin_get_payout_details_masked`, `admin_reveal_payout_details` (reason required, always
  audited), `admin_verify_payout_details` (method + note, for the version shown),
  `admin_set_payout_enabled`, `admin_attest_payout_outside_app` (call 1, only while off). Mark-paid
  now requires a current attestation (off) or verified details (on). Audit rows hold ids and field
  names only. App: payout card on `/editor/earnings`, admin payout card on `/admin/earnings/[id]`
  and `/admin/earnings?editor=`, toggle with the PDPA warning on `/admin/settings`. pgTAP
  `109`-`111`; older mark-paid tests seed an attestation. **Turn on only after counsel confirms PDPA
  handling.** No field-level encryption yet (SECURITY_AND_PRIVACY S10).

- **Phase 12D part 2 extra pay and settlement (branch `phase12d2-adjustments`, uncommitted,
  pending owner review, 2026-11-15):** `compensation_adjustments` (admin offers, editor accepts or
  declines; accepting creates its own payable payment row), `revision_requests.adjustment_required`
  and a database gate (a marked round or a scope change cannot begin until extra pay, and for a
  scope change the client quote, is accepted), admin-only `scope_change_quotes` (acceptance adds an
  invoiced extra-work client milestone with an admin due date), extra-round client charges from the
  terms, `payment_status.cancelled` and `admin_settle_cancellation` (cancels and settles: schedule
  maths, unpaid rows cancelled, shortfall row or overpayment reversal, client refund rows),
  notification kinds `adjustment_offered` / `adjustment_answered`. App: extra pay and settlement
  cards on `/admin/projects/[id]`, offers on `/editor/projects/[id]` and `/editor/earnings`,
  extra/cancelled/settlement lines on both earnings pages. pgTAP `105`-`108`. Owner calls are
  listed in `CHANGELOG.md`. Not yet: payout details (12E); signed-in e2e not extended.

- **Phase 12D part 1 editor pay (branch `phase12d-editor-pay`, uncommitted, pending owner review,
  2026-11-15):** editor milestone rows from the agreed terms shares (default 50/50, last row takes
  the rounding remainder), payable on client deposit verified (milestone 1) and on approval with
  the client balance verified (later milestones), due = payable date + editor pay days (business
  timezone); late-balance protection in `private.apply_timed_rules` (notifies admins,
  `late_balance_payable`); deposit flag nets refund rows; partial-dispute split
  (`admin_split_payment_for_dispute`, only the disputed part held); `editor_list_payments` returns
  fixed hold labels ("Under review", "Waiting for client payment") instead of reasons. App:
  milestones on `/editor/earnings`, `/admin/earnings` and `/admin/earnings/[id]` (payable reason,
  split form). pgTAP `102`-`104`. Part 2 (above) adds extra pay, scope quotes and settlement;
  payout details are 12E.

- **Phase 12C client billing (branch `phase12c-billing`, uncommitted, pending owner review,
  2026-11-15):** admin-only `client_milestones` (default 50/50 of the client price, per-project
  split such as 100% upfront, invoice/due dates, record and verify transfers, audited correction,
  deposit extension), deposit start gate (editors see only "Waiting for the client deposit"),
  unpaid-deposit auto-hold via `private.apply_timed_rules` (admin dashboard and `/admin/earnings`
  run it; `pg_cron` on hosted not scheduled), business timezone setting (default Asia/Colombo,
  call 4 to confirm). Details: `docs/CHANGELOG.md`, `DATABASE_SCHEMA.md`.

- **Phase 12B assets (branch `phase12b-assets`, uncommitted, pending owner review, 2026-11-15):**
  migrations `20261115042630_phase12b_notification_kind.sql`,
  `20261115042633_phase12b_assets_schema.sql`, `20261115042637_phase12b_assets_functions.sql`:
  asset description, access instructions, `access_status` (awaiting/verified/inaccessible, only an
  admin verifies), editor "I can open this" hint; share `access_type` with an admin security
  warning for anyone-with-the-link; append-only `asset_access_reports`;
  `editor_report_asset_inaccessible` (assigned editor only, notifies admins with the new
  `asset_inaccessible` kind), `editor_confirm_asset_access`, `admin_verify_asset`,
  `admin_resolve_asset_report`, `admin_request_access_removal`, `admin_confirm_access_removal`;
  revoke checklist shows requested/confirmed states. App: Asset access card and removal buttons on
  `/admin/projects/[id]` and `/admin/access-review`, new asset form fields, editor asset list with
  description, instructions, "I can open" and a report form. pgTAP `096`-`098`. Signed-in e2e not
  extended (no route changes); the new screens are covered by pgTAP and unit tests only.

- **Phase 12A terms (branch `phase12a-terms`, uncommitted, pending owner review, 2026-11-15):**
  migrations `20261115032846_phase12a_terms_schema.sql` and
  `20261115032849_phase12a_terms_functions.sql`: admin-only versioned `project_terms` +
  `project_terms_stages`, guard triggers (agreed rows immutable, revision allowance is a cache),
  `admin_save_terms_draft`, `admin_agree_terms`, `editor_get_terms`, confirm gate in
  `admin_confirm_assignment`, `admin_update_project` no longer takes `revision_allowance`, draft
  terms v1 for every new project, local backfill. App: Terms card on `/admin/projects/[id]`,
  editor-safe Terms summary on `/editor/projects/[id]`, create form "Included revision rounds"
  (pre-filled 3, create only). pgTAP `093`-`095`; existing confirm tests now agree terms first.
  Signed-in e2e covers save draft, agree and the editor summary. Details: `CHANGELOG.md`.

- **Phase 0-3:** tooling and CI; auth and access gating (`private.is_admin()` needs MFA `aal2`);
  editor applications and vetting (`/apply`, `/admin/applications`); public site, `/inquire`
  (anon, rate-limited, honeypot), `/admin/inquiries`, `/admin/settings`.
- **Phase 4 (uncommitted):** six migrations `20261114*_phase4_*.sql` (`clients`, `projects`,
  `project_internal`, `brief_versions`, `project_deliverables`, `project_references`,
  `client_inquiries.converted_project_id`); admin-read-only RLS, writes only via `public.admin_*`
  functions; brief versions immutable after first opening; screens `/admin/projects` (list, new,
  detail), `/admin/clients`, and a "Convert to project" form on the inquiry page
  (`admin_convert_inquiry`). Statuses `draft`/`open`/`on_hold`/`cancelled` only; later statuses
  exist in the enum but are set by later phases.
- **Phases 5-6 database (uncommitted, pending owner review):** seven migrations
  `20261114061439` to `20261114063650` (`project_assets`, `project_references.early_access`,
  `asset_access_grants`, `project_access`, `assignments`, `negotiation_offers`, `project_notes`);
  tiered editor reads via `private.editor_project_stage`; 16 new or replaced functions (assets,
  early access, folder shares and revoke checklist, access, offers, counters, confirm, reassign,
  notes, `editor_respond_offer`, cancellation from `assigned`). Plan calls in
  `docs/superpowers/plans/2026-11-14-phase5-6-database.md` await owner review.
- **Phase 7 database (uncommitted, pending owner review):** six migrations `20261114115858` to
  `20261114121138`: `assignment_status.in_progress`, `editor_interpretations`,
  `brief_confirmations`, gate `private.assignment_gate` enforced by triggers on `assignments` and
  `projects`, carry-forward on `brief_versions`, six new functions (interpretation submit/review,
  confirm brief, editor/admin start, `get_assignment_gate`) and Phase 6 replacements for
  `in_progress`. Spec and plan calls (`docs/superpowers/specs|plans/2026-11-14-phase7-*`) await
  owner review. F and KB5 untouched.
- **TokenEconomizer trial** (local scope; see CHANGELOG): propose-only tool pruning, micro-skills,
  loop guard nudges. Review proposals with `/tokeneconomizer:status` before applying.
- **Design system:** `docs/DESIGN_SYSTEM.md`; tokens, shell (`src/components/app-shell/`), status
  pills, empty/loading/error states applied to admin lists.
- **Phase 9 (uncommitted, pending owner review):** `payments` + `payment_notes`, creation/hold
  triggers on `assignments`, six `admin_*` payment functions and `editor_list_payments`; screens
  `/editor/earnings`, `/admin/earnings`, `/admin/earnings/[id]`. Not yet checked signed in.
- **Phase 8 (uncommitted, pending owner review):** three migrations `20261114154439` to
  `20261114154448` (`submissions`, `revision_requests`, six functions, review-status guard on
  `projects`, cancel/reassign/confirmation allowed in review); Submissions card on
  `/editor/projects/[id]`, Review card on `/admin/projects/[id]`. Not yet checked signed in.
- **Phase 10 (uncommitted, pending owner review):** `notifications` + private outbox, trigger on
  `activity_logs`, mark-read functions, `admin_dashboard_metrics`; bell in the shells,
  `/notifications`, metrics on `/admin`, `/admin/activity`. Not yet checked signed in.
- **Phase 11 (uncommitted, pending owner review):** signed-in e2e `tests/e2e/signed-in.spec.ts`
  with seed-free helpers `tests/e2e/support/local-stack.ts` (local service key read from
  `supabase status` at runtime, SQL via `docker exec`, Mailpit for the sign-up email, built-in RFC
  6238 TOTP for admin MFA; global setup/teardown removes all e2e data so pgTAP still sees a clean
  database); security headers in `next.config.ts`; restore drill `npm run db:restore-test`
  (`scripts/db-restore-test.mjs`); `docs/RUNBOOKS.md`.
- **Tests (2026-11-15, Phase 11):** `npm run check` green (Vitest 250/250), pgTAP 1545/1545,
  Playwright 24/24 (19 smoke + security headers + 4 signed-in), restore drill passed.
- **Tests (2026-11-14):** pgTAP 1543/1543 after Phase 10, Vitest 245/245, Playwright 19/19;
  pgTAP 1482/1482 after Phase 8, Vitest 223/223, Playwright 17/17;
  pgTAP 1357/1357 after Phase 9 (1133 after Phase 7), Vitest 212/212
  (`npm run check` green), Playwright smoke 17/17 (incl. signed-out gates for the earnings routes).
- **Claude Code guardrails:** `.claude/settings.json` + `.claude/hooks/` (env-file and committed-
  migration protection, approval for push/commit and hosted operations). Tests:
  `node --test .claude/hooks/guard.test.mjs`.

## Not yet done / not verified

- **Phase 4 admin screens have not been checked in a signed-in browser session** (pgTAP and unit
  tests only). The app shell likewise has only been seen on a temporary page.
- `main` is pushed to GitHub (`ahashmendis/editstation-web`, 2026-11-15) and CI is green (app,
  pgTAP, e2e). Hosted (2026-11-17): Supabase project `editstation` (ref `jatxlruwgopzoetqegmo`,
  ap-south-1) with all 55 migrations applied, and a Vercel production deployment at
  https://editstation.vercel.app (CLI deploys; GitHub auto-deploy not connected). First admin
  created with MFA. Auth config pushed from `supabase/config.toml` `[remotes.production]` (site URL,
  redirect, password rules). Brevo SMTP is configured on hosted Supabase (sender `no-reply@editstation.work`) and the branded
  auth and security-notification emails are pushed. Notification emails (feature A, 2026-11-17):
  migration `20261117143615` and worker route `/api/cron/send-emails` (owner steps in
  `docs/RUNBOOKS.md` section 8).
  Notification emails are live on hosted since 2026-11-17: migration applied, pg_cron job
  `send-notification-emails` every 5 minutes (Vault secret), Brevo API key and secrets in Vercel;
  a real email send has not been proven yet. Profile pictures (feature B): built, reviewed and
  tested locally (migration `20261117150324`, `/editor/profile`); NOT on hosted yet, so the
  code must not be pushed before the migration is applied there.
- Editor workspace Phase 1 (2026-11-17, local only, uncommitted pending owner approval): My projects,
  Feedback & revisions, project tabs, dashboard sections and grouped nav; no schema change. Plan and
  decisions: `docs/EDITOR_WORKSPACE_ARCHITECTURE.md`. Phases 2 to 6 (video review with a Google Drive
  player, moderation, calendar, WhatsApp, AI) are not started. Also local: signed-in visitors on `/`
  go to their own area (`/go`), and the app logo links to the user's dashboard.
- Client area C1 (2026-11-17, local only, reviewed, uncommitted pending owner approval): `/client`
  (sign-in by emailed code, projects, payments), admin invitation of client users, client updates and
  bank-details setting; migration `20261117175810`. Design: `docs/superpowers/specs/2026-11-17-client-area-design.md`.
  Order matters on hosted: the migration must be applied BEFORE the code is pushed (every signed-in
  request calls `my_client_status`). Open owner items: bank details, client terms and privacy
  notice, client-facing deadline, OTP wording and expiry (10 minutes also shortens sign-up and reset
  links). C2 (submit a project, messages) to C4 not started.
- Not tested: hosted Supabase (MFA plan, SMTP, backups), mobile layouts in depth. Signed-in e2e
  covers inquiry submit, applicant sign-up and gates, editor A/B project isolation and admin MFA
  into `/admin` + `/admin/activity`; the offer, confirmation, submission, review and payment screens
  are covered by pgTAP and unit tests only, not by a browser run.
- Not exercised in the browser: application reject, reopen, withdraw, practical-test results.
- Suspended users keep their session (they lose access on the next request).
- Suspending or revoking an editor does not close their assignments automatically (WORKFLOWS §6:
  the admin decides per assignment). The admin project page's Editors panel shows a "Suspended" /
  "Access revoked" badge next to such an editor while they hold a live or confirmed assignment.
- No admin UI for `profile_options`; editors cannot edit their profile after approval.
- Placeholder legal pages only (`placeholder-2026-11-11`).
- Only `frame-ancestors` is set in the CSP; a full script CSP (nonces) is a follow-up, as it
  changes rendering under `cacheComponents`.

## Known issues

- **Pre-Phase-4 functions executable by PUBLIC:** some Phase 1-3 functions (Phase 1 access helpers
  such as `private.is_admin`, `is_admin_account`, `is_active_editor`; Phase 2-3 public functions;
  two trigger functions) keep the default PUBLIC execute ACL. They are listed as exceptions in
  `supabase/tests/database/046_phase4_function_security.test.sql`. Fixing needs an owner-approved
  follow-up migration (the helpers are used by RLS policies, so test carefully).
- **Supabase Postgres image 17.6.1.106 crash:** a "permission denied for function" raised for
  `anon`/`authenticated` crashes Postgres. Mitigation: internal functions in `private`; every
  `public` function executable by both API roles and authorising in its body (pgTAP guardrail).
  Re-check on hosted Supabase before launch.
- **Supabase CLI 3.x rejects `supabase/config.toml`** (`[inbucket]` to `[local_smtp]`, maybe more).
  CLI pinned to 2.122.1 locally and in CI.
- Next 16 dev overlay logs "Could not validate `instant`" when a gate redirects. Dev-only.
- `npm audit`: 7 moderate advisories in dev-only lint tooling. Do not `npm audit fix --force`.
- Component tests deferred (`@vitejs/plugin-react` peer conflict with shadcn CLI).
- Keep >= 10 GB free disk for Docker. `supabase db reset` wipes local accounts; re-register after.
- **Don't run `npm run build` while `npm run dev` runs** (corrupts the route cache; restart dev).
- **After editing `supabase/templates/*.html`, restart local Supabase** (`db:stop`, `db:start`).
- Inquiry rate limits are a first line of defence only; Turnstile (decision O) is a launch gate.

## Phase 11 security review (2026-11-15)

Swept every server action (15 files), page gate, route handler and error path. Findings:

- All admin/editor/applicant pages call a `require*` gate; every admin action calls
  `requireAdmin()` and every database function authorises in its body (pgTAP guardrails).
- Database errors reach users only through `userMessageFromDbError` (ES4xx messages); auth errors
  through `authErrorMessage`; the error boundary shows only a digest. No secret key or
  non-`NEXT_PUBLIC_*` env var in `src/`; no `dangerouslySetInnerHTML`; `?next=` is
  same-site only (`safeNextPath`).
- **Fixed:** no security headers were sent. Added `X-Frame-Options: DENY`, CSP
  `frame-ancestors 'none'` (clickjacking on admin forms), `nosniff`, `Referrer-Policy`,
  `Permissions-Policy`; covered by an e2e smoke test.
- Still open (known): Phase 1-3 functions with PUBLIC execute (needs an owner-approved migration);
  suspended users keep their session until the next request.

## KB §16 acceptance criteria: evidence

pgTAP files are in `supabase/tests/database/`; e2e in `tests/e2e/`. "Met" means implemented and
tested locally. Hosted stack exists since 2026-11-17 (see Hosted note above); a hosted smoke test,
backup tier and restore drill are still outstanding.

| KB §16 criterion                                                                         | Evidence                                                                                                              | Status                                                                                   |
| ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Roles enforced server-side                                                               | `require*` gates on every page/action; `private.is_admin()` (aal2); e2e gates in `smoke.spec.ts`, `signed-in.spec.ts` | Met                                                                                      |
| Unapproved editors cannot access restricted projects                                     | 053 visibility; e2e applicant redirected from `/editor`, `/admin`                                                     | Met                                                                                      |
| Editors cannot see other editors' records or payments                                    | 053, 071, 075; e2e editor A vs B (404 on B's project)                                                                 | Met                                                                                      |
| Admin-only actions not invocable by editors                                              | `private.require_admin()` in every `admin_*`; 046, 058, 066, 076, 082                                                 | Met                                                                                      |
| RLS tested with separate identities                                                      | admin, editor A, editor B, applicant, anon in every RLS test                                                          | Met                                                                                      |
| Admin can create all three brief types                                                   | 042                                                                                                                   | Met (DB; admin form not run in e2e)                                                      |
| Multiple references per project                                                          | 050, 051                                                                                                              | Met                                                                                      |
| Reference timestamps, notes, categories, priorities visible to assigned editor           | `project_references` columns; 053 tiered reads                                                                        | Met                                                                                      |
| Brief versions and confirmations retained                                                | 043, 063 (immutable)                                                                                                  | Met                                                                                      |
| Assets accessible only to authorised users                                               | 051, 053 (app records); folder shares at the storage provider are manual (K, KB7 open)                                | Partly met                                                                               |
| Admin can invite a particular editor                                                     | 054; e2e uses `admin_grant_project_access` + offer                                                                    | Met                                                                                      |
| Eligible editors accept or counter                                                       | 056                                                                                                                   | Met                                                                                      |
| Final rate explicit and approved before work                                             | 055, 063, 064                                                                                                         | Met                                                                                      |
| No active editing with unresolved compensation                                           | 061 gate triggers                                                                                                     | Met                                                                                      |
| Editors submit versions; admin approves or requests revisions; history kept              | 081                                                                                                                   | Met (DB; screens not run in e2e)                                                         |
| Client rounds vs corrections vs scope; rounds tracked (F: per-project policy, not built) | 081                                                                                                                   | Met (tracking; pay for extra rounds is F, open)                                          |
| Admin records/updates payment status                                                     | 073                                                                                                                   | Met                                                                                      |
| Editors see only their own payments                                                      | 071, 075                                                                                                              | Met                                                                                      |
| Only authorised admins mark paid                                                         | 074 (MFA admin), 110 (payout check E, locked); A2 open                                                                | Met with open items                                                                      |
| Transfer references and timestamps auditable                                             | 074, `activity_logs`, `/admin/activity` (e2e)                                                                         | Met                                                                                      |
| Useful error states and activity history                                                 | error boundary, `userMessageFromDbError`, empty/loading states, `/admin/activity`                                     | Met                                                                                      |
| Backups and recovery considered and tested                                               | `npm run db:restore-test` (local), `docs/RUNBOOKS.md` §1                                                              | **Partly met:** hosted backup tier and a hosted restore are untested (no hosted project) |
| Documented cancellation, withdrawal, reassignment                                        | WORKFLOWS §6, RUNBOOKS §4                                                                                             | Met (pay consequences: F open)                                                           |

**Unmet before real client work:** hosted backup/restore test; storage-provider access control
(K, KB7); payout details (E) built but locked until counsel confirms PDPA handling (interim
attestation until then); F (extra rounds, kill fees); CI has never run
(no remote); browser e2e for the offer, submission, review and payment screens.

## Decisions made (implementation)

- npm, Node >= 24; `typecheck` runs `next typegen`; `proxy.ts` (Next 16).
- Password policy >= 10 chars, letters + digits. MFA enforced in the database.
- Withdrawal treated like rejection: **pending owner confirmation, question W**.
- Rejection reasons: internal reasoning in vetting notes; only `decision_message` shown to applicant.
- Inquiry form required: name, email, service type, description. Inquiries can be reopened from
  declined/closed/spam. `converted` is set only by `admin_convert_inquiry`.
- Phase 4: `brief_type` frozen once a project has been opened; client price is never copied from an
  inquiry's budget label; deadline and pay changes do not bump the brief version.

## Next task

0. Owner review of Phase 12E (branch `phase12e-payout`, uncommitted), incl. its implementation
   calls in CHANGELOG. Payout details stay OFF until counsel confirms PDPA handling; decide whether
   field-level encryption is required before turning them on (S10). Follow-up: a two-session
   test of the flag races (CHANGELOG).

1. Owner decisions of 2026-11-15 (KB7 client Drive/Dropbox links, F per-project revision policy,
   KB9 50/50 client and editor milestones) are recorded in docs only; **code still reflects the old
   model** (default 3 rounds, one editor payment per assignment, no client billing records, no
   asset verification). F2, KB9a, KB9b, KB7a and the E go-ahead were answered the same day; next: design Phase 12 (planned changes in
   `DATABASE_SCHEMA.md`). Security assessment: separate, owner-led (findings S1-S10 in
   `SECURITY_AND_PRIVACY.md`).
2. Extend signed-in e2e to the offer → confirmation → submission → review → payment path
   (helpers in `tests/e2e/support/local-stack.ts` already create admins with MFA and offers).
3. Owner: hosted Supabase plan and backup tier, then a hosted restore drill (RUNBOOKS §1).
4. Wire an email sender to `private.notification_outbox` once production SMTP exists.

Before public launch: KB1, KB2, KB8, P, Turnstile (O), production SMTP, real service list and
budget ranges (Settings screen).
