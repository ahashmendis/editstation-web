# EDITSTATION

Internal freelance video-editing operations platform for Lenscape Studios. Private and
admin-controlled; not a public marketplace.

## Requirements

- Node.js 24+ and npm
- Docker Desktop (for local Supabase), with at least 10 GB of free disk
- Supabase CLI

## Getting started

```bash
npm install
npm run db:start                # local Supabase: Postgres, Auth, API, Mailpit
cp .env.example .env.local      # then fill in the URL and publishable key from `supabase status`
npm run dev                     # http://localhost:3000
```

Use `http://localhost:3000` (not `127.0.0.1`) so auth cookies and email links match.
Confirmation and password-reset emails arrive in Mailpit: http://127.0.0.1:54324.

## Creating the first admin

Admins never sign up as admins. Register normally, confirm the email, then run as `postgres`
(locally: `docker exec -it supabase_db_editstation psql -U postgres`; hosted: the SQL editor):

```sql
select private.grant_admin_by_email('you@example.com', 'initial admin');
```

On the next sign-in the admin is asked to set up an authenticator app (required).

## Checks

```bash
npm run check        # Prettier, ESLint, TypeScript, Vitest
npm run db:test      # pgTAP database tests (local Supabase must be running)
npm run db:advisors  # Supabase security/performance lints
npm run build
```

## Documentation

Start with [`docs/CURRENT_STATUS.md`](docs/CURRENT_STATUS.md). The owner's source of truth is
[`docs/EDITSTATION_MASTER_KNOWLEDGE_BASE.md`](docs/EDITSTATION_MASTER_KNOWLEDGE_BASE.md).
Contributor/agent instructions: [`CLAUDE.md`](CLAUDE.md).
