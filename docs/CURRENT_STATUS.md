# Current Status

**Phase:** 2 (editor applications and vetting) implemented and verified locally, **not yet
committed** (branch `phase-2/editor-applications`, based on `phase-1/auth-access`).
Committed: Phase 0 `cf76cc7` (`main`), Phase 1 `9f73dad` (`phase-1/auth-access`, not merged).
Decisions applied: A, D, E, L, M, R (OPEN_QUESTIONS decisions log).
**Last updated:** 2026-11-11

## Implemented

### Phase 0

Next.js 16.4 (App Router, `src/`, TS strict), Tailwind v4, shadcn/ui (base-ui), ESLint + Prettier,
Vitest, local Supabase config, pgTAP, CI workflow, split docs, `CLAUDE.md`.

### Phase 1: auth and access gating

- DB (`20261111122133_phase1_auth_access.sql`): `profiles` (no role), `admin_users`,
  `editor_profiles.access_status`, append-only `activity_logs`; sign-up trigger (no access, ignores
  metadata); `private.is_admin()` (requires MFA `aal2`), `is_admin_account()`, `is_active_editor()`;
  admin bootstrap `private.grant_admin_by_email()`; audit triggers; explicit grants.
- Auth config: email confirmation (R), TOTP MFA (A), password ≥ 10 chars letters+digits,
  `token_hash` email templates.
- App: SSR Supabase clients, `proxy.ts`, Data Access Layer (`src/lib/auth/access.ts`), sign-up/in/out,
  password reset, admin MFA enrol/verify, gated `/apply`, `/editor`, `/admin`.

### Phase 2: editor applications and vetting (2026-11-11)

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

## Verified (2026-11-11)

- `npm run check`, `npm run build`, `npm run db:test` (111), `npm run db:advisors` (no issues).
- Browser, end to end on local Supabase: incomplete submission lists missing fields; terms required;
  insecure link rejected without losing input; submit → status + snapshot; applicant blocked from
  `/editor`; admin (MFA) list → detail → start review → vetting note → info request (approval
  blocked meanwhile); applicant sees request but not notes; response returns to review; approve
  refused without level, then approved as Professional; suspend and reactivate with reasons,
  audited; approved applicant lands on `/editor`; stale session redirects to sign-in.
- Not exercised in the browser (covered by pgTAP only): reject, reopen, withdraw, practical-test
  result recording.

## Not yet done / not verified

- Nothing pushed. No GitHub remote, Vercel or hosted Supabase project; CI has never run.
- Not tested: hosted Supabase (MFA plan, SMTP), Playwright e2e, mobile layouts in depth.
- Suspended users keep their session (they lose access on the next request).
- No admin UI for managing `profile_options` yet (seeded list only).
- Editors cannot yet edit their profile after approval (no editor profile page).
- Notifications (e.g. telling applicants about requests/decisions) are not built (KB §17.10).

## Known issues

- **Supabase Postgres image 17.6.1.106 crash:** a "permission denied for function" raised for
  `anon`/`authenticated` crashes Postgres (`supautils` hint bug). Mitigation: internal functions in
  `private`; pgTAP guardrail requires every `public` function to be executable by both API roles;
  functions authorise in their body. Re-check on hosted Supabase before launch.
- Next 16 dev overlay logs "Could not validate `instant`" when a gate redirects. Expected; dev-only.
- `npm audit`: 7 moderate advisories in dev-only lint tooling. Do not `npm audit fix --force`.
- Component tests deferred (`@vitejs/plugin-react` peer conflict with shadcn CLI).
- Keep ≥ 10 GB free disk for Docker; `npm run db:start` skips heavy services.
- `supabase db reset` wipes local accounts (including any you registered); re-register after.

## Decisions made (implementation)

- npm, Node ≥ 24; `typecheck` runs `next typegen`; `proxy.ts` (Next 16).
- Password policy ≥ 10 chars, letters + digits (security default; owner may change).
- MFA enforced in the database, not only in the UI.
- Withdrawal treated like rejection (admin must reopen): **pending owner confirmation, question W**.
- Rejection reasons: internal reasoning goes in vetting notes; only `decision_message` is shown to
  the applicant.
- Phone is required in the application (KB §7.3 lists email and telephone).

## Next task

Commit Phase 2. Then either Phase 3 (public website and client inquiries: needs N, O, S, U, V, H and
the KB3 service list) or smaller follow-ups (editor profile page, notifications). Decide when to
create the GitHub remote so CI starts running, and whether to merge the phase branches into `main`.
