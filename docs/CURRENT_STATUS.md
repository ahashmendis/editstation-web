# Current Status

**Phase:** 3 (public website and client inquiries) complete and committed. `main` = Phases 0–3
(`f17813d`). Nothing pushed.
Decisions applied: A, D, E, H, L, M, N, O, R, S, U, V; KB3 placeholder list (OPEN_QUESTIONS).
**Last updated:** 2026-11-12

**Development moved from macOS to Windows (2026-11-12).** Removed macOS metadata files (`._*`,
`.DS_Store`), reinstalled `node_modules` for Windows, added `.gitattributes` (LF everywhere),
and made the Supabase CLI a pinned dev dependency (`supabase@2.122.1`; CI pinned to the same
version). Re-verified on Windows: `npm run check` (58), `npm run db:test` (151),
`npm run db:advisors` (no issues), `/inquire` renders with data from local Supabase.

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

### Phase 3: public website and client inquiries (2026-11-11)

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

## Verified (2026-11-11)

- Phase 3: all DB tests (151), advisors (no issues), unit tests (58), lint, typecheck, build.
  Browser: home page and `/inquire` (desktop and 375px mobile, no horizontal overflow); empty
  submit lists required fields; privacy acknowledgement required with input kept; successful
  submission stored with link, "Prefer to discuss" budget and deadline; honeypot submission shows
  the thank-you but stores nothing; admin overview count; inquiry list and detail; status change
  to Contacted with note and audit history; adding a budget range in Settings shows it on the
  public form.
- Phase 2: `npm run check`, `npm run build`, `npm run db:test` (111), `npm run db:advisors` (no issues).
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
- **Don't run `npm run build` while `npm run dev` is running**: it corrupted the dev server's route
  cache (all `(auth)` pages returned 404). Restart the dev server if it happens.
- **After editing `supabase/templates/*.html`, restart local Supabase** (`npm run db:stop` then
  `npm run db:start`). Kong bind-mounts each template file; editors and formatters replace the file,
  so Kong keeps serving the deleted original (404) and auth falls back to the default email. Local
  development only.
- Inquiry rate limits are a first line of defence only; Turnstile (decision O) is a launch gate.
- **Supabase CLI 3.x rejects `supabase/config.toml`** (`[inbucket]` must become `[local_smtp]`,
  possibly more). The CLI is pinned to 2.122.1 locally and in CI until the config is migrated.
- Local accounts from the Mac did not carry over (fresh Docker volume); register again.

## Decisions made (implementation)

- npm, Node ≥ 24; `typecheck` runs `next typegen`; `proxy.ts` (Next 16).
- Password policy ≥ 10 chars, letters + digits (security default; owner may change).
- MFA enforced in the database, not only in the UI.
- Withdrawal treated like rejection (admin must reopen): **pending owner confirmation, question W**.
- Rejection reasons: internal reasoning goes in vetting notes; only `decision_message` is shown to
  the applicant.
- Phone is required in the application (KB §7.3 lists email and telephone).
- Inquiry form required fields: name, email, service type, project description. Phone, company,
  deliverables, budget, deadline, links and notes are optional.
- Inquiries can be reopened by an admin from declined/closed/spam back to an open status.

## Next task

Phase 4 (projects, briefs, inquiry → project conversion), which needs owner decisions J and T.
Before public launch (not development): KB1, KB2, KB8, P, Turnstile (O), production SMTP, and
your real service list and budget ranges (Settings screen). Phase 4 (projects, briefs, inquiry →
project conversion) needs J and T.
