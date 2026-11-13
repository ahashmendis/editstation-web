# Design system

Status: **owner-approved 2026-11-12 (recommended answers, section 9). Partly applied:** colour
tokens (dark default, light via system setting), Geist applied, text wordmark in the public header
and auth pages, token contrast test (`src/lib/design-tokens.test.ts`). **Not yet applied:** shared
admin/editor shell (sidebar), unified status badges, empty/loading/error states, React Bits
(skipped for now). Brand source: `EditStation Brand Identity Board.png` and
`Editstation Logo with Purple Accents.png` (repo root). `.claude/rules/ui.md` points here.

## 1. What the brand gives us

Sampled from the logo files (values are measured, not guessed):

- **Brand purple:** `#9643E5` (`oklch(0.573 0.232 303)`), used for "STATION", the pulse marks and
  the app icon gradient.
- **Background:** near-black `#050509`; text white. Wordmark is two-tone: **EDIT** in white (or
  black on light), **STATION** in purple.
- **Letterforms:** heavy, wide, geometric sans, all caps. Icon: a figure at a laptop with three
  "spark" strokes. Secondary marks: stacked lockup, bracketed wordmark, "ES" monogram.
- The brand board shows both a dark (primary) and a light version, so both themes are on-brand.

Contrast (WCAG, computed): white on purple **4.96:1** (passes AA for text); purple on near-black
**4.10:1** (fails AA for small text, fine for large text and graphics). So the brand purple is used
for fills and large elements, and a lighter tint is used for small purple text on dark.

## 2. Principles

1. **One identity, three areas.** Public site, admin and editor areas share tokens, type and
   components. They differ in density, not in style: public is spacious and branded; admin and
   editor are compact and calm.
2. **Dark-first, light supported.** The brand lives on black. Dark is the default theme everywhere;
   light is defined from the same tokens for long reading and printing. No theme toggle in v1
   (follows the system setting) to keep scope small.
3. **Purple is rare.** One purple primary action per screen; purple marks the brand, focus and the
   current location. Everything else is neutral, so status colours stay readable.
4. **Status is never colour alone.** Every status shows text (and an icon where space allows).
5. **shadcn/ui stays the foundation.** Restyle through tokens, not by forking components.

## 3. Colour tokens

Neutrals carry a slight cool-violet tint (hue 285) to sit with the purple. Mapped onto the existing
shadcn variable names so every installed component picks them up.

| Token                  | Dark (default)                   | Light                            | Use                                     |
| ---------------------- | -------------------------------- | -------------------------------- | --------------------------------------- |
| `--background`         | `#050509` oklch(0.118 0.011 285) | `#fafafc`                        | Page                                    |
| `--card` / `popover`   | `#0d0d14` oklch(0.163 0.015 285) | `#ffffff`                        | Surfaces, dialogs                       |
| `--border`             | `#23232e` oklch(0.261 0.020 285) | `#e4e4ec`                        | Lines, table rules                      |
| `--foreground`         | `#fafafa`                        | `#0b0b12`                        | Body text (20.4:1 on background)        |
| `--muted-foreground`   | `#a0a0b0` oklch(0.711 0.023 286) | `#5f5f70`                        | Secondary text (7.9:1 on bg)            |
| `--primary`            | `#9643e5` oklch(0.573 0.232 303) | `#7a2fcc` oklch(0.500 0.223 300) | Primary buttons, brand fills            |
| `--primary-foreground` | `#ffffff` (4.96:1 on purple)     | `#ffffff` (6.76:1)               | Text on primary                         |
| `--brand-text`         | `#b27ef0` oklch(0.692 0.168 303) | `#7a2fcc`                        | Small purple text/links (6.9:1 on dark) |
| `--ring`               | `#b27ef0`                        | `#7a2fcc`                        | Focus outline (always visible)          |

Status palette (to be tuned and contrast-checked when applied; each also needs a text label):
success (green) and warning (amber) are implemented as `--success` and `--warning`; danger reuses
`--destructive` (retuned); info is not implemented yet (it would use `--brand-text`); neutral is
`--muted`. Sidebar tokens inherit the card/background values with the purple
used only for the active item.

## 4. Typography

- **Keep Geist** (already loaded via `next/font`): no new dependency or font download. Geist Mono
  for IDs and amounts.
- Headings: weight 700, tight tracking, tight line height, sentence case. The all-caps wide wordmark
  is a logo only, never body or heading style.
