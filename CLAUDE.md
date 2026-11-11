# EDITSTATION

Private, admin-controlled freelance video-editing operations platform for Lenscape Studios.
Not a marketplace. No client portal. Two roles in the MVP: `admin`, `editor`.

@AGENTS.md

## Stack

Next.js 16 (App Router, `src/`), TypeScript strict, Tailwind v4, shadcn/ui (base-ui), Supabase
(Postgres + Auth + RLS), Vitest, pgTAP. Hosting: Vercel. npm, Node >= 24.

## Commands

- `npm run dev` / `npm run build`
- `npm run check`: format check, lint, typecheck and unit tests (run before saying work is done)
- `npm run db:start` / `db:stop` / `db:reset`: local Supabase (needs Docker running)
- `npm run db:test`: pgTAP tests in `supabase/tests/database/`
- New migration: `supabase migration new <name>`; never edit an applied migration

## Non-negotiable rules

- RLS on every `public` table; default deny. A pgTAP guardrail fails if any table lacks RLS.
- Authorisation is enforced in the database and on the server, never only by hiding UI.
- Editors never write money/status columns directly: state changes go through Postgres functions.
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
| Features, roles, MVP exclusions      | `docs/PRODUCT_SPEC.md`                                    |
| Statuses and lifecycles              | `docs/WORKFLOWS.md`                                       |
| Rates, revisions, approvals          | `docs/BUSINESS_RULES.md`                                  |
| Tables, RLS, migrations              | `docs/DATABASE_SCHEMA.md`, `docs/SECURITY_AND_PRIVACY.md` |
| Stack, boundaries, code organisation | `docs/SYSTEM_ARCHITECTURE.md`                             |
| Phase plan                           | `docs/DEVELOPMENT_ROADMAP.md`                             |
| Unresolved decisions                 | `docs/OPEN_QUESTIONS.md`                                  |
| Business context (rarely needed)     | `docs/BUSINESS_PLAN.md`                                   |

`docs/EDITSTATION_MASTER_KNOWLEDGE_BASE.md` is the owner's original source of truth. Consult it
only to resolve ambiguity in the docs above; if they conflict, the knowledge base wins and the
derived doc must be corrected.

## Working conventions

- One bounded feature per task. Inspect existing code first. Don't touch unrelated features.
- Use the installed `supabase` and `supabase-postgres-best-practices` skills for schema/RLS work.
- Every RLS change gets pgTAP tests as admin, editor A, editor B, pending applicant, anon.
- Update `docs/CURRENT_STATUS.md` when the implementation state changes.
