# Phase 12 design: project terms, client billing, editor milestones, assets and payout details

Status: **approved by the owner on 2026-11-15, including the recommended answer to each of the 11 calls in section 9. Nothing here is built yet.** Written 2026-11-15 from the owner
decisions KB7, F, F2, F3, KB9, KB9a, KB9b, KB7a and E (`docs/OPEN_QUESTIONS.md` decisions log).
No code, migration or commit follows until this design is approved.

## 1. Goal

Make the agreed commercial rules enforceable by the database: per-project terms recorded as an
auditable agreement, client billing separate from editor pay, a verified-deposit start gate,
editor pay milestones, extra-work and cancellation pay, client-owned asset links, and payout
details (built but locked until the PDPA review).

Non-goals: payment gateway or escrow; currency conversion; client accounts or a client portal;
automatic bank reconciliation; legal wording of contracts (KB8); inventing any price, fee,
percentage or deadline beyond the owner's stated defaults.

## 2. Approaches considered

| Approach                                                                                               | Trade-off                                                                                                             |
| ------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------- |
| **A. One versioned terms agreement per project, with milestone rows hanging off it (recommended)**     | One auditable record of everything agreed; reuses the Phase 7 confirmation pattern; more tables up front              |
| B. Keep adding columns to `projects` / `payments` (e.g. more `*_days` columns, a second amount column) | Fewer tables, but terms change in place, so no agreement history, and client money would sit near editor-visible data |
| C. Free-form JSON "terms" blob validated in the app                                                    | Fast, but the database cannot enforce gates or lock changes, which breaks "enforce in the database"                   |

Recommendation: **A**. Client-only data lives in admin-only tables; editors read an editor-safe
projection through functions (the Phase 9 `editor_list_payments` pattern), never a table that
also holds client prices.

## 3. Delivery slices (recommended order)

Each slice is its own branch, migrations, pgTAP tests, security review and owner review.

| Slice   | Content                                                                                               | Depends on |
| ------- | ----------------------------------------------------------------------------------------------------- | ---------- |
| **12A** | Terms agreement (versioned, locked) incl. revision policy, kill-fee schedule, day counts              | none       |
| **12B** | Assets (KB7, KB7a): access type, verification, inaccessible reports, revocation checklist             | none       |
| **12C** | Client milestones, deposit verification, deposit gate, timed rules (auto-hold), scheduler             | 12A        |
| **12D** | Editor milestones, extra-work adjustments, scope quotes, partial disputes, cancellation settlement    | 12A, 12C   |
| **12E** | Payout details (E) behind a disabled flag, mark-paid check, interim attestation (call 1 in section 9) | 12D        |

12B can run in parallel with 12A. 12E ships last and stays locked.

## 4. Data model

All money columns carry a currency; no conversion. New tables have RLS on, no direct write
grants, and every function is executable by `anon` and `authenticated` and authorises in its body
(ES401/ES403/ES409/ES422). Audit rows in `activity_logs` hold ids and field names only.

### 4.1 Terms agreement (12A)

`project_terms` (admin-only, append-only, versioned; unique `(project_id, version)`):

- `status`: `draft | agreed | superseded`; `agreed_by`, `agreed_at`; `change_reason` (required for
  version >= 2 once any assignment is `in_progress`).
- Revision policy: `included_rounds` (0..20; 0 means chargeable from round 1, F3),
  `extra_round_charge` + `charge_currency` (both nullable until known; admin-only).
- Day counts (defaults from the owner decisions, changeable before the project starts):
  `deposit_days = 14`, `balance_days = 7`, `editor_pay_days = 7`, `late_balance_days = 14`.
- Editor side: `editor_milestone_shares` (e.g. 50/50, must sum to 100).
- Cancellation schedule rows in `project_terms_stages` (admin-only): `stage`
  (`assigned | in_progress | in_review | revision_requested`, the project status at cancellation),
  `editor_earned_percent`, `client_charge_percent`. **No default values**; the admin enters them
  per project, and a cancellation cannot be settled without them.

