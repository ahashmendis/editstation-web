---
paths:
  - "src/app/**"
  - "src/components/**"
  - "src/features/**/components/**"
---

# UI and server-code rules (loads when touching app, components or feature UI)

Next.js 16 differs from older versions: check `node_modules/next/dist/docs/` before using an API
you are unsure of.

- shadcn/ui (base-ui, `base-nova` style) is the component foundation; `src/components/ui/` holds
  the installed components. Add components with `npx shadcn add <name>` and read the generated
  code. Do not add a UI dependency without checking compatibility and saying why.
- Tailwind v4: tokens and theme live in `src/app/globals.css`. Use existing tokens; do not
  hardcode colours or one-off spacing.
- Server code uses `src/lib/supabase/server.ts` and `src/lib/auth/access.ts`. Per-request auth
  reads sit inside `<Suspense>` (`cacheComponents`); never cache access decisions across requests.
- Authorisation is enforced in the database and on the server, never only by hiding UI.
- Mutations are server actions in `src/features/<area>/actions.ts` (admin ones in
  `admin-actions.ts`), validated with Zod schemas in `schemas.ts`. Show only messages from
  `userMessageFromDbError`; never leak raw database errors.
- Forms keep the user's input on validation errors. Every screen needs empty, loading and error
  states and must work at 375px width without horizontal scroll.
- Accessibility: labelled inputs, visible focus, keyboard-operable dialogs, status never conveyed
  by colour alone.
- Never expose secret keys to the browser; only `NEXT_PUBLIC_*` values reach client code.
