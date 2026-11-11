# System Architecture

Derived from KB §11, plus the Phase 0 architecture proposal approved by the owner on 2026-11-11.

## Stack (KB §11.1; current recommendation, not irreversible)

Next.js + TypeScript · Tailwind + shadcn/ui · Supabase Postgres, Auth, RLS · Vercel · Resend (or
similar) for transactional email · GitHub · Initial assets: restricted Google Drive/Dropbox links ·
Later: Cloudflare R2 or another S3-compatible store. Verify vendor pricing/limits before production.

## Request flow

- **Reads:** Server Components use a Supabase client bound to the user's session, so RLS applies
  to every query.
- **Writes:** Server Actions validate input (zod), then call **Postgres functions** for every state
  transition (accept/counter offer, confirm rate, confirm brief, submit, review, mark paid). Business
  invariants live in the database, not only in TypeScript.
- **Secret/service-role key:** avoided by default. If unavoidable, used only in one `server-only`
  module for a named purpose. Never in client code, never for routine queries.
- **Roles:** `profiles.role` plus `is_admin()` / `is_approved_editor()` helper functions (table
  lookup rather than JWT claims, so revocation is immediate).
- **Audit:** triggers write to append-only `activity_logs`.
- **Email:** sent after a successful transaction; failures are logged, never roll back the action.

## Media (KB §11.2)

No large media in Postgres or through app-server routes. MVP stores links and metadata only.
Note: app-level RLS hides a link, but cannot revoke an "anyone with the link" Drive/Dropbox share.
Prefer per-account sharing and an assign/unassign access checklist (OPEN_QUESTIONS K).

## Code layout (grow into it; don't create empty folders)

```
src/app/            routes: (auth), admin/*, editor/*
src/components/ui/  shadcn primitives
src/features/<module>/  server actions, queries, components, schemas per module
src/lib/            supabase clients, shared utils
supabase/migrations/  SQL migrations (append-only)
supabase/tests/database/  pgTAP
tests/e2e/          Playwright (added when the first UI flow exists)
```

## Modules and dependencies

Auth & roles → Editor applications & vetting → Project access.
Auth & roles → Projects/briefs/deliverables → Assets & references.
Project access + assets → Invitations & negotiation → Interpretation & brief confirmation (gate) →
Submissions → Reviews & revisions → Payments. Notifications, dashboards, analytics and the audit view
sit on top of all of them.

## Testing

Vitest (pure logic) · pgTAP via `supabase test db` (RLS and state-change functions, run as several
user identities) · Playwright (end-to-end, from the first real UI flow).