Immutable once `agreed`: a guard trigger refuses updates to agreed rows. A change creates version
n+1 and marks n `superseded` (the same pattern as `brief_versions`).

`projects.revision_allowance` stays as a **cache** written only by the agree function, so Phase 8
code (`renumber_client_rounds`, the review screens) keeps working. A trigger refuses direct edits
to it, and `admin_update_project` stops accepting it. The new-project form pre-fills 3 (owner) and
creates terms v1.

Editor view: `editor_get_terms(project_id)` returns only included rounds, the editor milestone
shares and the editor's kill-fee shares, never client prices, charges or milestones.

### 4.2 Client billing (12C), admin-only

`client_milestones`: `project_id`, `terms_id`, `seq`, `kind` (`deposit | balance | extra_work |
refund`), `amount`, `currency`, `invoice_issued_at`, `due_date`, `received_at`,
`transfer_reference`, `verification_status` (`expected | received_unverified | verified`),
`verified_by/at`, `reverses_id` (refunds are negative rows, like payment reversals).

- Default milestones come from the terms (50/50 of `project_internal.client_price`). Agreeing
  terms requires a client price; amounts are computed once and stored (last milestone takes the
  rounding remainder).
- Editors never read this table. They see only a derived flag (4.3).

### 4.3 Editor pay (12D)

Extends `payments` (existing statuses and `paid is final` rules stay):

- New columns: `milestone_seq`, `payable_reason` (`client_deposit_verified |
client_balance_verified | late_balance_protection | adjustment_accepted |
cancellation_settlement`), `payable_at`, `split_from_payment_id`, and a client-safe
  `waiting_on_client` flag set by triggers (never a free-text reason).
- `payments_open_key` (one open row per assignment) becomes one open row per
  `(assignment_id, milestone_seq)`.
- At assignment confirmation the trigger creates the editor milestone rows from the terms shares
  (default 50/50 of `agreed_amount`; last row takes rounding remainder), all `not_due`.
- Milestone 1 becomes payable (`pending_approval`, due = `payable_at` + `editor_pay_days`) when the
  client deposit is `verified` and the assignment is confirmed.
- Milestone 2 becomes payable when the project is `approved` and the client balance is `verified`,
  or when the balance is unverified `late_balance_days` after it was due and no dispute applies
  (Lenscape carries the risk).
- Admin approves and then marks paid only after verifying the transfer (existing functions, plus
  the 12E payout check).
