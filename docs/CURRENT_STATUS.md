# Current Status

**Phase:** Phase 10 **notifications, admin metrics and audit view done** (database + screens) on
branch `phase10-notifications` (uncommitted, pending owner review; KB10 adopted 2026-11-14, email
queued in a private outbox but not sent until production SMTP). Before that: Phase 8 **submissions, review and revision classification done** (database +
screens) on branch `phase8-submissions` (uncommitted, pending owner review; spec calls §7 in
`docs/superpowers/specs/2026-11-14-phase8-submissions-design.md`: per-project versions, payment
moves to `pending_approval` on work approval, assignment stays `in_progress` after completion,
needs-discussion opens a disputed request). F and KB5 untouched (facts only: rounds,
beyond-allowance flag, late flag). Earlier: Phase 9 **payments and earnings done** (database + screens) on branch
`phase4-followups` (uncommitted, pending owner review). **Phase 9 flags:** (a) F: ended
assignments put unpaid payments on hold automatically with a fixed editor-visible reason (spec call
2); (b) E: mark paid cannot check verified payout details yet (call 11) — resolve before recording
real transfers; (c) suspended/revoked editors lose the earnings screen (call 9). Spec/plan calls
(`docs/superpowers/specs|plans/2026-11-14-phase9-earnings*`) await owner review.
Phase 7 **database layer done** (uncommitted, pending owner review), on top of the
uncommitted-review Phases 5-6 database. **Flagged for the owner:**
(1) order: admin confirmation stays first (decision B), then interpretation, brief confirmation and
a gated start (spec call 1); (2) drift: any deadline or agreed-pay change after confirmation
requires re-confirmation (spec call 6). Phase 4 committed. Nothing pushed.
Development machine: Windows. Decisions applied: A, D, E, H, J, L, M, N, O, R, S, T, U, V; KB3
placeholder list (OPEN_QUESTIONS).
**Last updated:** 2026-11-14

Per-phase implementation details and verification history: `docs/CHANGELOG.md` (read only when
needed). Phase 4 design: `docs/superpowers/specs/2026-11-13-phase4-projects-briefs-design.md`.

## What exists

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
- Nothing pushed. No GitHub remote, Vercel or hosted Supabase project; CI has never run.
- Not tested: hosted Supabase (MFA plan, SMTP), signed-in e2e flows (smoke tests cover public pages
  and signed-out gates; not in CI), mobile layouts in depth.
- Not exercised in the browser: application reject, reopen, withdraw, practical-test results.
- Suspended users keep their session (they lose access on the next request).
- Suspending or revoking an editor does not close their assignments automatically (WORKFLOWS §6:
  the admin decides per assignment). The admin project page's Editors panel shows a "Suspended" /
  "Access revoked" badge next to such an editor while they hold a live or confirmed assignment.
- No admin UI for `profile_options`; editors cannot edit their profile after approval.
- Notifications (KB §17.10) not built. Placeholder legal pages only (`placeholder-2026-11-11`).

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

1. Owner review of the Phases 5-6 and Phase 7 database diffs, spec and plan calls (db-security
   review recommended), then commit (needs owner approval).
2. Phase 7 screens (editor steps panel, admin gate panel and interpretation review) after review;
   Phase 5-6 screens. Phase 8 screens and flow need a signed-in browser check.
3. Signed-in browser check of `/admin/projects`, `/admin/clients` and the conversion form, and of
   the Phase 10 screens (bell, `/notifications`, `/admin` metrics, `/admin/activity`).
4. Wire an email sender to `private.notification_outbox` once production SMTP exists.

Before public launch: KB1, KB2, KB8, P, Turnstile (O), production SMTP, real service list and
budget ranges (Settings screen).