- Scale (rem): 0.75 / 0.875 / 1 / 1.125 / 1.25 / 1.5 / 1.875 / 2.5 (hero only, public site).
  Body 1rem on public pages, 0.875rem in dense admin tables.
- Option for later (needs your approval, adds a font): a heavier geometric display face for the
  hero only, closer to the logo letterforms.

## 5. Spacing, radius, layout

- 4px base grid. Page gutter 16px on phones, 24px from `md`. Public content max width 64rem
  (`max-w-5xl`, as now); admin/editor content up to 80rem with a fixed sidebar.
- Radius: keep `--radius: 0.625rem` for cards and inputs; buttons the same; pills for status badges.
- Elevation: borders and surface steps, not shadows (shadows disappear on black).

## 6. Components and patterns

- **Logo/header:** text wordmark in HTML (EDIT in foreground colour, STATION in purple) for now. The
  supplied PNGs have a baked-in black background, so the icon needs a transparent SVG/PNG before it
  can be used on other surfaces; the wordmark alone works on both themes.
- **Public header/footer:** as today (`site-chrome.tsx`), restyled; two clear entry points (send a
  project, join as an editor), "Sign in" quieter.
- **Admin and editor shell:** fixed left sidebar on `lg+`, collapses to a top bar with a menu sheet
  on small screens. Active item: purple marker plus stronger text. Same shell component for both
  areas, different navigation items.
- **Buttons:** primary (purple fill), secondary (surface), outline, ghost, destructive. One primary
  per view. Min height 40px, 44px touch target on phones. Loading state keeps width and disables.
- **Forms:** labels above fields, helper text below, errors in text plus icon, input kept on error
  (existing rule). Required fields marked in the label, not by colour.
- **Tables:** compact rows, sticky header, hairline separators, status badge column, row hover. On
  phones, tables become stacked cards. Sorting/filtering only where the data needs it.
- **Dialogs:** use for confirmations and short forms only; destructive confirmations name the
  action and the consequence (matches the existing two-step approve/withdraw).
- **Status badges:** pill with dot + label, from one mapping file per feature so colours stay
  consistent (applications, inquiries, later projects and payments).
- **Empty, loading, error states:** each list/detail screen gets all three: empty (one sentence and
  the next action), skeleton loading (no layout shift), error (user-safe message from
  `userMessageFromDbError`, retry action).
- **Motion:** 150-200ms ease for hover/focus/dialogs; respect `prefers-reduced-motion`.

## 7. React Bits (optional, public site only)

At most two or three selected effects on the home page hero (for example a subtle text or background
effect). Not used in admin or editor areas. Each one is copied in through the shadcn registry, read
before committing, licence checked (reported as MIT with Commons Clause, to be confirmed), and any
animation dependency it needs is justified first. Must be disabled under reduced motion.

## 8. What changes in code (status)

1. **Done.** `src/app/globals.css`: replace neutral shadcn tokens with the table above; add `--brand-text`,
   status tokens; dark as default (`color-scheme` follows system for light).
2. **Done.** `src/components/site-chrome.tsx` and the auth pages: wordmark and header restyle.
3. **Done (shell and status pills).** Shared `AppShell` (sidebar on `lg+`, top bar with a menu sheet below) used by `/admin` and `/editor` layouts; the old horizontal admin nav was removed. Status pills are unified in `src/components/status-pill.tsx`.
4. **Done (first pass).** `EmptyState` (title, what to do next) on the admin lists and activity feed, a skeleton `Loading` (respects reduced motion), `app/error.tsx` (shows only a reference, never the error message) and `app/not-found.tsx`. Remaining screens adopt `EmptyState` as they are touched.
5. **Done.** Playwright smoke tests and the 375px check keep passing; a contrast check for the
   token pairs (`src/lib/design-tokens.test.ts`) keeps the table above from drifting.

## 9. Owner decisions (2026-11-12)

1. Dark-first everywhere: **yes**.
2. Keep Geist, no display font: **yes**. (Geist was loaded but never applied: `--font-sans`
   pointed at itself, so the app rendered in Times New Roman. Fixed.)
3. Transparent logo files: **still needed** from the owner; text wordmark until then.
4. React Bits: **skipped for now** (revisit with the public hero).
5. Light theme: **defined now** (follows the system setting; no toggle).
