# EDITSTATION

Internal, admin-controlled video-editing operations platform for Lenscape Studios, with two
public entry points: a client inquiry form (no accounts) and editor registration. Not a
marketplace. No client portal. Account types: admin, applicant, active editor.

@AGENTS.md

## Stack

Next.js 16 (App Router, `src/`), TypeScript strict, Tailwind v4, shadcn/ui (base-ui), Supabase
(Postgres + Auth + RLS), Vitest, pgTAP. Hosting: Vercel. npm, Node >= 24.

## Commands

- `npm run dev` / `npm run build`
- `npm run check`: format check, lint, typecheck and unit tests (run before saying work is done)
- `npm run db:start` / `db:stop` / `db:reset`: local Supabase (needs Docker; `db:start:full` adds Studio)
- `npm run db:test`: pgTAP tests in `supabase/tests/database/`
- `npm run db:advisors`: Supabase security/performance lints; `npm run db:types` after schema changes
- New migration: `supabase migration new <name>`; never edit an applied migration
- Local email (confirmations, resets): Mailpit at http://127.0.0.1:54324
- After editing `supabase/templates/*`, restart local Supabase; don't run `build` while `dev` runs

## Non-negotiable rules

- RLS on every `public` table; default deny. A pgTAP guardrail fails if any table lacks RLS.
- Authorisation is enforced in the database and on the server, never only by hiding UI.
- Registering grants no access. Editor access = `editor_profiles.access_status = 'active'`, set
  only by admin functions. Never trust role/status from sign-up metadata. Admins never self-register.
- Client inquiries are leads, never projects; only an admin converts one.
- Admin authorisation = `private.is_admin()`, which requires an MFA (`aal2`) session.
- DB helpers and anything not meant for the API go in the `private` schema. Every function in
  `public` must be executable by both `anon` and `authenticated` and authorise in its body
  (pgTAP guardrail; a function permission error crashes this Postgres image, see CURRENT_STATUS).
- Server code uses `src/lib/supabase/server.ts` + `src/lib/auth/access.ts`; per-request auth reads
  sit inside `<Suspense>` (Next `cacheComponents`). Never cache access decisions across requests.
- Editors never write money/status columns directly: state changes go through Postgres functions.
- Workflow functions raise user-safe errors with custom SQLSTATEs `ES401`/`ES403`/`ES409`/`ES422`
  (never `42501`); the app shows only those messages (`userMessageFromDbError`).
- Editor-visible tables must not hold client data or client pricing (RLS is row-level, not column-level).
- No editing starts until compensation is agreed and admin-approved.
- 3 free client revision rounds; editor-caused corrections and scope changes do not consume them.
- Large media never goes into Postgres. Store links/metadata only.
- Never expose secret keys to the browser. Never invent legal, tax, pricing, domain or trademark facts.
- Do not decide items listed in `docs/OPEN_QUESTIONS.md`; ask the owner when one becomes blocking.

## Read only what the task needs

| Task touches                         | Read                                                      |
| ------------------------------------ | --------------------------------------------------------- |
| Where things stand / what's next     | `docs/CURRENT_STATUS.md` (always start here)              |
| Features, access areas, exclusions   | `docs/PRODUCT_SPEC.md`                                    |
| Statuses and lifecycles              | `docs/WORKFLOWS.md`                                       |
| Rates, revisions, approvals          | `docs/BUSINESS_RULES.md`                                  |
| Tables, RLS, migrations              | `docs/DATABASE_SCHEMA.md`, `docs/SECURITY_AND_PRIVACY.md` |
| Stack, boundaries, code organisation | `docs/SYSTEM_ARCHITECTURE.md`                             |
| Phase plan                           | `docs/DEVELOPMENT_ROADMAP.md`                             |
| Unresolved decisions                 | `docs/OPEN_QUESTIONS.md`                                  |
| Business context (rarely needed)     | `docs/BUSINESS_PLAN.md`                                   |

`docs/EDITSTATION_MASTER_KNOWLEDGE_BASE.md` is the owner's original source of truth; never edit it.
Precedence: owner decisions in the `OPEN_QUESTIONS.md` decisions log > the knowledge base > derived
docs. Consult the knowledge base only to resolve ambiguity; if a derived doc conflicts, fix the
derived doc.

## Working conventions

- One bounded feature per task. Inspect existing code first. Don't touch unrelated features.
- Use the installed `supabase` and `supabase-postgres-best-practices` skills for schema/RLS work.
- Every RLS change gets pgTAP tests as admin, editor A, editor B, pending applicant, anon.
- Update `docs/CURRENT_STATUS.md` when the implementation state changes.
