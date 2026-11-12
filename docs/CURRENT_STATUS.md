# Current Status

**Phase:** 3 (public website and client inquiries) complete. `main` = Phases 0–3 plus Windows
setup (`e70dfec`). Nothing pushed. Development machine: Windows (moved from macOS 2026-11-12).
Decisions applied: A, D, E, H, L, M, N, O, R, S, U, V; KB3 placeholder list (OPEN_QUESTIONS).
**Last updated:** 2026-11-12

Per-phase implementation details and verification history: `docs/CHANGELOG.md` (read only when
needed).

## What exists

- **Phase 0:** Next.js 16.4, Tailwind v4, shadcn/ui (base-ui), ESLint + Prettier, Vitest, local
  Supabase, pgTAP, CI workflow.
- **Phase 1, auth and access:** sign-up grants no access; `private.is_admin()` requires MFA
  `aal2`; append-only `activity_logs`; gated `/apply`, `/editor`, `/admin`.
- **Phase 2, editor applications and vetting:** `/apply` and `/admin/applications`; admin
  workflow functions (`admin_approve_application` is the only path to `active`); vetting notes;
  suspend/reactivate/revoke.
- **Phase 3, public site and inquiries:** home page with separate inquiry and editor entry points;
  `/inquire` (anon, rate-limited, honeypot); `/admin/inquiries`; `/admin/settings` (service types,
  budget ranges; no budget ranges seeded).
- **Tests:** pgTAP 151, Vitest 58. Last verified 2026-11-12 on Windows (check, db:test,
  db:advisors).
- **Claude Code guardrails:** `.claude/settings.json` + `.claude/hooks/` (env-file and committed-
  migration protection, approval for push/commit and hosted operations, Prettier on edit). Hook
  tests: `node --test .claude/hooks/guard.test.mjs`.

## Not yet done / not verified

- Nothing pushed. No GitHub remote, Vercel or hosted Supabase project; CI has never run.
- Not tested: hosted Supabase (MFA plan, SMTP), Playwright e2e, mobile layouts in depth.
- Not exercised in the browser (pgTAP only): application reject, reopen, withdraw, practical-test
  result recording.
- Suspended users keep their session (they lose access on the next request).
- No admin UI for managing `profile_options` yet (seeded list only).
- Editors cannot yet edit their profile after approval (no editor profile page).
- Notifications (e.g. telling applicants about requests/decisions) are not built (KB §17.10).
- Placeholder legal pages only (`/legal/editor-terms`, `/legal/privacy`, version
  `placeholder-2026-11-11`).

## Known issues

- **Supabase Postgres image 17.6.1.106 crash:** a "permission denied for function" raised for
  `anon`/`authenticated` crashes Postgres (`supautils` hint bug). Mitigation: internal functions in
  `private`; pgTAP guardrail requires every `public` function to be executable by both API roles;
  functions authorise in their body. Re-check on hosted Supabase before launch.
- **Supabase CLI 3.x rejects `supabase/config.toml`** (`[inbucket]` must become `[local_smtp]`,
  possibly more). The CLI is pinned to 2.122.1 locally and in CI until the config is migrated.
- Next 16 dev overlay logs "Could not validate `instant`" when a gate redirects. Expected; dev-only.
- `npm audit`: 7 moderate advisories in dev-only lint tooling. Do not `npm audit fix --force`.
- Component tests deferred (`@vitejs/plugin-react` peer conflict with shadcn CLI).
- Keep ≥ 10 GB free disk for Docker; `npm run db:start` skips heavy services.
- `supabase db reset` wipes local accounts (including any you registered); re-register after.
  Accounts from the Mac did not carry over.
- **Don't run `npm run build` while `npm run dev` is running**: it corrupted the dev server's route
  cache (all `(auth)` pages returned 404). Restart the dev server if it happens.
- **After editing `supabase/templates/*.html`, restart local Supabase** (`npm run db:stop` then
  `npm run db:start`). Kong bind-mounts each template file; editors and formatters replace the file,
  so Kong keeps serving the deleted original (404) and auth falls back to the default email. Local
  development only.
- Inquiry rate limits are a first line of defence only; Turnstile (decision O) is a launch gate.

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
- `converted` inquiry status is reserved for Phase 4 conversion (cannot be set by hand).

## Next task

Phase 4 (projects, briefs, inquiry → project conversion), which needs owner decisions **J** and
**T**. Before public launch (not development): KB1, KB2, KB8, P, Turnstile (O), production SMTP,
and your real service list and budget ranges (Settings screen).
