# Current Status

**Phase:** 1 (auth and access gating) implemented and verified locally, **not yet committed**.
Phase 0 committed as `cf76cc7`. Decisions A, L, R applied (see OPEN_QUESTIONS decisions log).
**Last updated:** 2026-11-11

## Implemented

### Phase 0

Next.js 16.4 (App Router, `src/`, TS strict), Tailwind v4, shadcn/ui (base-ui), ESLint + Prettier,
Vitest, local Supabase config, pgTAP, CI workflow, split docs, `CLAUDE.md`.

### Phase 1 (2026-11-11)

**Database** (`supabase/migrations/20261111122133_phase1_auth_access.sql`):

- Tables: `profiles` (no role column), `admin_users`, `editor_profiles.access_status`
  (`none`/`active`/`suspended`/`revoked`), `activity_logs` (append-only, enforced by trigger).
- Sign-up trigger creates profile + editor profile with **no access**; ignores user metadata.
- Helpers in the non-exposed `private` schema: `is_admin()` (requires `aal2` = MFA-verified
  session), `is_admin_account()` (routing only), `is_active_editor()`.
- Admin bootstrap: `private.grant_admin_by_email(email, note)`, executable only by `postgres`.
- Audit triggers: account registration, admin grant/revoke, every access-status change.
- Explicit grants; default privileges revoked so new tables/functions are not API-reachable
  until a migration grants them. `anon` has no table access.

**Auth config** (`supabase/config.toml`): email confirmation required (R), TOTP MFA enabled (A),
passwords ≥ 10 chars with letters and digits, `secure_password_change`, custom confirmation and
recovery email templates (`supabase/templates/`) using the SSR `token_hash` flow.

**App:**

- `src/lib/supabase/*`: server client (per request, RLS-bound, `connection()` so auth is never
  prerendered), `proxy.ts` session refresh with cache-header handling, generated DB types.
- `src/lib/auth/access.ts`: Data Access Layer (`getAccess`, `requireApplicant`,
  `requireActiveEditor`, `requireAdminAccount`, `requireAdmin`), memoised per request only.
- `src/lib/auth/safe-next-path.ts`: open-redirect guard for `?next=`.
- `src/features/authentication/`: zod schemas, server actions (sign-up, sign-in, sign-out, reset
  request, new password), admin MFA actions (enrol, verify), client forms.
- Routes: `/sign-up`, `/sign-in`, `/forgot-password`, `/reset-password`, `/auth/confirm`, `/mfa`,
  `/apply` (applicants), `/editor` (active editors), `/admin` (admin + MFA; overview counts and
  recent activity). Each gated area checks access server-side inside a `<Suspense>` boundary.

**Tests:**

- pgTAP (44): RLS guardrail; public-function guardrail; five identities (anon, applicant, editor
  A, editor B, admin with and without MFA); metadata escalation; self-activation; cross-user
  edits; admin bootstrap not callable; audit log append-only; suspension and admin revocation are
  immediate.
- Vitest (27): password/email/TOTP validation, sign-up ignores injected role fields,
  open-redirect guard.

## Verified (2026-11-11)

- `npm run check`, `npm run build`, `npm run db:test`, `npm run db:advisors` (no issues): all pass.
- In the browser against local Supabase: signed-out redirect; sign-up validation (server-side);
  unconfirmed sign-in blocked; email confirmation via Mailpit lands on `/apply`; applicant blocked
  from `/editor`, `/admin`, `/mfa`; activation → `/editor` and suspension → `/apply` on next
  request; admin bootstrap; admin without MFA forced to `/mfa`; TOTP enrolment (wrong code
  rejected); admin overview; returning admin must enter a code; active editor blocked from admin
  areas; password reset end to end.
- Through the real REST API with real tokens: applicant and non-MFA admin see only their own
  profile; non-MFA admin sees no audit log; anon denied; self-activation denied; editing another
  user's profile affects 0 rows.

## Not yet done / not verified

- Nothing committed or pushed. No GitHub remote, Vercel project or hosted Supabase project.
- CI has never run on GitHub.
- Not tested: hosted Supabase (MFA plan availability, SMTP), Playwright e2e (manual browser
  checks only), mobile layouts.
- Admin UI to activate/suspend editors is Phase 2; locally use SQL (see `supabase/seed.sql`).
- Suspended users keep their session (they just lose access on the next request); forced
  sign-out would need the Auth admin API and is not implemented.

## Known issues

- **Supabase Postgres image 17.6.1.106 crash:** a "permission denied for function" raised for
  `anon`/`authenticated` crashes Postgres (segfault; `supautils` permission-hint feature). Table
  permission errors are unaffected. Mitigation: functions not meant for the API live in
  `private`, and a pgTAP guardrail requires every `public` function to be executable by both API
  roles (they must authorise in the body). Re-test after upgrading the Supabase CLI/image, and
  check hosted Supabase before launch.
- Next 16 dev overlay logs "Could not validate `instant`" when a gate redirects (for example an
  applicant opening `/admin`). Expected: the redirect is the access control. Dev-only.
- `npm audit`: 7 moderate advisories in dev-only lint tooling (`@typescript-eslint/*` via
  `eslint-config-next`). Do not `npm audit fix --force`.
- `@vitejs/plugin-react` conflicts with shadcn CLI's Babel peer deps; component tests deferred.
- Local Docker was damaged by a full disk on 2026-11-11 (corrupted Kong image, since re-pulled).
  Keep ≥ 10 GB free; `npm run db:start` skips heavy services (`db:start:full` for Studio etc.).

## Decisions made (implementation)

- npm, Node ≥ 24; `npm run typecheck` runs `next typegen` first; `proxy.ts` (Next 16).
- Password policy ≥ 10 chars, letters + digits (security default; owner may change).
- MFA enforced in the database (`private.is_admin()` requires `aal2`), not only in the UI.
- No browser Supabase client yet: all auth runs in server actions.
- Owner decisions live in `docs/OPEN_QUESTIONS.md`.

## Next task

Phase 2: editor applications and vetting (DEVELOPMENT_ROADMAP). Needs owner answers to **M**
(re-application after rejection) and confirmation that applications contain no bank fields (E);
**G** only for whether assessments record payment. Before that: commit Phase 1, and decide when to
create the GitHub remote so CI starts running.
