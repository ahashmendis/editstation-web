# Phase 9 design: payments and the earnings tracker

**Status:** draft under the owner's standing instruction of 2026-11-14 ("accept recommended"),
awaiting owner review. **Owner request (verbatim):** "there should be an earning tracker for both
pages editor and admin". **Decision applied:** OPEN_QUESTIONS **I** (recorded 2026-11-14).
**Not decided here:** E (bank/payout details: not built), G (test payments: not built), KB9
(payment schedule: the admin sets a due date by hand), F (extra-round pay, scope changes,
cancellation, kill fees), A2 (separate "mark paid" permission). Each is flagged where it touches
the design (§12).

**Depends on** the Phases 5–6 and Phase 7 database layers (assignments with
`agreed_amount`/`agreed_currency`, statuses `confirmed`/`in_progress`, `admin_confirm_assignment`,
`admin_reassign`, `private.close_live_assignments`). Section numbers (§) are referenced by the plan
`docs/superpowers/plans/2026-11-14-phase9-earnings.md`.

## 1. Intent

Make what Lenscape owes and has paid each editor visible from the moment pay is committed, and let
the admin move each payment through a small, audited lifecycle up to "paid". Editors see their own
earnings; the admin sees totals, liabilities, a per-editor breakdown and per-project margin.
Money moves outside the app (manual Sri Lankan bank transfers, KB §8.2); the app only records it.

## 2. Goals, non-goals, anti-goals

- **Goals:** one `payments` record per confirmed assignment, created automatically for the agreed
  amount; admin-only status changes through functions; `paid` final; corrections by reversal
  rows; editor and admin earnings screens.
- **Non-goals:** bank or payout details (E), test/assessment payments (G), automatic due dates
  (KB9), pay adjustments, extra-round pay or kill fees (F), a separate payer role (A2), currency
  conversion (H: none in the MVP), exports, notifications (KB10, Phase 10), automatic
  `not_due → pending_approval` on project approval (Phase 8 has not been built; §9 note).
- **Anti-goals:** no payment gateway; no editor write of any kind; no client price, margin or
  client data in any editor-readable table or function; never editing a paid row.

## 3. Constraints

- RLS on `payments` and `payment_notes`, default deny, `select`-only grants; writes only through
  `public.admin_*` security-definer functions or `private` triggers.
- Admin = `private.require_admin()` (MFA `aal2`); editor = `private.require_active_editor()`.
- Errors `ES401`/`ES403`/`ES409`/`ES422` only; plain user-safe sentences.
- Money `numeric(12,2)` with sibling `char(3)` currency (decision H). Amounts, references and free
  text never appear in `activity_logs.details`.
- Editor-visible tables hold no client data and no client pricing (RLS is row-level). Internal
  notes therefore live in a separate admin-only table (§5).

## 4. Approaches considered

### 4.1 When the record is created

1. **At assignment confirmation (chosen; decision I).** Committed-but-unpaid costs show from day
   one, which is what makes "outstanding liabilities" meaningful.
2. At work approval (§10.4 set). Hides liabilities until late; rejected by I.

### 4.2 How it is created

1. **`AFTER UPDATE OF status` trigger on `assignments`** when `old.status = 'accepted'` and
   `new.status = 'confirmed'` (chosen). Every confirmation path (today only
   `admin_confirm_assignment`) creates the record, in the same transaction and under the locks
   that function already holds (project, then assignment). No Phase 6 function is replaced.
2. Add an insert to `admin_confirm_assignment`. Replacing a reviewed function to add one line is
   riskier and a future confirmation path could forget it.

### 4.3 Reassignment and cancellation (decision I says "whether `cancelled` is needed depends on F")

1. **Automatic `on_hold` with a fixed system reason (chosen; flagged, F).** When a `confirmed` or
   `in_progress` assignment becomes `reassigned` or `withdrawn`, every unpaid payment of that
   assignment moves to `on_hold` with reason _"The assignment ended before the work was
   finished. Lenscape will contact you about this payment."_ It stays visible as an unresolved
   liability until the admin acts (release the hold, or leave it on hold). No cancellation status,
   no kill-fee or partial-pay logic, no deletion. Paid rows are untouched.
