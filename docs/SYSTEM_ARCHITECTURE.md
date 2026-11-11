# System Architecture

Derived from KB §11, the Phase 0 architecture proposal approved on 2026-11-11, and the owner
clarification of 2026-11-11 (public website, inquiries, editor self-registration).

## Stack (KB §11.1; current recommendation, not irreversible)

Next.js + TypeScript · Tailwind + shadcn/ui · Supabase Postgres, Auth, RLS · Vercel · Resend (or
similar) for transactional email · GitHub · Initial assets: restricted Google Drive/Dropbox links ·
Later: Cloudflare R2 or another S3-compatible store. Verify vendor pricing/limits before production.

## Surfaces and route groups (proposed)

| Surface          | Routes (indicative)               | Gate (server-side)                           |
| ---------------- | --------------------------------- | -------------------------------------------- |
| Public website   | `/`, `/services`, `/privacy`      | none                                         |
| Client inquiry   | `/inquire`                        | none; captcha/rate limit (OPEN_QUESTIONS O)  |
| Auth             | `/sign-up`, `/sign-in`, `/auth/*` | none                                         |
| Applicant area   | `/apply`                          | signed in                                    |
| Editor dashboard | `/editor/*`                       | signed in **and** `access_status = active`   |
| Admin dashboard  | `/admin/*`                        | signed in **and** admin **and** MFA (`aal2`) |

Gates are enforced three times: `proxy.ts` (Next 16's renamed middleware) only refreshes the session
and redirects for convenience; each protected layout checks access on the server; and **RLS is
the real boundary**, so a page that skips its check still receives no data.

## Authentication flow (proposed)

1. Sign-up: Supabase Auth email + password. Email confirmation required (decision R); production
   auth emails need custom SMTP (e.g. Resend) on a verified sender domain (KB §17.2).
2. A trigger on `auth.users` insert creates `profiles` (and `editor_profiles` with
   `access_status = 'none'`). It ignores `raw_user_meta_data` for anything security-relevant,
   because users can set that metadata themselves.
3. Admins are **never** created through sign-up. Bootstrap: a one-off, documented SQL/CLI step run
   by the owner that inserts a row into `admin_users`. Later admins are granted by an existing
   admin through an audited function (one admin at launch; decision A).
4. Suspension/revocation takes effect on the next query because access helpers read tables, not
   JWT claims. Optionally also sign the user out of all sessions (needs the Auth admin API on the
   server; decide when building suspension).

## Request flow

- **Reads:** Server Components use a Supabase client bound to the user's session, so RLS applies.
- **Writes:** Server Actions validate input (zod), then call **Postgres functions** for every
  state transition: submit application, approve/activate, suspend, convert inquiry, accept/counter
  offer, confirm rate, confirm brief, submit work, review, mark paid.
- **Public inquiry submission:** Server Action → captcha/rate-limit check → `submit_client_inquiry()`
  function executable by `anon`, which inserts with a forced `new` status and returns nothing
  readable. `anon` gets no direct table privileges.
- **Secret/service-role key:** avoided by default. Candidates where it may be unavoidable: signing
  out a suspended user, sending admin invites. Each use is in one `server-only` module, named and
  documented here before it is added.
- **Audit:** triggers write to append-only `activity_logs`, including every admin action on
  applications, access status, admin grants and inquiry conversion.
- **Email:** sent after a successful transaction; failures are logged, never roll back the action.

## Role design (proposed; replaces `profiles.role` from Phase 0)

- `admin_users`: one row per admin. Supports one admin now and more later without a schema change
  (decision A). A future `admin_permissions` column/table can narrow "mark paid".
- `editor_profiles.access_status`: the only thing that grants editor access.
- Helper functions: `is_admin()`, `is_active_editor()`, `current_editor_id()`.
- There is no stored "applicant" role: any signed-in user who is neither admin nor active editor
  is an applicant and can see only their own account and application.

## Media (KB §11.2)

No large media in Postgres or through app-server routes. MVP stores links and metadata only.
App-level RLS hides a link, but cannot revoke an "anyone with the link" Drive/Dropbox share. See
OPEN_QUESTIONS K and the proposed `asset_access_grants` table for tracking manual sharing.
Public inquiry form: reference **links** only, no file uploads, in the MVP (OPEN_QUESTIONS U).

## Code layout (grow into it; don't create empty folders)

```
src/app/(public)/   website, inquiry form
src/app/(auth)/     sign-up, sign-in, auth callbacks
src/app/apply/      applicant area
src/app/editor/     active editors
src/app/admin/      admins
src/proxy.ts        session refresh + convenience redirects only
src/components/ui/  shadcn primitives
src/features/<module>/  server actions, queries, components, schemas per module
src/lib/            supabase clients, shared utils
supabase/migrations/  SQL migrations (append-only)
supabase/tests/database/  pgTAP
tests/e2e/          Playwright (added when the first UI flow exists)
```

## Modules and dependencies

```
Auth, accounts & access gating
 ├─► Editor applications & vetting ──► Project access
 ├─► Public website & client inquiries ──► (inquiry → project conversion)
 └─► Projects / briefs / deliverables ──► Assets & references
          Project access + assets ──► Invitations & negotiation
              ──► Interpretation & brief confirmation (gate)
              ──► Submissions ──► Reviews & revisions ──► Payments
Notifications, dashboards, analytics and the audit view sit on top of all of them.
```

The public website and inquiry module only depends on auth for the admin side, so it can be
built in parallel with editor applications.

## Testing

Vitest (pure logic) · pgTAP via `supabase test db` (RLS and state-change functions, run as
anonymous, pending applicant, approved editor A, approved editor B, admin) · Playwright
(end-to-end, from the first real UI flow).
