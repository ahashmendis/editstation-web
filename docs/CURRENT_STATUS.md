# Current Status

**Phase:** 0 (repository foundation) verified; pending first commit.
**Last updated:** 2026-11-11

## Implemented

- Git repository (`main`), knowledge base moved to `docs/EDITSTATION_MASTER_KNOWLEDGE_BASE.md`.
- Next.js 16.4 app (App Router, `src/`, TypeScript strict, Tailwind v4, shadcn/ui on base-ui).
- ESLint (Next config + Prettier compat), Prettier (+ Tailwind class sorting), Vitest (node env).
- Local Supabase config (`supabase/config.toml`, Postgres 17), empty migrations, empty seed.
- pgTAP guardrail test: every `public` table must have RLS enabled.
- `.env.example` (no secrets committed), CI workflow (`.github/workflows/ci.yml`).
- Split documentation in `docs/` and a concise `CLAUDE.md`.

## Not yet done / not verified

- Full local Supabase stack (`npm run db:start`: Auth, Studio, API) not yet started; only Postgres
  (`supabase db start`) has run. The full stack needs several GB more of Docker images; check free
  disk space first (a full disk crashed Docker during setup).
- CI workflow not yet run on GitHub.
- No GitHub remote, no Vercel project, no hosted Supabase project yet (owner to create/connect).
- No business features, tables, auth or RLS policies yet (Phase 1+).

## Known issues

- `npm audit`: 7 moderate advisories in dev-only lint tooling (`@typescript-eslint/*` via
  `eslint-config-next`). Not shipped to the browser. Revisit when `eslint-config-next` updates;
  do not `npm audit fix --force`.
- `@vitejs/plugin-react` currently conflicts with shadcn CLI's Babel peer deps, so component tests
  (jsdom/Testing Library) are deferred; Playwright will cover UI flows.

## Decisions made

- npm as package manager; Node >= 24.
- `cn` helper comes from the `cn` package (shadcn default for this version).
- `npm run typecheck` runs `next typegen` first: Next 16 route types (`LayoutProps`, etc.) are
  generated, so plain `tsc` fails on a clean checkout.
- `@types/node` pinned to ^24 to match the Node 24 runtime (Vitest 5 peer requirement).

## Verified (2026-11-11)

- `npm run check` (Prettier, ESLint, typecheck, Vitest) and `npm run build` pass locally.
- `supabase db start` + `npm run db:test`: pgTAP guardrail passes. Negative check done: adding a
  `public` table without RLS makes it fail; dropping the table makes it pass again.

## Next task

Phase 1: auth, `profiles` + role model, RLS helper functions, pgTAP identity harness.
Blocked on owner answers to OPEN_QUESTIONS A (admins) and D (applicant sign-up flow).
