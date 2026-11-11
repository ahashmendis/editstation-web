# EDITSTATION

Internal freelance video-editing operations platform for Lenscape Studios. Private and
admin-controlled; not a public marketplace.

## Requirements

- Node.js 24+ and npm
- Docker Desktop (for local Supabase)
- Supabase CLI

## Getting started

```bash
npm install
cp .env.example .env.local      # fill in values printed by the next command
npm run db:start                # starts local Supabase in Docker
npm run dev                     # http://localhost:3000
```

## Checks

```bash
npm run check     # Prettier, ESLint, TypeScript, Vitest
npm run db:test   # pgTAP database tests (local Supabase must be running)
npm run build
```

## Documentation

Start with [`docs/CURRENT_STATUS.md`](docs/CURRENT_STATUS.md). The owner's source of truth is
[`docs/EDITSTATION_MASTER_KNOWLEDGE_BASE.md`](docs/EDITSTATION_MASTER_KNOWLEDGE_BASE.md).
Contributor/agent instructions: [`CLAUDE.md`](CLAUDE.md).