- `editor_list_payments` is replaced to return an enum-based `hold_label` (for example "Under
  review", "Waiting for client payment") instead of the free-text `on_hold_reason`.

`payment_status` gains `cancelled` (voided by a settlement; final). This revises decision I,
which deferred `cancelled` until F was decided (section 9, call 2).

### 4.4 Extra work and scope (12D)

`compensation_adjustments`: `assignment_id`, `kind` (`extra_round | scope_change | cancellation`),
`amount`, `currency`, `revision_request_id` or `scope_quote_id`, `status` (`offered | accepted |
declined | withdrawn`), offered/answered by and at. The admin offers, the editor accepts or
declines with `editor_respond_adjustment`; the original agreed amount is never edited. Accepting
creates its own `payments` row (`payable_reason = adjustment_accepted`).

- `revision_requests` gains `adjustment_required`. The editor cannot acknowledge or start such a
  request until its adjustment is `accepted`; if declined, the admin decides (new offer, withdraw
  the request, or reassign).
- `scope_change_quotes` (admin-only): description, client quote amount, `status` (`drafted | sent
| accepted | declined`, client acceptance recorded by the admin). A scope change cannot begin
  until the quote is accepted **and** the editor adjustment is accepted. Acceptance creates an
  `extra_work` client milestone with an admin-entered due date (no default, call 5).

### 4.5 Partial disputes (12D)

`admin_split_payment_for_dispute(payment_id, disputed_amount, reason)` splits an unpaid milestone
into an undisputed row and a disputed child row (`split_from_payment_id`), puts only the child
`on_hold`, and keeps a trigger invariant that the parts sum to the original. Releasing the hold
returns the child to its prior state. This reuses the existing hold machinery instead of adding
partial-hold states everywhere (rejected alternative: a `held_amount` column).

### 4.6 Cancellation settlement (12D)

`admin_settle_cancellation(project_id, adjusted_editor_earned?, reason?)`:

1. Reads the stage from the project status at cancellation and the agreed stage schedule.
2. Computes editor earned = agreed total x `editor_earned_percent`, and the client charge from
   `client_charge_percent`; the admin may adjust the earned figure with a recorded reason.
3. Editor side: voids unpaid milestone rows (`cancelled`), creates a settlement row for any
   shortfall, or an audited reversal for any overpayment (reconciliation is recorded; recovering
   money is outside the app).
4. Client side: records a negative `refund` milestone for the unused portion (received minus
   completed work and cancellation charges), which the admin verifies like any transfer.

This replaces the Phase 9 behaviour that freezes unpaid payments when an assignment ends.

### 4.7 Assets (12B)

- `project_assets`: add `description`, `access_instructions`, `access_status` (`awaiting_access |
verified | inaccessible`), `verified_by/at`. Keep `other` as a provider value unless you decide
  otherwise.
- `asset_access_grants`: add `access_type` (`editor_account | anyone_with_link`),
  `removal_requested_at`, `removal_confirmed_at` (+ by). Admin screens show the access type with a
  security warning for `anyone_with_link`.
- `asset_access_reports` (append-only): `asset_id`, `editor_id`, `note`, `resolved_by/at`. Insert
  only through `editor_report_asset_inaccessible` (the assigned editor of that project); resolve
  through an admin function; every report notifies the admin.
- The revoke checklist now means "ask the client to remove access" and records requested and
  confirmed; ending an assignment never marks access as removed.

### 4.8 Payout details (12E, locked)

- `editor_payout_details` + append-only `editor_payout_detail_versions`: holder, bank, branch,
  account number, `verification_status` (`unverified | verified`), `verified_by/at`,
  `verified_method`. **No API grants on the tables**; reads and writes only through functions. The
  editor sees a masked number; an admin full-number reveal is a function call that writes an audit
  row. Any change resets to `unverified` and flags the admin (phone verification).
- Locked by an `app_settings` flag `payout_details_enabled = false`. While false, writes are
  refused, so no real bank data can be stored until counsel confirms PDPA handling and the owner
  turns it on. pgTAP uses fake data only.
- `admin_mark_payment_paid` requires a verified payout account (or the interim attestation, call
  1).

## 5. Gates and timed rules

- **Start gate (KB9b-4):** `private.assignment_gate` gains `client_deposit_verified`; `ready`
  requires it. The gate's return type changes, so the migration drops and recreates it with its
  dependents (`get_assignment_gate`, the enforcing triggers); the plan must list them from the
  catalog before writing.
- **Confirm gate:** `admin_confirm_assignment` requires agreed terms with a valid editor milestone
  split.
- **Auto-hold (KB9a-2):** if the deposit is unverified `deposit_days` after `invoice_issued_at`,
  the project goes `on_hold` with a deposit-unpaid reason; the admin extends (new due date,
  reason) or cancels. This needs `assigned -> on_hold` (call 3). `in_progress -> on_hold` stays
  refused because the start gate makes that state unreachable without a deposit.
- **Late-balance protection (KB9a-1):** see 4.3, skipped while a dispute exists.
- **Scheduler (call 7):** the rules above run in one idempotent `private.apply_timed_rules(p_now)`.
  It is called by (1) `pg_cron` on hosted Supabase, (2) an admin-only `admin_run_timed_rules()`
  that the admin dashboard and `/admin/earnings` invoke on load (works locally and as a backstop),
  and (3) pgTAP with an explicit `p_now`, so no test sleeps. Every action it takes is audited and
  notifies the admin.
- "Calendar days" use a business timezone setting (call 4).

## 6. App changes (summary)

- Admin project page: a **Terms** card (versions, agree, change with reason), **Client billing**
  panel (milestones, issue invoice, record and verify transfer), scope quotes, and the extended
  revision and cancellation panels.
- Admin assets: access type, verification, reports, checklist with requested/confirmed.
- Editor: **Terms** summary (editor-safe), adjustment offers to accept or decline, milestone view on
  `/editor/earnings` with "Waiting for client payment", an inaccessible-link report button.
- Notifications (extend KB10; only the first is owner-decided, call 8): asset reported
  inaccessible (admin); proposed: adjustment offered (editor), adjustment answered (admin),
  project auto-held (admin), late-balance protection triggered (admin).
- Admin metrics: gross contribution (client received minus editor paid) becomes computable
  (optional, owner's call).

## 7. Security and testing

- Client prices, charges, milestones, quotes and kill-fee client percentages are admin-only.
  Editors reach financial data only through safe functions; the 12D migration replaces
  `editor_list_payments` to stop leaking free-text reasons.
- Every new table and function gets pgTAP as admin, editor A, editor B, pending applicant and
  anon, including "editor cannot read or infer client money", guard-trigger refusals, race checks
  (two admins agreeing terms or releasing holds), timed-rule tests with explicit `p_now`, and the
  sum invariants. Security guardrails (RLS on every table, public function grants) stay green.
- Each slice gets a db-security review, a code-reviewer pass and signed-in e2e for the main path.
- All Phase 12 findings feed the separate owner-led security assessment (S1-S10 list).

## 8. Conflicts resolved by this design

(Numbering follows `docs/DATABASE_SCHEMA.md`, "Conflicts with what Phases 0-11 built".)

1. `on_hold` from `assigned`: allowed for the unpaid-deposit rule only (call 3).
2. No client-money check at start: deposit gate (section 5).
3. One editor payment per assignment: milestone rows (4.3).
4. Ending an assignment freezes unpaid pay: cancellation settlement replaces it (4.6).
5. Whole-row holds: split rows for partial disputes (4.5).
6. Editable revision number: locked, versioned terms (4.1).
7. Free-text hold reasons visible to editors: enum-based hold labels (4.3).
8. Revoke checklist assumed Lenscape revokes access: request and confirm states (4.7).
9. No scheduler: timed-rules function (section 5).

## 9. Calls that need the owner (recommendations in brackets)

1. **Marking paid before payout details are live.** E-1 requires a verified payout account before
   any payment is marked paid, but E-2 forbids storing real bank data until counsel review. So no
   real payment could be marked paid in the app until then. [Recommended: an interim per-editor
   "payout account verified outside the app" attestation (admin name and date, no bank data),
   retired when E goes live. Alternative: pay and track outside the app until E is live.]
2. **Add a `cancelled` payment status**, revising decision I. [Yes.]
3. **Allow `assigned -> on_hold`** for the unpaid-deposit rule. [Yes, only that transition.]
4. **Business timezone for "calendar days".** [An admin setting, default Asia/Colombo; please
   confirm.]
5. **Client due date for extra-round and scope-change charges.** Not specified. [Admin enters it per
   charge; no default.]
6. **Terms changes after work begins.** [Client-only changes need a reason and are audited;
   anything affecting editor pay needs the editor's acceptance through an adjustment offer.]
7. **Scheduler approach** (section 5). [Sweep function with `pg_cron` on hosted plus the admin
   trigger.]
8. **New notification events** beyond asset-inaccessible (section 6). [Add the four proposed.]
9. **Rounding** for odd amounts: the last milestone takes the remainder. [My call; tell me if you
   want otherwise.]
10. **Existing local projects** have no terms. [Backfill terms v1 from `revision_allowance` with
    no milestones; the new gates apply to assignments confirmed after the migration. Local data
    only; no hosted data exists.]
11. **Slice order and start.** [12A with 12B in parallel, then 12C, 12D, 12E.]
