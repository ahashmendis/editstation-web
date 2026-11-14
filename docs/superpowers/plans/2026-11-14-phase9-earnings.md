# Phase 9 Payments and Earnings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `payments` (created automatically at assignment confirmation for the agreed amount), the decision-I lifecycle (`not_due → pending_approval → approved → processing → paid`, plus `on_hold` with a reason), audited reversal rows, admin-only status functions, and the earnings screens `/editor/earnings` and `/admin/earnings` (+ `/admin/earnings/[id]`).

**Architecture:** Same model as Phases 4–7. `payments` and `payment_notes` have `select`-only grants and one combined policy each; every write is a `public.admin_*` security-definer function or a `private` trigger. Creation and ended-assignment holds are `AFTER UPDATE OF status` triggers on `assignments`, so no Phase 6/7 function is replaced. Guards on `payments` hold for the table owner. Summaries are pure TypeScript over rows the caller can already read. Three migrations, then UI.

**Tech Stack:** Postgres (Supabase local, CLI pinned 2.122.1), pgTAP, plpgsql; Next.js 16 App Router (`cacheComponents`; per-request reads inside `<Suspense>`), zod, Vitest, Playwright.

**Spec:** `docs/superpowers/specs/2026-11-14-phase9-earnings-design.md` (draft under the owner's standing instruction of 2026-11-14). Section numbers (§) refer to it. **Depends on** the Phases 5–6 and Phase 7 migrations (`20261114061439` … `20261114143056`) and tests 050–066 being green. Before UI tasks, read the relevant guides in `node_modules/next/dist/docs/` (AGENTS.md).

## Global Constraints

- RLS on both new tables; `revoke all ... from anon, authenticated`; only `grant select ... to authenticated`; policies per spec §6. No insert/update/delete grant or policy.
- Every `public.admin_*` / `public.editor_*` function: `language plpgsql security definer set search_path = ''`; first statement `private.require_admin()` or `private.require_active_editor()`; then `revoke all on function <sig> from public, anon, authenticated;` and `grant execute on function <sig> to anon, authenticated;`. Every `private.*` function and trigger function: revoked from `public, anon, authenticated`, no grant.
- Errors only `ES401`/`ES403` (helpers), `ES409` (state), `ES422` (input); never `42501`. Wrap `check_violation` into `ES422` and `unique_violation` into `ES409` where a function can hit them.
- Lock order: payment functions lock the target `payments` row `for update` (reversal: the original row) and touch nothing else that is locked by assignment functions. The assignment triggers run under `lock_assignment`'s project → assignment locks and lock payments last.
- Money `numeric(12,2)` + `char(3)` regex check. `activity_logs.details` hold ids and enum names only: never amounts, references, reasons, notes or dates.
- New migrations via `npx supabase migration new <name>` (timestamps after `20261114143056`); never edit a committed migration. Local database only.
- After each DB task: `npm run db:reset` then `npm run db:test`; all existing tests stay green. After each UI task: `npm run check`.
- Do not decide E, G, KB9, F or A2 (spec §12/§13). No commit steps: commits are made by the main session with owner approval.

## Review Focus

1. Confirmation creates exactly one `not_due` row with `amount = agreed_amount`, `currency = agreed_currency`, `created_by` = confirming admin; a seeded `insert ... status 'confirmed'` creates none. Task 2.
2. Reassign and cancel (`admin_reassign`, `admin_set_project_status(..,'cancelled')`, `admin_revoke_project_access` path) from `confirmed` and `in_progress`: unpaid rows → `on_hold` with the fixed reason and correct `held_from_status`; a row already `on_hold` keeps its reason; a `paid` row and its reversal untouched. Task 2.
3. Every one of the 36 `(from, to)` status pairs as table owner: only the spec §7 pairs succeed; `on_hold → X` only when `X = held_from_status`. Task 1.
4. Paid row: any column change (status, reference, due date, transfer date) `ES409`; clearing only `approved_by`/`marked_paid_by`/`created_by` succeeds; clearing one with another column `ES409`; delete `ES409` for every status. Task 1.
5. `p_status` `null`, `'PAID'`, `'paid'`, `'not_due'`, `'bogus'`; `on_hold` with null / whitespace / 501-char reason (all `ES422`, except `paid` → `ES422` "Use mark as paid."). Task 3.
6. Mark paid: from `not_due`, `pending_approval`, `on_hold`, `paid` (`ES409`); reference null / blank / 121 chars; transfer date null, tomorrow (Asia/Colombo), before `confirmed_at` (`ES422`). Task 3.
7. Reverse: a non-paid row, a reversal row, an already-reversed row (`ES409`); blank reason (`ES422`); `p_reopen = true` while an unpaid row exists for the assignment (`ES409`, nothing inserted); `p_reopen = null` (`ES422`). Task 3.
8. Unknown payment id → identical `ES422` "Payment not found." for every admin function. Task 3.
9. Editor A calling `editor_list_payments` sees only own rows and only `project_id`/`project_title` from projects, including after reassignment (stage `none`); B never sees A's; suspended A `ES403`. Task 3.
10. Direct `insert`/`update`/`delete` on `payments` and `payment_notes` as admin aal2 and as A → `42501`. Task 1.
11. Audit rows for every action contain only keys `payment_id, assignment_id, from, to` (`from`/`to` null where meaningless) and no amount, reference, reason, note or date text. Task 4.

## Calls

Plan choices beyond the spec; the owner may override.

1. **Three migrations:** schema+guards+RLS, assignment triggers, functions. Enum values are used only after their creating migration commits, so the enums sit in the schema migration with no `add value`.
2. **Hold-chk expressed explicitly:** `check ((status = 'on_hold') = (held_from_status is not null) and (status = 'on_hold') = (on_hold_reason is not null) and (held_from_status is null or held_from_status not in ('on_hold','paid')))`.
3. **Fixed hold reason** (spec §4.3) is a constant in `private.hold_payments_on_close`; the trigger's audit `to` = `on_hold`.
4. **`created_by` from triggers** = `assignments.confirmed_by` (create) and `null` actor in the audit row when `auth.uid()` is null (seeded tests), same as `private.audit_assignments`.
5. **Release** clears `on_hold_reason` and `held_from_status`; the reason survives only in the activity log as the `payment.on_hold` event (no text), so the UI shows the current reason only. Admin notes can record context.
6. **Transfer-date bound** uses `(now() at time zone 'Asia/Colombo')::date`; the lower bound is `(confirmed_at at time zone 'Asia/Colombo')::date` of the assignment.
7. **Reversal row** gets `marked_paid_by/at` = admin/now, `approved_*` null, `transaction_reference` null, `transfer_date` null (the `paid_chk` reference/date requirement applies to `assignment` rows only).
8. **Admin reads in the UI** use RLS selects with explicit column lists (no `select *`); editor UI uses only `editor_list_payments()`.
9. **Nav icon** `earnings` → lucide `Wallet`.
10. **Money formatting** reuses `formatMoney` from `src/features/access/constants.ts` (moved to `src/lib/money.ts` only if a second feature needs it here; keep the import otherwise).

## File Structure

| File                                                                                                          | Responsibility                                                                                      |
| ------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `supabase/migrations/<ts>_phase9_payments_schema.sql`                                                         | enums, `payments`, `payment_notes`, constraints, indexes, transition fn, guards, audit trigger, RLS |
| `supabase/migrations/<ts>_phase9_payment_triggers.sql`                                                        | `create_assignment_payment`, `hold_payments_on_close` on `assignments`                              |
| `supabase/migrations/<ts>_phase9_payment_functions.sql`                                                       | six `admin_*` functions, `editor_list_payments`                                                     |
| `supabase/tests/database/070`–`076_phase9_*.test.sql`                                                         | pgTAP, see each task                                                                                |
| `src/features/payments/constants.ts` (+ `.test.ts`)                                                           | statuses, labels, tones, allowed actions per status, hold-reason hint                               |
| `src/features/payments/schemas.ts` (+ `.test.ts`)                                                             | zod schemas for the six admin forms and filter params                                               |
| `src/features/payments/summary.ts` (+ `.test.ts`)                                                             | pure summary functions (spec §9)                                                                    |
| `src/features/payments/queries.ts`                                                                            | `server-only` reads                                                                                 |
| `src/features/payments/admin-actions.ts`                                                                      | `"use server"` actions                                                                              |
| `src/features/payments/components/*.tsx`                                                                      | pill, cards, lists, tables, filters, action forms, notes                                            |
| `src/app/editor/earnings/page.tsx`, `src/app/admin/earnings/page.tsx`, `src/app/admin/earnings/[id]/page.tsx` | routes                                                                                              |
| `src/app/admin/layout.tsx`, `src/app/editor/layout.tsx`, `src/components/app-shell/nav-links.tsx`             | nav entries + icon                                                                                  |
| `src/lib/activity-labels.ts` (+ test), `tests/e2e/smoke.spec.ts`                                              | labels for `payment.*`; signed-out gates                                                            |
| `docs/*`, `src/lib/supabase/database.types.ts`                                                                | Task 12                                                                                             |

Tests reuse the helpers of `054_phase6_offers.test.sql` (`pg_temp.as_user(uid, 'aal2')`, `pg_temp.as_anon()`, `private.grant_admin_by_email`, editors activated as postgres, temp id tables granted to `authenticated`). Identities: admin (aal2), admin aal1, editor A, editor B, suspended S, applicant, anon. UUID prefix `70000000-` for 070, `71000000-` for 071, and so on. Fixture "confirmed assignment" = project opened via `admin_set_project_status`, `admin_make_offer`, `editor_respond_offer(.., 'accept')`, `admin_confirm_assignment`; schema-only tests seed rows as postgres.

---

### Task 1: Payments schema, guards and RLS

**Files:**

- Create: `supabase/migrations/<ts>_phase9_payments_schema.sql`
- Test: `supabase/tests/database/070_phase9_schema.test.sql`, `supabase/tests/database/071_phase9_visibility.test.sql`

**Interfaces:**

- Produces enums `public.payment_status` (`not_due`, `pending_approval`, `approved`, `processing`, `paid`, `on_hold`), `public.payment_kind` (`assignment`, `reversal`).
- Produces `public.payments` and `public.payment_notes` exactly as spec §5 (constraint names `payments_amount_chk`, `payments_hold_chk` (Call 2), `payments_approved_chk`, `payments_paid_chk`, `payments_reversal_chk`; indexes `payments_open_key`, `payments_reverses_key`, `payments_editor_idx (editor_id, created_at desc)`, `payments_project_idx`, `payments_status_idx`, one per actor FK; `payment_notes_payment_idx (payment_id, created_at desc)`, `payment_notes_author_idx`). `payments_set_updated_at` via `private.set_updated_at()`.
- Produces `private.payment_transition_allowed(p_from public.payment_status, p_to public.payment_status) returns boolean` (sql immutable; spec §7 without the `on_hold` return, which the guard checks).
- Produces triggers: `payments_check_row` BEFORE INSERT → `private.check_payment_row()`; `payments_guard` BEFORE UPDATE OR DELETE → `private.guard_payments()` (spec §5; `on_hold → held_from_status` allowed here; paid-row actor-clear exception); `payment_notes_append_only` BEFORE UPDATE OR DELETE → `private.guard_append_only('author_id')`; `payments_audit` AFTER INSERT OR UPDATE OF status, due_date → `private.audit_payments()` (`payment.created` on insert of `assignment` rows, `payment.reversed` on insert of `reversal` rows, `payment.<new status>` or `payment.hold_released` on status change, `payment.due_date_set` when only `due_date` changes; details per Review Focus 11).
- Produces policies `payments_select`, `payment_notes_select` (spec §6).

- [ ] **Step 1: Write the failing tests.**
  - `070_phase9_schema.test.sql`: enum labels exact; columns, constraint and index names exist. As postgres on a seeded confirmed assignment (agreed 10000 LKR): insert `assignment` row with amount 9000 or currency `USD` → `ES409`; with `project_id`/`editor_id` of another assignment → `ES409`; on an assignment without `confirmed_at` → `ES409`; valid insert succeeds; second unpaid `assignment` row → `23505`. `amount <= 0` for `assignment` and `>= 0` for `reversal` → `23514`. `on_hold` without reason or without `held_from_status`, `held_from_status = 'paid'` → `23514`; `approved` without `approved_at` → `23514`; `paid` assignment row without reference or transfer date → `23514`. Reversal: of a non-paid row, with a different amount or currency → `ES409`; reversal with status other than `paid` → `23514`; second reversal of the same row → `23505`. Review Focus 3 (36-pair matrix via a `pg_temp.try_status(from, to)` helper that seeds a row in `from` with the columns its constraints need and returns the SQLSTATE or `ok`; expected `ok` set listed explicitly; `on_hold → X` tried with `held_from_status = X` and with another value). Review Focus 4. Immutable columns (`amount`, `currency`, `assignment_id`, `kind`) on an unpaid row → `ES409`. `payment_notes`: update and delete → `ES409`; clearing only `author_id` succeeds. Deleting a referenced assignment → `23503` (restrict).
  - `071_phase9_visibility.test.sql`: seed rows for A (two payments, one paid) and B (one). Per identity (spec §6): row counts on `payments` and `payment_notes` (admin aal2 all; A own 2 / notes 0; B own 1; S, applicant, admin aal1 0; anon `42501`); Review Focus 10.
- [ ] **Step 2: Run to verify failure** (`npm run db:test`).
- [ ] **Step 3: Implement** the migration.
- [ ] **Step 4: Run `npm run db:reset && npm run db:test`; expect pass.**

---

### Task 2: Assignment triggers (create on confirmation, hold on end)

**Files:**

- Create: `supabase/migrations/<ts>_phase9_payment_triggers.sql`
- Test: `supabase/tests/database/072_phase9_lifecycle_triggers.test.sql`

**Interfaces:**

- Consumes: `public.assignments` (Phase 6/7), Task 1 tables.
- Produces:
  - `private.create_assignment_payment()` + trigger `assignments_create_payment` AFTER UPDATE OF status ON `public.assignments` FOR EACH ROW WHEN (`old.status = 'accepted' and new.status = 'confirmed'`): insert `kind 'assignment'`, `status 'not_due'`, `amount = new.agreed_amount`, `currency = new.agreed_currency`, `project_id`, `editor_id`, `created_by = new.confirmed_by` (Call 4).
  - `private.hold_payments_on_close()` + trigger `assignments_hold_payments` AFTER UPDATE OF status WHEN (`old.status in ('confirmed','in_progress') and new.status in ('reassigned','withdrawn')`): for each row of the assignment with status in (`not_due`, `pending_approval`, `approved`, `processing`), `order by id for update`, set `status = 'on_hold'`, `held_from_status = old status`, `on_hold_reason` = spec §4.3 text (Call 3).

- [ ] **Step 1: Write the failing test** `072_phase9_lifecycle_triggers.test.sql`. Driven through Phase 6 functions: after `admin_confirm_assignment`, exactly one row for the assignment with the Review Focus 1 values, visible to A via RLS; the other offers that became `not_selected` have no rows; seeded `confirmed` insert as postgres creates none. Review Focus 2: (a) `admin_reassign` from `confirmed` with a `not_due` row → `on_hold`, `held_from_status = 'not_due'`, reason exact; (b) from `in_progress` (via `editor_start_work` after confirmation fixtures from 063) with an `approved` row → `held_from_status = 'approved'`; (c) cancel via `admin_set_project_status(.., 'cancelled')` → same; (d) a row already `on_hold` with an admin reason keeps that reason; (e) a `paid` row plus its reversal unchanged; (f) `admin_withdraw_offer` on an `accepted` assignment creates/changes nothing. Audit: one `payment.created` row per confirmation, one `payment.on_hold` per held row.
- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement** both trigger functions and triggers with revoke lines.
- [ ] **Step 4: Run `npm run db:reset && npm run db:test`; expect pass**, including 054–057 and 060–066 (no Phase 6/7 behaviour changes).

---

### Task 3: Admin payment functions and the editor list

**Files:**

- Create: `supabase/migrations/<ts>_phase9_payment_functions.sql`
- Test: `supabase/tests/database/073_phase9_admin_status.test.sql`, `supabase/tests/database/074_phase9_paid_and_reversal.test.sql`, `supabase/tests/database/075_phase9_editor_list.test.sql`

**Interfaces:**

- Consumes: `private.require_admin()`, `private.require_active_editor()`, `private.clean_text(text, int, text)`, Task 1/2.
- Produces (signatures exact; behaviour spec §8):
  - `public.admin_set_payment_status(p_payment_id uuid, p_status text, p_reason text default null) returns void`
  - `public.admin_release_payment_hold(p_payment_id uuid) returns void`
  - `public.admin_mark_payment_paid(p_payment_id uuid, p_transaction_reference text, p_transfer_date date) returns void`
  - `public.admin_set_payment_due_date(p_payment_id uuid, p_due_date date) returns void`
  - `public.admin_reverse_payment(p_payment_id uuid, p_reason text, p_reopen boolean) returns uuid`
  - `public.admin_add_payment_note(p_payment_id uuid, p_note text) returns uuid`
  - `public.editor_list_payments() returns table (id uuid, project_id uuid, project_title text, kind public.payment_kind, amount numeric, currency char(3), status public.payment_status, on_hold_reason text, reversal_reason text, reverses_payment_id uuid, due_date date, transfer_date date, transaction_reference text, approved_at timestamptz, marked_paid_at timestamptz, created_at timestamptz)` — `stable`; `where p.editor_id = v_uid order by p.created_at desc, p.id`.
  - Messages: unknown id `ES422` "Payment not found."; wrong state `ES409` "This payment cannot move from <from> to <to>." (underscores → spaces); paid row `ES409` "This payment has been paid and cannot be changed."; `on_hold` without reason `ES422` "Please give a reason for the hold."; `p_status = 'paid'` `ES422` "Use mark as paid."

- [ ] **Step 1: Write the failing tests.**
  - `073_phase9_admin_status.test.sql`: happy path `not_due → pending_approval → approved` (`approved_by/at` set) `→ processing`; hold from each unpaid state and release back to it (reason cleared); Review Focus 5, 8; due date set, changed, cleared on an unpaid row, refused on a paid row (`ES409`); every function: anon `ES401`, A/B/S/applicant/admin aal1 `ES403`.
  - `074_phase9_paid_and_reversal.test.sql`: mark paid from `approved` and from `processing` (`marked_paid_by/at`, reference trimmed, transfer date stored); Review Focus 6, 7; reverse without re-open → reversal row (negative, `paid`, linked, reason, `marked_paid_by` = admin), paid total for the assignment nets to 0; reverse with re-open → also a new `pending_approval` row for the agreed amount; notes: append, blank `ES422`, 4001 chars `ES422`, unknown payment `ES422`; A cannot read notes.
  - `075_phase9_editor_list.test.sql`: Review Focus 9; columns returned exactly the declared set (`results_eq` on `pg_get_function_result`); B with rows of A seeded sees only own; admin aal2 `ES403`; anon `ES401`; after `admin_reassign`, A still lists the held payment with its project title while `select title from projects where id = ...` as A returns 0 rows.
- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement** the seven functions with revoke/grant lines.
- [ ] **Step 4: Run `npm run db:reset && npm run db:test`; expect pass.**

---

### Task 4: Function security, hygiene and audit guardrails

**Files:**

- Test: `supabase/tests/database/076_phase9_function_security.test.sql`

- [ ] **Step 1: Write the test.** The seven public functions exist and are executable by `anon` and `authenticated`; `prosrc` of `admin_*` contains `private.require_admin()` and of `editor_list_payments` `private.require_active_editor()`. New private functions (`payment_transition_allowed`, `check_payment_row`, `guard_payments`, `audit_payments`, `create_assignment_payment`, `hold_payments_on_close`): security definer, `search_path=""`, no API grantee. Hygiene: no column on `payments` matching `client|email|phone|company|contact|price|margin|note`; `editor_list_payments` result has no such column; all policies on both tables `cmd = 'SELECT'`; triggers present by name. Review Focus 11 over one full flow (confirm, pending, approve, process, hold, release, due date, mark paid with reference `TESTREF-77`, reverse with re-open, note, reassign hold): every `payment.%`/`payment_note.%` row has exactly the allowed keys and `details::text` contains neither `10000`, `TESTREF-77`, the reasons, the note text nor the dates used. Confirm `046_phase4_function_security` still passes (catalogue rules cover the new functions automatically).
- [ ] **Step 2: Run `npm run db:test`;** fix any failure in its own uncommitted migration.

---

### Task 5: Types and UI constants

**Files:**

- Modify: `src/lib/supabase/database.types.ts` (generated: `npm run db:types`)
- Create: `src/features/payments/constants.ts`, `src/features/payments/constants.test.ts`
- Modify: `src/lib/activity-labels.ts`, `src/lib/activity-labels.test.ts`

**Interfaces:**

- `PAYMENT_STATUSES` (ordered as the enum), `type PaymentStatus`, `type PaymentKind`.
- `PAYMENT_STATUS_LABEL` (Not due, Pending approval, Approved, Processing, Paid, On hold) and `PAYMENT_STATUS_TONE` (neutral, warning, info, info, success, danger) per spec §11.
- `UNPAID_STATUSES`, `COMMITTED_STATUSES` (= four unpaid), `AWAITING_TRANSFER_STATUSES` (`approved`, `processing`).
- `nextAdminActions(status, kind, hasReversal): AdminPaymentAction[]` where `AdminPaymentAction` = `"to_pending_approval" | "approve" | "to_processing" | "mark_paid" | "hold" | "release" | "set_due_date" | "reverse"` (mirrors spec §7/§8; UI hint only, the database decides).
- `HOLD_REASON_HINT` = "The editor can see this reason."; `REVERSAL_LABEL` = "Correction".
- Activity labels: `payment.created` "Payment record created", `payment.pending_approval` "Sent for approval", `payment.approved` "Payment approved", `payment.processing` "Transfer in progress", `payment.paid` "Marked paid", `payment.on_hold` "Put on hold", `payment.hold_released` "Hold released", `payment.due_date_set` "Due date set", `payment.reversed` "Payment reversed", `payment_note.added` "Note added".

- [ ] **Step 1: Write failing tests:** every status has a label and tone; `nextAdminActions` per status (paid assignment → `["reverse"]`, paid with reversal → `[]`, reversal → `[]`, on_hold → `release`, `set_due_date`; etc.); every `payment.*` code labelled.
- [ ] **Step 2: Run** `npx vitest run src/features/payments src/lib/activity-labels.test.ts`; expect failure.
- [ ] **Step 3: Implement**, run `npm run db:types` and confirm the diff adds only the two enums, two tables and seven functions.
- [ ] **Step 4: Run** `npm run check`; expect pass.

---

### Task 6: Summary functions

**Files:**

- Create: `src/features/payments/summary.ts`, `src/features/payments/summary.test.ts`

**Interfaces:**

- `type PaymentLike = { status: PaymentStatus; kind: PaymentKind; amount: number; currency: string; markedPaidAt: string | null; dueDate: string | null; editorId?: string; projectId?: string }`.
- `summariseByCurrency(rows, now: Date): Record<string, { committed: number; awaitingTransfer: number; onHold: number; paidThisMonth: number; paidAllTime: number; overdue: number }>` (spec §9; month and "today" in Asia/Colombo via `Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Colombo" })`).
- `summariseByEditor(rows, now)` → `Array<{ editorId; currency; ...same figures }>` sorted by committed desc.
- `projectMargin({ clientPrice: number | null; clientCurrency: string; rows }) → { kind: "margin"; amount; currency; includesOnHold } | { kind: "no_price" } | { kind: "mixed_currency" }`.
- Amounts summed in integer cents to avoid float drift; returned as numbers with 2 decimals.

- [ ] **Step 1: Write failing tests:** two currencies never mixed; reversal nets paid totals; a payment marked paid at `2026-11-30T19:00:00Z` counts in December for Asia/Colombo (UTC+5:30); on-hold excluded from committed; overdue counts only unpaid rows with `dueDate` before Colombo today; margin for no price, mixed currency, on-hold flag, reversal netting; cents rounding (`0.1 + 0.2`).
- [ ] **Step 2: Run** `npx vitest run src/features/payments/summary.test.ts`; expect failure.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `npm run check`; expect pass.

---

### Task 7: Schemas, queries and server actions

**Files:**

- Create: `src/features/payments/schemas.ts`, `src/features/payments/schemas.test.ts`, `src/features/payments/queries.ts`, `src/features/payments/admin-actions.ts`

**Interfaces:**

- Schemas (zod, `uuid` ids, trimmed strings, `""` → `null` like `src/features/confirmation/schemas.ts`): `setPaymentStatusSchema` (`paymentId`, `status` in `pending_approval|approved|processing|on_hold`, `reason` ≤ 500, required when `on_hold`), `releaseHoldSchema`, `markPaidSchema` (`reference` 1..120, `transferDate` ISO date), `setDueDateSchema` (`dueDate` ISO date or empty → null), `reversePaymentSchema` (`reason` 1..500, `reopen` checkbox → boolean), `paymentNoteSchema` (`note` 1..4000), `adminEarningsFilterSchema` (`status`, `editor` uuid, `currency` `^[A-Z]{3}$`; invalid values dropped, not thrown), `editorEarningsFilterSchema` (`status`).
- `queries.ts` (`import "server-only"`; `createClient` from `src/lib/supabase/server.ts`):
  - `listMyPayments(): Promise<EditorPaymentRow[]>` — `supabase.rpc("editor_list_payments")`.
  - `listAdminPayments(filter): Promise<AdminPaymentRow[]>` — `payments` select with explicit columns + `projects(title)` + editor name from `profiles(full_name)` via `editor_id`; filter applied in the query.
  - `listProjectMargins(): Promise<ProjectMarginRow[]>` — `project_internal (project_id, client_price, client_price_currency)` joined to `projects(title)` for projects that have payments; combined with payment rows in `summary.projectMargin`.
  - `getAdminPayment(id)` — the row, project title, editor name, reversal links, `payment_notes` (newest first) and `activity_logs` where `entity_type = 'payment' and entity_id = id`.
- `admin-actions.ts` (`"use server"`; each: `await requireAdmin()`, `safeParse`, `rpc`, `userMessageFromDbError` on error, `revalidatePath("/admin/earnings")` + `/admin/earnings/${id}` + `refresh()`): `setPaymentStatusAction`, `releasePaymentHoldAction`, `markPaymentPaidAction`, `setPaymentDueDateAction`, `reversePaymentAction`, `addPaymentNoteAction`. `FormState` and `validationError` from `src/features/authentication/schemas.ts`. No editor actions (editors write nothing).

- [ ] **Step 1: Write failing schema tests:** valid/invalid per field above; reason required only for `on_hold`; `status = "paid"` rejected; filter schema drops bad values.
- [ ] **Step 2: Run** `npx vitest run src/features/payments/schemas.test.ts`; expect failure.
- [ ] **Step 3: Implement** the three files.
- [ ] **Step 4: Run** `npm run check`; expect pass.

---

### Task 8: Shared components

**Files:**

- Create: `src/features/payments/components/payment-status-pill.tsx` (wraps `StatusPill` with label/tone; reversal rows show "Correction"), `summary-cards.tsx` (one card group per currency, figures labelled per audience via props, stacks at 375px), `status-filter.tsx` (link chips driven by search params, `aria-current` on the active one), `money.tsx` (`<Money amount currency />` using `formatMoney`; negative amounts prefixed "−").

- [ ] **Step 1:** Implement; follow `docs/DESIGN_SYSTEM.md` (status pills, cards, empty states) and the `.claude/rules/ui.md` rules.
- [ ] **Step 2: Run** `npm run check`; expect pass.

---

### Task 9: `/editor/earnings`

**Files:**

- Create: `src/app/editor/earnings/page.tsx`, `src/features/payments/components/editor-payment-list.tsx`
- Modify: `src/app/editor/layout.tsx` (`EDITOR_NAV` += `{ href: "/editor/earnings", label: "Earnings", icon: "earnings" }`), `src/components/app-shell/nav-links.tsx` (`ICONS.earnings = Wallet`, Call 9)

**Interfaces:**

- Page: heading "Earnings"; `<Suspense>` around an async section that calls `listMyPayments()` (per request, never cached), parses `searchParams` with `editorEarningsFilterSchema`, renders `SummaryCards` from `summariseByCurrency(allRows, new Date())` (cards: Committed, Approved, Paid this month, Paid all time, On hold when > 0), `StatusFilter`, then `EditorPaymentList` (rows: project title, amount, pill, due date, paid date + reference, hold or correction reason; list items as cards at 375px). Empty state (spec §11); filtered-empty state "No payments with this status." with a clear-filter link.

- [ ] **Step 1:** Implement.
- [ ] **Step 2: Run** `npm run check`; signed-in manual check at 375px and desktop delegated to the `qa-browser` agent in Task 12.

---

### Task 10: `/admin/earnings`

**Files:**

- Create: `src/app/admin/earnings/page.tsx`, `src/features/payments/components/admin-payments-table.tsx`, `src/features/payments/components/editor-breakdown.tsx`, `src/features/payments/components/project-margin-table.tsx`, `src/features/payments/components/admin-filters.tsx`
- Modify: `src/app/admin/layout.tsx` (`ADMIN_NAV` += `{ href: "/admin/earnings", label: "Earnings", icon: "earnings" }` after Projects)

**Interfaces:**

- Page: heading "Earnings"; sections inside `<Suspense>`: summary cards (Outstanding liabilities, Approved awaiting transfer, On hold, Paid this month, Paid all time) from all rows; `AdminFilters` (status, editor select, currency select; GET form, no JS required); Payments table (project, editor, amount, pill, due date with "Overdue" badge, paid date; row links to `/admin/earnings/[id]`); By editor (`summariseByEditor`); Project margin (`projectMargin` per project; labelled "Admin only: client price minus editor pay"). Tables collapse to row cards below `sm`. Empty states: "No payments yet. A payment record is created when you confirm an editor."

- [ ] **Step 1:** Implement.
- [ ] **Step 2: Run** `npm run check`; expect pass.

---

### Task 11: `/admin/earnings/[id]` and action forms

**Files:**

- Create: `src/app/admin/earnings/[id]/page.tsx`, `src/features/payments/components/payment-actions.tsx` (client; `useActionState` per form, pattern of `src/features/confirmation/components/forms.tsx`), `src/features/payments/components/payment-notes.tsx`, `src/features/payments/components/payment-history.tsx`
- Optional (last): `src/app/admin/projects/[id]/page.tsx` and `src/app/editor/projects/[id]/page.tsx` — one line "Payment: <pill>" linking to the detail / earnings page.

**Interfaces:**

- Page: `notFound()` when `getAdminPayment` returns null; facts (project, editor, amount, currency, kind, due date, approved by/at, paid by/at, reference, transfer date, reverses / reversed by links); forms rendered from `nextAdminActions(...)`: advance buttons, hold (reason textarea + `HOLD_REASON_HINT`), release, due date (date input, clear), mark paid (reference + transfer date defaulting to Colombo today), reverse (reason + "Re-open the payment for re-approval" checkbox, confirmation text "A paid payment cannot be edited; this adds a correction."); notes log with add form; history from `activity_logs` via `activityLabel`.

- [ ] **Step 1:** Implement.
- [ ] **Step 2: Run** `npm run check`; expect pass.

---

### Task 12: E2E gates, docs, advisors and reviews

**Files:**

- Modify: `tests/e2e/smoke.spec.ts` (gate list += `/editor/earnings`, `/admin/earnings`, `/admin/earnings/7a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d`)
- Modify: `docs/DATABASE_SCHEMA.md` (payments row → built tables), `docs/SECURITY_AND_PRIVACY.md` (payments matrix row; `payment_notes` admin-only; E not enforced yet), `docs/WORKFLOWS.md` (payment lifecycle replaces the "see I" line), `docs/BUSINESS_RULES.md` (payments: lifecycle and reversal rule), `docs/PRODUCT_SPEC.md` (earnings screens), `docs/DEVELOPMENT_ROADMAP.md` (Phase 9 status; E and G remain), `docs/CURRENT_STATUS.md`, `docs/CHANGELOG.md`

- [ ] **Step 1:** `npm run test:e2e` (local Supabase running); expect the three new gate tests green.
- [ ] **Step 2:** `npm run db:advisors`; expect no new security warnings.
- [ ] **Step 3:** Update the docs; record spec/plan calls as awaiting owner review; flag F (call 2), E (call 11) and suspended-editor visibility (call 9) at the top of `CURRENT_STATUS.md`. Do not edit `EDITSTATION_MASTER_KNOWLEDGE_BASE.md`.
- [ ] **Step 4:** `npm run check` and `npm run db:test`; both green.
- [ ] **Step 5:** Dispatch `db-security` over the three migrations and tests 070–076; `code-reviewer` over the UI diff; `qa-browser` for signed-in `/editor/earnings` and `/admin/earnings` at 375px and desktop (no horizontal scroll, empty and filled states, margin section absent from every editor page). Fix findings with tests; re-run Step 4.

---

## Self-review notes

Spec coverage: §5 schema and guards → Task 1; §6 RLS → Task 1 (071) and Task 3 (075); §4.2/§4.3 triggers → Task 2; §7 lifecycle → Task 1 matrix and Task 3; §8 functions → Task 3; audit and hygiene (§8, §10) → Task 4; §9 figures → Task 6; §11 screens → Tasks 8–11; Playwright gates → Task 12. Margin data is read only by admin queries (`project_internal` is admin-only by RLS) and rendered only under `/admin`. Phase 8 must move `not_due → pending_approval` on work approval through `admin_set_payment_status`'s rules (or a private helper sharing them), not by a direct update.
