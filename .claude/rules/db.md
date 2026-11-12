---
paths:
  - "supabase/**"
---

# Database rules (loads when touching `supabase/`)

Full rules live in `CLAUDE.md`, `docs/DATABASE_SCHEMA.md` and `docs/SECURITY_AND_PRIVACY.md`. Use
the `supabase` and `supabase-postgres-best-practices` skills for schema/RLS work.

- Applied (committed) migrations are never edited; a hook blocks it. New change =
  `npx supabase migration new <name>`, then `npm run db:reset` and `npm run db:test`.
- Every `public` table: RLS on, default deny, explicit grants. Helpers and anything not meant for
  the API go in `private`. Every `public` function must be executable by both `anon` and
  `authenticated` and authorise inside its body (a permission error crashes this Postgres image).
- Admin checks use `private.is_admin()` (needs MFA `aal2`). Editor access is
  `editor_profiles.access_status = 'active'`, changed only by admin functions. Never trust
  role/status from sign-up metadata.
- Editors never write money/status columns directly: state changes go through functions that raise
  `ES401`/`ES403`/`ES409`/`ES422` (never `42501`) with user-safe messages.
- Editor-visible tables must not hold client data or client pricing. Large media is never stored in
  Postgres (links and metadata only).
- Every RLS change needs pgTAP tests (`supabase/tests/database/`) as admin, editor A, editor B,
  pending applicant and anon.
- Local database only. Never `link`, `db push`, or use a non-local `--db-url` without owner
  approval. After schema changes run `npm run db:types`, then `npm run db:advisors`.
