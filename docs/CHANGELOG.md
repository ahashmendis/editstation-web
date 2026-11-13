# Changelog

Detailed implementation and verification history, newest first. Read only when you need the
specifics of an earlier phase; `CURRENT_STATUS.md` is the session starting point.

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