2. A `cancelled` status. Needs a rule for what is owed on cancellation, which is F. Not added.
3. Leave the record as it was. A reassigned editor's `not_due` payment would keep counting as
   committed with no prompt to resolve it.

Consequence the owner should know: until F is decided, a cancelled assignment's payment can only
be released (paid in full) or left on hold; on-hold amounts are reported separately from
committed liabilities so they never inflate them silently.

### 4.4 Corrections

`paid` is final (I). A mistake is corrected by `admin_reverse_payment`, which inserts a
**reversal row** (`kind = 'reversal'`, negative amount equal to the whole original, status `paid`,
linked by `reverses_payment_id`, one per original). Optionally it also re-opens the liability by
inserting a fresh `kind = 'assignment'` row for the same amount in `pending_approval` (for "marked
paid by mistake"); without re-opening it records money returned. Partial reversals are not
supported (minimal; anything partial is F territory).

### 4.5 Where summaries are computed

Pure TypeScript functions over rows the caller can already read (editor: `editor_list_payments`;
admin: RLS reads). At pilot scale (5–10 editors) this is cheap, keeps SQL small, and the arithmetic
is unit-tested in Vitest. A SQL summary function can replace it later without changing screens.

## 5. Schema

### Enums

- `public.payment_status` = (`not_due`, `pending_approval`, `approved`, `processing`, `paid`,
  `on_hold`) (decision I).
- `public.payment_kind` = (`assignment`, `reversal`). G or F may add kinds later.

### `public.payments`

| Column                    | Type / rule                                                                             |
| ------------------------- | --------------------------------------------------------------------------------------- |
| `id`                      | uuid pk                                                                                 |
| `assignment_id`           | uuid not null FK `assignments` restrict (nullable only if G later allows test payments) |
| `project_id`              | uuid not null FK `projects` restrict (equals the assignment's)                          |
| `editor_id`               | uuid not null FK `editor_profiles (user_id)` restrict (equals the assignment's)         |
| `kind`                    | `payment_kind` not null default `assignment`                                            |
| `amount`                  | numeric(12,2) not null; `> 0` for `assignment`, `< 0` for `reversal`                    |
| `currency`                | char(3) not null, `^[A-Z]{3}$`                                                          |
| `status`                  | `payment_status` not null default `not_due`                                             |
| `held_from_status`        | `payment_status`; set exactly while `on_hold` (the status to return to)                 |
| `on_hold_reason`          | text 1..500; set exactly while `on_hold`; **visible to the editor**                     |
| `due_date`                | date, nullable; set by the admin (KB9)                                                  |
| `transfer_date`           | date; required when an `assignment` row is `paid` (KB §8.2 "transfer date")             |
| `transaction_reference`   | text 1..120; required when an `assignment` row is `paid`; visible to the editor         |
| `reverses_payment_id`     | uuid FK `payments` restrict, unique; set exactly when `kind = 'reversal'`               |
| `reversal_reason`         | text 1..500; set exactly when `kind = 'reversal'`; visible to the editor                |
| `approved_by`/`_at`       | FK `profiles` set null / timestamptz; set on entering `approved`                        |
| `marked_paid_by`/`_at`    | FK `profiles` set null / timestamptz; set on entering `paid`                            |
| `created_by`              | FK `profiles` set null (null when created by the confirmation trigger with no session)  |
| `created_at`,`updated_at` | timestamptz                                                                             |

Constraints: `payments_amount_chk` (sign by kind); `payments_hold_chk` (`(status = 'on_hold') =
(held_from_status is not null) = (on_hold_reason is not null)`, and `held_from_status not in
('on_hold','paid')`); `payments_approved_chk` (status in `approved`,`processing`,`paid` and
kind `assignment` ⇒ `approved_at` not null; `held_from_status` in those likewise);
`payments_paid_chk` (`status = 'paid'` ⇒ `marked_paid_at` not null; for `assignment` also
`transaction_reference` and `transfer_date`); `payments_reversal_chk` (kind `reversal` ⇔
`reverses_payment_id` and `reversal_reason` not null, and reversal ⇒ `status = 'paid'`).
Indexes: unique partial `payments_open_key on (assignment_id) where kind = 'assignment' and status
<> 'paid'` (at most one unpaid record per assignment); unique `reverses_payment_id`; `(editor_id,
created_at desc)`, `(project_id)`, `(status)`, and one per actor FK.

The table has **no notes column**: the "Internal notes" of KB §8.2 go to `payment_notes`, so the
editor-readable row never carries admin-only text.

### `public.payment_notes` (admin-only, append-only; mirrors `project_notes`)

`id`, `payment_id` FK restrict, `author_id` FK `profiles` set null, `note text not null 1..4000`,
`created_at`. Guarded by the existing `private.guard_append_only('author_id')`.

### Guards (BEFORE triggers, hold for the table owner too)

- `private.check_payment_row()` BEFORE INSERT: `project_id`/`editor_id` equal the assignment's;
  an `assignment` row needs the assignment's `confirmed_at` set and `amount`/`currency` equal to
  its `agreed_amount`/`agreed_currency`; a `reversal` row must reverse a `paid` `assignment` row of
  the same assignment, with `amount = -original.amount` and the same currency; else `ES409`.
- `private.guard_payments()` BEFORE UPDATE OR DELETE: delete `ES409`; `assignment_id`,
  `project_id`, `editor_id`, `kind`, `amount`, `currency`, `reverses_payment_id`,
  `reversal_reason`, `created_*` never change; a row whose `old.status = 'paid'` never changes
  except clearing an actor column (`approved_by`, `marked_paid_by`, `created_by`) to null with
  every other column unchanged; status changes must pass `private.payment_transition_allowed`.

## 6. Visibility and RLS

| Identity            | `payments`                   | `payment_notes` | `editor_list_payments()` |
| ------------------- | ---------------------------- | --------------- | ------------------------ |
| Admin (aal2)        | all rows                     | all rows        | `ES403`                  |
| Admin (aal1)        | none                         | none            | `ES403`                  |
| Active editor A     | own rows (`editor_id = uid`) | none            | own rows + project title |
| Editor B            | own rows only (none of A's)  | none            | own rows only            |
| Suspended / revoked | none                         | none            | `ES403`                  |
| Applicant           | none                         | none            | `ES403`                  |
| Anon                | `42501` (no grant)           | `42501`         | `ES401`                  |

Policy `payments_select`: `(select private.is_admin()) or (editor_id = (select auth.uid()) and
(select private.is_active_editor()))`. `payment_notes_select`: admin only. No insert/update/delete
grant or policy.

Why `editor_list_payments()`: the editor's project read access (`editor_project_stage`) ends at
reassignment, but an editor must still see which project an old payment was for. The function
returns only the project **id and title** (never brief, client or price fields) for the caller's
own payments. Suspended editors see nothing in the app (consistent with every editor table); the
admin still sees and settles their payments (flagged §12).

## 7. Lifecycle

```
not_due ──► pending_approval ──► approved ──► processing ──► paid (final)
                                     └───────────────────────► paid
any of the four unpaid states ──► on_hold (reason required) ──► back to held_from_status
```

`private.payment_transition_allowed(from, to)`: `not_due → pending_approval | on_hold`;
`pending_approval → approved | on_hold`; `approved → processing | paid | on_hold`;
`processing → paid | on_hold`; `on_hold → <held_from_status>` only (checked in the guard, which
knows the row). Nothing leaves `paid`. A wrongly approved payment is put on hold, not moved back.
`approved → paid` directly is allowed because `processing` is optional for a same-day transfer
(call 3).

## 8. Functions

All `security definer set search_path = ''`, first statement `require_admin()` or
`require_active_editor()`, executable by `anon` and `authenticated` (guardrail), payment row
locked `for update` before reading its state.

| Function                                                                                         | Rule                                                                                                                                                                                                                                                                                    |
| ------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `admin_set_payment_status(p_payment_id uuid, p_status text, p_reason text default null)`         | Targets `pending_approval`, `approved`, `processing`, `on_hold` only (`paid` → "Use mark as paid", `not_due` → `ES422`). `on_hold` needs a reason (`ES422`), stores `held_from_status`. `approved` sets `approved_by/at`.                                                               |
| `admin_release_payment_hold(p_payment_id uuid)`                                                  | Only from `on_hold`; returns to `held_from_status`, clears reason and `held_from_status`.                                                                                                                                                                                               |
| `admin_mark_payment_paid(p_payment_id uuid, p_transaction_reference text, p_transfer_date date)` | From `approved` or `processing`; reference required (trimmed, 1..120); transfer date required, not in the future (Asia/Colombo) and not before the assignment's `confirmed_at` date; sets `marked_paid_by/at`.                                                                          |
| `admin_set_payment_due_date(p_payment_id uuid, p_due_date date)`                                 | Any unpaid status; `null` clears it. No past-date restriction (back-dating a schedule is legitimate).                                                                                                                                                                                   |
| `admin_reverse_payment(p_payment_id uuid, p_reason text, p_reopen boolean)`                      | Only a `paid` `assignment` row with no reversal yet; inserts the reversal (`paid`, `marked_paid_by/at` = now/admin, no reference); when `p_reopen`, also inserts a new `assignment` row in `pending_approval` (fails `ES409` if an unpaid row already exists). Returns the reversal id. |
| `admin_add_payment_note(p_payment_id uuid, p_note text)`                                         | Appends to `payment_notes`.                                                                                                                                                                                                                                                             |
| `editor_list_payments()`                                                                         | Own rows with `project_id`, `project_title`; every `payments` column except actor ids.                                                                                                                                                                                                  |

Triggers: `private.create_assignment_payment()` AFTER UPDATE OF status on `assignments`
(`accepted → confirmed`: insert `not_due`, amount/currency from `agreed_*`, `created_by` = the
confirming admin); `private.hold_payments_on_close()` AFTER UPDATE OF status on `assignments`
(`confirmed|in_progress → reassigned|withdrawn`: unpaid rows → `on_hold` with the §4.3 reason;
rows already on hold keep their reason). Audit: `payment.created`, `payment.<status>`,
`payment.hold_released`, `payment.due_date_set`, `payment.reversed`, `payment_note.added`;
details `{payment_id, assignment_id, from, to}` (ids and enum names only).

## 9. Earnings figures

Per currency, never summed across currencies (H: no conversion). "This month" = calendar month in
**Asia/Colombo** of `marked_paid_at` (call 6).

- **Committed (unpaid)** = sum of `not_due + pending_approval + approved + processing`.
- **Approved, awaiting transfer** = `approved + processing`.
- **On hold** = `on_hold` (separate; includes ended assignments, §4.3).
- **Paid this month / all time** = sum of all `paid` rows including negative reversals (net).
- **Admin: outstanding liabilities** = committed; on hold shown beside it, not inside it.
- **Admin: per editor** = the four figures above per editor and currency, plus count of overdue
  payments (`due_date < today`, unpaid). Overdue is a display flag only (KB9).
- **Admin: per-project margin (admin-only)** = `project_internal.client_price` minus the net editor
  cost (sum of every payment row of the project, reversals included). Shown only when
  `client_price` is set and every row shares `client_price_currency`; otherwise "No client price"
  or "Currencies differ". Rows on hold are included and flagged "includes on-hold pay".

Phase 8 note: when Phase 8 adds work approval it should move `not_due → pending_approval`
automatically; until then the admin does it by hand.

## 10. Tests

- **pgTAP 070–076:** schema, constraints and guards; RLS matrix for admin aal2, admin aal1, editor
  A, editor B, suspended S, applicant, anon on both tables and `editor_list_payments`; the full
  transition matrix (36 pairs) as table owner; creation on confirmation (amount/currency copied,
  exactly one row, none for seeded inserts); hold on reassign/cancel (paid rows untouched);
  function happy paths and refusals; reversal and re-open; append-only notes; function security
  catalogue and data hygiene (no client/price columns on `payments`, `editor_list_payments`
  returns no such fields); audit details free of amounts, references and reasons.
- **Vitest:** zod schemas for each admin form; summary functions (per-currency split, reversal
  netting, month boundary in Asia/Colombo, margin rules); label/tone maps complete.
- **Playwright:** signed-out gates for `/editor/earnings`, `/admin/earnings` and
  `/admin/earnings/<uuid>`.

## 11. Screens

- **`/editor/earnings`** (nav "Earnings"): summary cards per currency (Committed, Approved,
  Paid this month, Paid all time, On hold when non-zero); status filter chips; list of own
  payments (project title, amount, status pill, due date, paid date and reference, hold or
  reversal reason). Empty state: "No earnings yet. Pay appears here once an admin confirms you on
  a project." Reversals shown as negative amounts labelled "Correction".
- **`/admin/earnings`** (nav "Earnings"): summary cards per currency (Outstanding liabilities,
  Approved awaiting transfer, On hold, Paid this month, Paid all time); filters (status, editor,
  currency) via search params; tabs or sections: Payments table, By editor, Project margin
  (admin-only). Rows link to the detail page. Empty states per section.
- **`/admin/earnings/[id]`**: payment facts, status pill, actions valid for the current status
  (approve/advance, put on hold with reason, release hold, set due date, mark paid with reference
  and transfer date, reverse with reason and "re-open" checkbox), notes log, activity history.
- **Status pills:** not due = neutral "Not due"; pending approval = warning "Pending approval";
  approved = info "Approved"; processing = info "Processing"; paid = success "Paid"; on hold =
  danger "On hold". All screens work at 375px (cards stack, tables become row cards).
- Admin project page and editor project page get a one-line payment status link (optional, last
  task).

## 12. Calls made (owner may override)

1. **Creation by trigger** on `accepted → confirmed` (§4.2); `admin_confirm_assignment` unchanged.
2. **Ended assignments → automatic `on_hold`** with a fixed editor-visible reason; no `cancelled`
   status, no kill-fee or partial pay (§4.3). **Flag F.**
3. **`processing` optional:** `approved → paid` allowed.
4. **Full reversals only**, optional re-open in `pending_approval` (§4.4).
5. **Internal notes in `payment_notes`**, not on `payments` (editor-visible row stays clean).
6. **Month boundary = Asia/Colombo.**
7. **Editors see hold/reversal reasons and the transaction reference**; admins write reasons
   knowing that (form hint says so).
8. **`transfer_date` added** (KB §8.2, DATABASE_SCHEMA row) alongside `marked_paid_at`.
9. **Suspended/revoked editors** lose the earnings screen like every editor screen; payments
   remain for the admin. **Flag:** if former editors need payment visibility, that needs a
   decision.
10. **Single admin marks paid (A2 deferred):** any `aal2` admin may approve and mark paid;
    `approved_by` and `marked_paid_by` are recorded so separation can be added later.
11. **No bank-detail check on mark paid (E not built):** decision E's "no payment to unverified
    details" cannot be enforced until payout details exist. **Flag E** before payments are
    recorded for real transfers through the app.
12. **Assignment pay is fixed at the agreed amount;** any future adjustment mechanism (F) adds
    rows of a new kind rather than editing a payment.

## 13. Open questions touched

- **I:** resolved 2026-11-14 (recommendation adopted; decisions log).
- **F:** open; affects call 2, 4, 12.
- **E:** open for build (decision exists, not built); call 11.
- **G:** open; `assignment_id not null` now, relaxed by a later migration if test payments are
  tracked.
- **KB9:** open; manual `due_date` only.
- **A2:** deferred; call 10.
