# Current Status

**Phase:** 4 (projects, briefs, clients, inquiry conversion) implemented on branch
`phase4-projects`, **uncommitted**. `main` = Phases 0-3 plus Windows setup. Nothing pushed.
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
- **TokenEconomizer trial** (local scope; see CHANGELOG): propose-only tool pruning, micro-skills,
  loop guard nudges. Review proposals with `/tokeneconomizer:status` before applying.
- **Design system:** `docs/DESIGN_SYSTEM.md`; tokens, shell (`src/components/app-shell/`), status
  pills, empty/loading/error states applied to admin lists.
- **Tests (2026-11-14):** pgTAP 472/472, Vitest 132/132 (`npm run check` green), Playwright smoke
  12/12 (incl. signed-out gates for `/admin/projects`, `/admin/projects/new`, `/admin/clients`).
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

1. Owner review of the Phase 4 diff, then commit (needs owner approval) and merge.
2. Signed-in browser check of `/admin/projects`, `/admin/clients` and the conversion form.
3. Phase 5 (assets, reference visibility, asset access grants); `project_references` already
   exists. Constraints from Phase 4 are in DEVELOPMENT_ROADMAP. Blocking questions B, K, KB7.
4. Owner-approved follow-up migration for the PUBLIC-executable functions above.

Before public launch: KB1, KB2, KB8, P, Turnstile (O), production SMTP, real service list and
budget ranges (Settings screen).
