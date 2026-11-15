# Changelog

Detailed implementation and verification history, newest first. Read only when you need the
specifics of an earlier phase; `CURRENT_STATUS.md` is the session starting point.

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
