# Phase 7 Database Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Phase 7 database layer: `assignment_status.in_progress`, `editor_interpretations`, immutable `brief_confirmations` with recorded carry-forward, the single gate predicate `private.assignment_gate`, gated start functions, and DB triggers so no path reaches `in_progress` unless pay is admin-approved, the current brief version is confirmed without drift, and the interpretation is accepted where required.

**Architecture:** Same model as Phases 4–6. New tables have `select`-only grants and one combined admin-or-own-editor select policy; every write is a `public.admin_*` / `public.editor_*` security-definer function. The gate is one `private` function used by the start functions, by a `BEFORE UPDATE` guard on `assignments` and (indirectly) by a `BEFORE UPDATE OF status` guard on `projects`. Carry-forward is an `AFTER INSERT` trigger on `brief_versions`. Phase 6 functions that list "live"/"confirmed" statuses are `create or replace`d to include `in_progress`. Delivered as six small append-only migrations.

**Tech Stack:** Postgres (Supabase local, CLI pinned 2.122.1), pgTAP, plpgsql. No application code: screens are a separate plan written after this layer is reviewed.

**Spec:** `docs/superpowers/specs/2026-11-14-phase7-confirmation-gate-design.md` (draft under the owner's standing instruction of 2026-11-14). Section numbers (§) refer to it. Plan calls beyond the spec are listed under **Calls** and flagged `(call)` where used. **Depends on** the Phases 5–6 migrations (`20261114061439` … `20261114063650`) and their tests 050–057 being green; names below follow that plan's Interfaces and the migrations as written.

## Global Constraints

- RLS on every new table; `revoke all ... from anon, authenticated`, then only `grant select ... to authenticated` and one policy `<table>_select for select to authenticated using ((select private.is_admin()) or (<own row> and (select private.is_active_editor())))`, the combined-policy form used in `20261114062429_phase6_editor_visibility.sql`. No insert/update/delete grant or policy anywhere.
- Every `public.admin_*` / `public.editor_*` / `public.get_*` function: `language plpgsql security definer set search_path = ''`; first statement `private.require_admin()`, `private.require_active_editor()` or (for `get_assignment_gate` only) `private.require_user()`; then `revoke all on function <sig> from public, anon, authenticated;` and `grant execute on function <sig> to anon, authenticated;`. Every `private.*` function and trigger function: `revoke all ... from public, anon, authenticated;` and no grant (`private.editor_project_stage(uuid)` keeps its existing `authenticated` grant when replaced: re-issue `grant execute ... to authenticated` then `revoke ... from public, anon`, in that order).
- Errors only `ES401`/`ES403` (from the `require_*` helpers), `ES409` (state conflict), `ES422` (invalid input); never `42501`. Plain user-safe sentences. Wrap `check_violation` into `ES422` (Phase 4 pattern).
- Lock order: `projects` row `for update` first, then the `assignments` row, via `private.lock_assignment` (Phase 6). Editor functions first check ownership with a plain `select ... where id = p_assignment_id and editor_id = v_uid` and raise `ES422` "Assignment not found." (same message for unknown and not-own ids), then call `lock_assignment` and re-read state under the lock.
- `alter type ... add value` lives alone in its migration (Postgres refuses to use a new enum value in the transaction that adds it). No other statement in that file.
- Money: `numeric(12,2)` with sibling `char(3)` currency, `check (currency ~ '^[A-Z]{3}$')`. Amounts, free text, deadlines and deliverables never appear in `activity_logs.details`.
- Never edit an applied (committed) migration; new migrations via `npx supabase migration new <name>`, timestamps after `20261114063650`. Local database only.
- Audit rows: `public.activity_logs (actor_id, action, entity_type, entity_id, details)`; `details` hold ids, version numbers and enum names only.
- Run `npm run db:reset` then `npm run db:test` after each task. All existing pgTAP tests stay green, except the edits to `044` and `052` named in Task 2 and Task 6.
- No commit steps: commits are made by the main session with owner approval.

## Review Focus

Input classes the spec implies but does not pin; each line has a test in the owning task.

1. `p_brief_version` `null`, `0`, an older version, a future version (expect `ES422` for null/`< 1`, `ES409` for any value other than current). Tasks 4 and 5.
2. `editor_confirm_brief` with the right version but a stale deadline, `null` deadline, a different amount, the same amount in another currency, currency `'lkr'` (accepted, upper-cased) (stale/different → `ES409`; malformed currency → `ES422`). Task 5.
3. Project deadline cleared (`null`) after confirmation (expect `deadline_changed = true`, gate not ready, `editor_confirm_brief` `ES409` "This project has no deadline yet."). Task 5.
4. Interpretation text: all three null, only `questions_limitations`, whitespace-only fields (stored null), 4001 characters (all invalid ones `ES422`; at least one of reproduce/adapt required). Task 4.
5. `p_decision` `null`, `'Accept'`, `'reject'` (expect `ES422`); `request_changes` with blank feedback (`ES422`); reviewing an already reviewed row (`ES409`). Task 4.
6. Another editor's or an unknown assignment / interpretation id (expect identical `ES422` messages, no row change). Tasks 3, 4, 5.
7. Editor suspended after confirmation (expect editor functions `ES403`, `admin_start_work` `ES409`, `get_assignment_gate` `ES422` for the editor). Tasks 3 and 5.
8. Two consecutive brief versions: v2 `false` then v3 `false` (two carried rows chained v1→v2→v3); v2 `true` then v3 `false` with no re-confirmation (no carried row for v3, gate needs confirmation); v2 `false` while the assignment is only `accepted` (no row). Task 3.
9. Start twice, start from `accepted`, start on a project `on_hold` (set as postgres), cancelled or archived (expect `ES409`, nothing changed). Task 5.
10. Direct `update public.assignments set status = 'in_progress', started_at = now()` as the table owner without the gate (expect `ES409`), and `update public.projects set status = 'in_progress'` without an `in_progress` assignment (expect `ES409`). Task 3.
11. Concurrency: `editor_confirm_brief` and `admin_save_brief` both lock the project row first; `pg_get_functiondef` of the editor functions and `private.lock_assignment` match `for\s+update`. Task 5.
12. Reassign and cancel from `in_progress`; a fresh offer to the reassigned editor gives a new assignment that needs its own interpretation and confirmation (old rows untouched). Task 6.

## Calls

Places a builder would have to guess, settled with the safest reasonable choice. The owner may override any of them.

1. **`admin_confirm_assignment` is not changed** (spec §4.1, call 1): decision B shows the full brief only after admin confirmation, so interpretation and brief confirmation come after it and `in_progress` is the gated step.
2. **One active editor per project**: `assignments_one_confirmed_key` is dropped and replaced by `assignments_one_active_key on (project_id) where status in ('confirmed','in_progress')`; `assignments_live_key` is recreated with `in_progress` in its predicate. Both recreated in one migration, drop-then-create, no data rewrite (local data has no `in_progress` rows).
3. **Constraint names kept:** `assignments_agreed_chk` and `assignments_confirmed_chk` are dropped and re-added with the same names, widened to `in_progress`; `assignments_started_chk` added.
4. **Gate triggers are `BEFORE UPDATE` only** (spec call 9). An `in_progress` row can be inserted by the table owner (tests); no API role can insert anything.
5. **"Latest confirmation"** = the row with the highest `(brief_version, confirmed_at, id)` for the assignment. Drift flags are computed against it only.
6. **Carry-forward copies** the source row's `confirmed_deadline`, `confirmed_amount`, `confirmed_currency`; `confirmed_deliverables` comes from the new version's snapshot; `created_by` is `new.created_by` of the brief version; `confirmed_at = now()`. It runs only when the source row is for `new.version - 1` (a stale confirmation is never carried). It does not check deadline/pay drift: drift stays visible on the carried row exactly as before.
7. **Interpretation validity:** accepted rows count when their version ≥ `private.material_brief_version(project)`. `admin_review_interpretation(.., 'accept', ..)` is refused (`ES409`) for a row whose version is below the material version; `request_changes` is always allowed on a `submitted` row.
8. **Interpretations need `requires_interpretation = true`** at submission (`ES409` otherwise). If the admin later turns it off, nothing is deleted; the gate stops requiring it.
9. **Editor state checks** for interpretation and confirmation: assignment `confirmed` or `in_progress`; project status `assigned` or `in_progress` and `archived_at is null`. Start: assignment `confirmed`, project `assigned`, not archived.
10. **Start error order:** pay (`"The agreed pay has not been approved yet."`), interpretation (`"Your interpretation needs to be accepted first."`), brief (`"Please confirm the current brief first."`), drift (`"The deadline or pay changed since you confirmed. Please confirm again."`). Admin-start uses the same messages with "the editor" wording.
11. **`get_assignment_gate`**: admin (aal2) or the owning active editor; anyone else signed in gets `ES422` "Assignment not found."; anon `ES401`. Returns one row; read-only (`stable`).
12. **Audit:** `interpretation.<status>` `{interpretation_id, assignment_id, brief_version}`; `brief_confirmation.<kind>` `{confirmation_id, assignment_id, brief_version, carried_from_id}`; written by the functions/trigger, not by a generic table trigger.
13. **`admin_reassign`** from `in_progress` behaves exactly as from `confirmed` (project `assigned` or `in_progress` → `open`); `admin_revoke_project_access` and `admin_withdraw_offer` treat `in_progress` like `confirmed` ("use reassign").
14. **`admin_pending_revocations`**: `no_active_assignment` checks the set (`offered`, `counteroffer_pending`, `accepted`, `confirmed`, `in_progress`). Same signature; `create or replace`.
15. **Cancellation from `in_progress`** via `admin_set_project_status` (function body unchanged; only `private.project_transition_allowed` and `private.close_live_assignments` change). `in_progress` stays refused as a target there. `on_hold` from `assigned`/`in_progress` stays refused.
16. **FKs:** all new `assignment_id`, `brief_version_id`, `project_id`, `editor_id`, `carried_from_id` columns `on delete restrict`; actor columns (`submitted_by`, `reviewed_by`, `created_by`, `started_by`) `on delete set null`, with the append-only exception for clearing them (`private.guard_append_only` cannot express "one review update", so interpretations get their own guard).

## File Structure

| File                                                       | Responsibility                                                                                                   |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/<ts>_phase7_in_progress_enum.sql`     | `alter type public.assignment_status add value 'in_progress' after 'confirmed'` only                             |
| `supabase/migrations/<ts>_phase7_schema.sql`               | new enums, `assignments` columns/constraints/indexes, transition table, two tables, guards, RLS                  |
| `supabase/migrations/<ts>_phase7_gate.sql`                 | `material_brief_version`, `assignment_gate`, `get_assignment_gate`, gate triggers, stage helper, carry-forward   |
| `supabase/migrations/<ts>_phase7_interpretations.sql`      | `editor_submit_interpretation`, `admin_review_interpretation`                                                    |
| `supabase/migrations/<ts>_phase7_confirm_and_start.sql`    | `editor_confirm_brief`, `editor_start_work`, `admin_start_work`                                                  |
| `supabase/migrations/<ts>_phase7_phase6_changes.sql`       | Phase 6/4 replacements for `in_progress` (close, reassign, revoke, withdraw, offer, checklist, transition table) |
| `supabase/tests/database/060`-`066_phase7_*.test.sql`      | pgTAP, see each task                                                                                             |
| `supabase/tests/database/044_*.test.sql`, `052_*.test.sql` | expected matrices updated (Tasks 6 and 2)                                                                        |
| `docs/*`, `src/lib/supabase/database.types.ts`             | updated in Task 8                                                                                                |

Tests reuse the helpers of `054_phase6_offers.test.sql` (`pg_temp.as_user(uid, 'aal2')`, `pg_temp.as_anon()`, `private.grant_admin_by_email`, editors activated as postgres, temp id tables granted to `authenticated`). Identities: admin (aal2), admin aal1, editor A, editor B, suspended S, applicant, anon. UUID prefix `60000000-` for 060, `61000000-` for 061, and so on. Fixture "confirmed assignment" = project opened via `admin_set_project_status`, offer, editor accept, `admin_confirm_assignment` (or seeded directly as postgres where a test is about the schema only).

---

### Task 1: `in_progress` enum value

**Files:**

- Create: `supabase/migrations/<ts>_phase7_in_progress_enum.sql`
- Test: covered by `060_phase7_schema.test.sql` (Task 2)

**Interfaces:**

- Produces: `public.assignment_status` = (`offered`, `counteroffer_pending`, `accepted`, `confirmed`, `in_progress`, `declined`, `withdrawn`, `not_selected`, `reassigned`).

- [ ] **Step 1: Write the failing assertion** at the top of `060_phase7_schema.test.sql`: `enum_has_labels('public', 'assignment_status', array[...the nine labels in that order...])`.
- [ ] **Step 2: Run to verify failure** — `npm run db:test`; 060 fails, and `052` fails on its exact-label check (expected; fixed in Task 2).
- [ ] **Step 3: Implement** the single `alter type` statement; nothing else in the file.
- [ ] **Step 4: Run** `npm run db:reset`; expect the reset to succeed (proves the value is committed before Task 2 uses it).

---

### Task 2: Phase 7 schema

**Files:**

- Create: `supabase/migrations/<ts>_phase7_schema.sql`
- Test: `supabase/tests/database/060_phase7_schema.test.sql`
- Modify: `supabase/tests/database/052_phase6_schema.test.sql` (labels and matrix only)

**Interfaces:**

- Produces enums: `public.interpretation_status` = (`submitted`, `accepted`, `changes_requested`); `public.brief_confirmation_kind` = (`confirmed`, `carried_forward`).
- Produces on `public.assignments`: `started_at timestamptz`, `started_by uuid` FK `profiles` set null (index); constraints `assignments_agreed_chk` (as before with `in_progress` added to the "agreed required" list), `assignments_confirmed_chk check ((status in ('confirmed','in_progress')) <= (confirmed_at is not null))`, `assignments_started_chk check ((status = 'in_progress') <= (started_at is not null))`; index `assignments_live_key` recreated with `in_progress` (Call 2); `assignments_one_confirmed_key` dropped, `assignments_one_active_key` created.
- Produces: `create or replace private.assignment_transition_allowed` — Phase 6 rules plus `confirmed → in_progress`, `in_progress → reassigned | withdrawn` (18 pairs).
- Produces `public.editor_interpretations` — `id uuid pk`, `assignment_id` FK restrict, `brief_version_id` FK `brief_versions` restrict, `will_reproduce text check (1..4000)`, `will_adapt text check (1..4000)`, `questions_limitations text check (1..4000)`, `status public.interpretation_status not null default 'submitted'`, `admin_feedback text check (1..4000)`, `submitted_by` FK `profiles` set null, `submitted_at timestamptz not null default now()`, `reviewed_by` FK `profiles` set null, `reviewed_at timestamptz`, `created_at`. Constraints: `editor_interpretations_content_chk check (num_nonnulls(will_reproduce, will_adapt) >= 1)`; `editor_interpretations_review_chk check ((status = 'submitted') = (reviewed_at is null) and (status <> 'changes_requested' or admin_feedback is not null) and (status <> 'submitted' or (admin_feedback is null and reviewed_by is null)))`. Partial unique index `editor_interpretations_pending_key on (assignment_id) where status = 'submitted'`; indexes on `assignment_id, submitted_at`, `brief_version_id`, `submitted_by`, `reviewed_by`.
- Produces `public.brief_confirmations` — `id uuid pk`, `assignment_id` FK restrict, `project_id` FK `projects` restrict, `editor_id` FK `editor_profiles (user_id)` restrict, `brief_version_id` FK `brief_versions` **on delete restrict**, `brief_version int not null check (>= 1)`, `kind public.brief_confirmation_kind not null`, `carried_from_id uuid` FK `brief_confirmations` restrict, `confirmed_deadline date not null`, `confirmed_deliverables jsonb not null check (jsonb_typeof = 'array')`, `confirmed_amount numeric(12,2) not null check (> 0)`, `confirmed_currency char(3) not null` (regex), `created_by` FK `profiles` set null, `confirmed_at timestamptz not null default now()`. Constraint `brief_confirmations_kind_chk check ((kind = 'carried_forward') = (carried_from_id is not null))`. Partial unique index `brief_confirmations_carried_key on (assignment_id, brief_version_id) where kind = 'carried_forward'`; indexes `(assignment_id, brief_version desc, confirmed_at desc)`, `project_id`, `editor_id`, `brief_version_id`, `carried_from_id`, `created_by`.
- Produces triggers (all `security definer set search_path = ''`, revoked from API roles):
  - `private.check_phase7_row()` BEFORE INSERT on both tables: the brief version belongs to the assignment's project and `brief_version` equals its `version` (confirmations); `project_id`/`editor_id` equal the assignment's (confirmations); else `ES409`.
  - `private.guard_interpretations()` BEFORE UPDATE OR DELETE on `editor_interpretations`: delete `ES409`; update allowed only (a) `old.status = 'submitted'`, new status `accepted|changes_requested`, `reviewed_at` set, and every column except `status, admin_feedback, reviewed_by, reviewed_at` unchanged, or (b) only `submitted_by` or `reviewed_by` cleared to null with everything else unchanged; else `ES409`.
  - `brief_confirmations` uses the existing `private.guard_append_only('created_by')` BEFORE UPDATE OR DELETE.
- Produces policies `editor_interpretations_select` (`admin or exists (select 1 from public.assignments a where a.id = assignment_id and a.editor_id = (select auth.uid())) and (select private.is_active_editor())`) and `brief_confirmations_select` (`admin or (editor_id = (select auth.uid()) and (select private.is_active_editor()))`).

- [ ] **Step 1: Write the failing test** `060_phase7_schema.test.sql`. Enum labels exact (all three enums). Columns and constraint names exist. As postgres on seeded rows: `in_progress` without `started_at` `23514`; `in_progress` without `confirmed_at` or `agreed_amount` `23514`; a `confirmed` and an `in_progress` row on one project `23505`; two `in_progress` rows on one project `23505`; a second live row for (project, editor) where one is `in_progress` `23505`. Interpretations: all content null `23514`; `changes_requested` without feedback `23514`; second `submitted` row for an assignment `23505`, allowed after the first is reviewed; a brief version of another project `ES409` (insert trigger); review update `submitted → accepted` with `reviewed_at` succeeds; then any update (status back, content, feedback) `ES409`; content change on a `submitted` row `ES409`; delete `ES409`; clearing only `submitted_by` succeeds; clearing it with another column `ES409`. Confirmations: `carried_forward` without `carried_from_id` and `confirmed` with it `23514`; mismatched `project_id`/`editor_id`/`brief_version` `ES409`; update of any column and delete `ES409`; clearing only `created_by` succeeds; deleting the referenced `brief_versions` row is refused (its own guard `ES409`, and with that trigger disabled in a savepoint the FK raises `23503`); second carried row for the same (assignment, version) `23505`. Visibility per table: anon `42501`; editor A sees own rows only; B, S, applicant, admin aal1 see 0; admin aal2 all; direct insert/update/delete as admin aal2 and as A `42501`.
- Update 052: label list gains `in_progress`; matrix insert sets `confirmed_at` for `('confirmed','in_progress','reassigned')` and `started_at` for `in_progress`; the update in `try_matrix` sets `confirmed_at` for `to_s in ('confirmed','in_progress','reassigned')` and `started_at = case when r.to_s = 'in_progress' then now() end` (keeping it on `in_progress → reassigned|withdrawn` is not required by any constraint); expected list gains `in_progress>reassigned`, `in_progress>withdrawn`, `in_progress>in_progress` and does **not** contain `confirmed>in_progress` (the Task 3 gate refuses it without a confirmation; asserted positively in 064); description becomes "over all 81 pairs". (Task 3 lands the gate trigger; until then `confirmed>in_progress` succeeds, so run 052 green only after Task 3; note this in the step.)

- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement** the migration (drop/re-add constraints and indexes in one file; `create or replace` the transition function and re-issue its revoke).
- [ ] **Step 4: Run `npm run db:reset && npm run db:test`;** 060 green; 052 green except the `confirmed>in_progress` cell, which turns green after Task 3.

---

### Task 3: Gate, stage helper, gate triggers and carry-forward

**Files:**

- Create: `supabase/migrations/<ts>_phase7_gate.sql`
- Test: `supabase/tests/database/061_phase7_gate.test.sql`

**Interfaces:**

- Consumes: `private.require_user()`, `private.is_admin()`, `private.is_active_editor()`, tables from Task 2.
- Produces (private, no API grant unless stated):
  - `private.material_brief_version(p_project_id uuid) returns int` — sql stable: `max(version) filter (where version = 1 or requires_reacknowledgement)`.
  - `private.latest_confirmation(p_assignment_id uuid) returns public.brief_confirmations` — Call 5.
  - `private.assignment_gate(p_assignment_id uuid) returns table (compensation_approved boolean, interpretation_required boolean, interpretation_accepted boolean, current_brief_version int, confirmed_brief_version int, reacknowledgement_required boolean, deadline_changed boolean, amount_changed boolean, deliverables_changed boolean, brief_confirmed boolean, ready boolean)` — plpgsql stable security definer; definitions per spec §7; unknown id returns no row.
  - `private.guard_assignment_start()` BEFORE UPDATE on `assignments`: when `new.status = 'in_progress' and old.status <> 'in_progress'`, raise `ES409` (Call 10 messages) unless `(select ready from private.assignment_gate(new.id))`. Runs in addition to `assignments_guard`.
  - `private.guard_project_in_progress()` BEFORE UPDATE OF status on `projects`: when `new.status = 'in_progress' and old.status <> 'in_progress'`, `ES409` "A project starts only when its editor starts work." unless an assignment on the project has status `in_progress`.
  - `create or replace private.editor_project_stage(uuid)` — `assigned` when the caller's assignment is `confirmed` **or** `in_progress`; otherwise unchanged. Grant pattern per Global Constraints.
  - `private.carry_forward_confirmations()` AFTER INSERT on `brief_versions` — spec §8 / Call 6; audit `brief_confirmation.carried_forward` per row.
- Produces (public): `public.get_assignment_gate(p_assignment_id uuid) returns table (...same columns...)` — `require_user()`; Call 11.

- [ ] **Step 1: Write the failing test** `061_phase7_gate.test.sql`. Fixtures as postgres: opened project P (deadline `2026-12-31`, v1), A `confirmed` with agreed 10000 LKR; P2 with `requires_interpretation`; B on another project. Gate cells (`results_eq` on the gate row): no confirmation → `reacknowledgement_required`, not ready; confirmation row for v1 matching deadline and amount → `brief_confirmed`, ready; P2 without accepted interpretation → not ready, with an accepted v1 interpretation → ready; `accepted` assignment (not confirmed) → `compensation_approved = false`; deadline changed as postgres → `deadline_changed`, not ready; agreed amount changed as postgres (seeded) → `amount_changed`; deliverables in a new v2 (`requires_reacknowledgement = true`) → `reacknowledgement_required` and `deliverables_changed`; interpretation accepted for v1 then v2 with `true` → `interpretation_accepted = false`; v2 with `false` → still true. Review Focus 8: three chains as listed (row counts, `carried_from_id`, versions, copied deadline/amount, deliverables from the new snapshot, `kind = 'carried_forward'`, audit rows with exactly the keys `confirmation_id, assignment_id, brief_version, carried_from_id`). Review Focus 10: both direct updates `ES409`; with the gate met, `update assignments set status = 'in_progress', started_at = now()` succeeds, then `update projects set status = 'in_progress'` succeeds. Stage: A `assigned` while `in_progress` (sees `brief_versions`, all references and assets); B `none`. `get_assignment_gate`: admin aal2 and A get the row; B, S, applicant, admin aal1 `ES422`; anon `ES401`; Review Focus 7 (A suspended → `ES422`). `has_function_privilege` checks: `private.assignment_gate`, `material_brief_version`, `latest_confirmation`, trigger functions not executable by `anon`/`authenticated`; `editor_project_stage` executable by `authenticated` only. Re-run 052 and expect it fully green.

- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement.** Keep the gate the only place that encodes the rule; triggers and functions call it.
- [ ] **Step 4: Run `npm run db:reset && npm run db:test`; expect pass**, including 052, 053 (stage unchanged for non-`in_progress` cases) and 046 (catalogue).

---

### Task 4: Interpretations

**Files:**

- Create: `supabase/migrations/<ts>_phase7_interpretations.sql`
- Test: `supabase/tests/database/062_phase7_interpretations.test.sql`

**Interfaces:**

- Consumes: `private.require_active_editor()`, `private.require_admin()`, `private.lock_assignment`, `private.clean_text` (Phases 5–6), `private.material_brief_version` (Task 3).
- Produces:
  - `public.editor_submit_interpretation(p_assignment_id uuid, p_brief_version int, p_will_reproduce text, p_will_adapt text, p_questions text default null) returns uuid` — ownership check (Global Constraints); `lock_assignment`; Call 9 states; `requires_interpretation` (Call 8); `p_brief_version` check (Review Focus 1); texts via `clean_text(.., 4000, ..)`, at least one of reproduce/adapt (`ES422`); pending row `ES409` "Your interpretation is waiting for review."; valid accepted row `ES409` "Your interpretation has already been accepted."; inserts with `brief_version_id` of the current version, `submitted_by`; audit `interpretation.submitted`.
  - `public.admin_review_interpretation(p_interpretation_id uuid, p_decision text, p_feedback text default null) returns void` — `p_decision` in (`accept`, `request_changes`) else `ES422`; unknown id `ES422`; locks project then assignment (via `lock_assignment` on the row's assignment) then the interpretation row; only `submitted` (`ES409`); assignment must be `confirmed`/`in_progress` (`ES409`); Call 7; feedback via `clean_text(.., 4000, ..)`, required for `request_changes`; sets `status`, `admin_feedback`, `reviewed_by`, `reviewed_at`; audit `interpretation.accepted` / `interpretation.changes_requested`.

- [ ] **Step 1: Write the failing test** `062_phase7_interpretations.test.sql`. Driven through the Phase 6 functions to a confirmed A on project P (`requires_interpretation = true`). A submits → row `submitted`, version = current, audit row without text; second submit `ES409`; admin `request_changes` with feedback → `changes_requested`, A reads the feedback through RLS; A resubmits → new row, old row unchanged; admin accepts → gate `interpretation_accepted`; further submit `ES409`. Review Focus 1, 4, 5, 6 (B with A's assignment id and a random uuid: same message; admin with a random interpretation id `ES422`). Project without `requires_interpretation` `ES409`. Assignment `accepted` (not confirmed) `ES409`; project archived `ES409`. Stale acceptance: submit at v1, admin saves v2 with `requires_reacknowledgement = true`, accept → `ES409`, `request_changes` succeeds; with v2 `false` instead, accept succeeds. Suspended A `ES403`. Every function: anon `ES401`; editor calling admin function and admin calling editor function `ES403`; admin aal1, applicant `ES403`. Direct `update public.editor_interpretations set status = 'accepted'` as A `42501`.

- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement** both functions with the revoke/grant lines.
- [ ] **Step 4: Run `npm run db:reset && npm run db:test`; expect pass.**

---

### Task 5: Brief confirmation and start

**Files:**

- Create: `supabase/migrations/<ts>_phase7_confirm_and_start.sql`
- Test: `supabase/tests/database/063_phase7_confirm.test.sql`, `supabase/tests/database/064_phase7_start.test.sql`

**Interfaces:**

- Consumes: Task 3 gate, `private.lock_assignment`, `private.check_amount`, `private.check_currency` (Phase 6).
- Produces:
  - `public.editor_confirm_brief(p_assignment_id uuid, p_brief_version int, p_deadline date, p_amount numeric, p_currency text) returns uuid` — ownership check; `lock_assignment`; Call 9 states; Review Focus 1–3 (all four inputs required, `ES422` when null/malformed; mismatch `ES409` "The brief, deadline or pay changed while you were reviewing. Please review it again."); project deadline null `ES409`; required interpretation not accepted `ES409`; gate already `brief_confirmed` `ES409` "You have already confirmed this brief."; inserts `kind = 'confirmed'` with copies from the current `brief_versions` row, `projects.deadline`, `agreed_amount`/`agreed_currency`, `created_by = uid`; audit `brief_confirmation.confirmed`.
  - `public.editor_start_work(p_assignment_id uuid) returns void` — ownership check; `lock_assignment`; assignment `confirmed`, project `assigned`, not archived (`ES409`); gate `ready` else Call 10 message; `update assignments set status = 'in_progress', started_at = now(), started_by = uid`, then `update projects set status = 'in_progress'`.
  - `public.admin_start_work(p_assignment_id uuid) returns void` — `require_admin()`; `lock_assignment` (unknown `ES422`); same checks plus editor `access_status = 'active'` (`ES409`); `started_by = admin`.

- [ ] **Step 1: Write the failing tests.**
  - `063_phase7_confirm.test.sql`: A confirms v1 with the displayed values → one `confirmed` row with exact copies (version id, version, deadline, deliverables equal to `brief_versions.deliverables`, amount, currency, `created_by = A`), gate `brief_confirmed`; repeat `ES409`; Review Focus 1–3, 6, 7; admin saves v2 `false` → carried row, gate still confirmed; admin saves v3 `true` → gate `reacknowledgement_required`, A confirms v3 → new row; admin moves the deadline → `deadline_changed`, A confirms again (same version) → new row, gate clear; P with `requires_interpretation` and no accepted interpretation → `ES409`; after acceptance → succeeds; assignment `accepted` or project archived `ES409`; confirming during `in_progress` (after Task 5 start) allowed; B sees none of A's rows; audit details have no amount, deadline or deliverable text. Review Focus 11 (`for\s+update` in `private.lock_assignment` and in a second session-free check that the function calls it: `prosrc ~ 'private\.lock_assignment'`).
  - `064_phase7_start.test.sql`: Review Focus 9; start before confirmation, before interpretation acceptance, with deadline drift, each `ES409` with the Call 10 message order (assert messages with `throws_ok(.., 'ES409', '<message>')`); happy path editor start → assignment `in_progress` with `started_by = A`, project `in_progress`, audit rows `assignment.in_progress` and `project.in_progress`; admin start on a second project → `started_by = admin`; admin start with A suspended `ES409`; editor start by B with A's id `ES422`; `admin_set_project_status(.., 'in_progress')` `ES409`; after start: admin saves a `true` version → gate not ready, assignment stays `in_progress` (spec call 7); every function: anon `ES401`, wrong role `ES403`; direct `update ... set status = 'in_progress'` as A `42501`.

- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement** the three functions with revoke/grant lines.
- [ ] **Step 4: Run `npm run db:reset && npm run db:test`; expect pass.**

---

### Task 6: Phase 6 and Phase 4 replacements for `in_progress`

**Files:**

- Create: `supabase/migrations/<ts>_phase7_phase6_changes.sql`
- Test: `supabase/tests/database/065_phase7_phase6_changes.test.sql`
- Modify: `supabase/tests/database/044_phase4_status.test.sql` (expected list gains `in_progress>cancelled`; nothing else)

**Interfaces:**

- Produces (`create or replace`, same signatures, same revoke/grant lines as the originals):
  - `private.close_live_assignments(...)` — `withdrawn` also closes `in_progress`.
  - `private.project_transition_allowed(...)` — adds `when p_from = 'in_progress' then p_to = 'cancelled'`.
  - `public.admin_reassign(uuid, text)` — Call 13.
  - `public.admin_revoke_project_access(uuid, uuid)`, `public.admin_withdraw_offer(uuid, text)` — Call 13.
  - `public.admin_make_offer(uuid, uuid, numeric, text, text)` — live set includes `in_progress`.
  - `public.admin_pending_revocations()` — Call 14.
- Each replacement is a copy of the migrated body with only the status lists changed; diff it against `20261114062924_phase6_admin_negotiation.sql` / `20261114063650_phase6_project_status_changes.sql` in review.

- [ ] **Step 1: Write the failing test** `065_phase7_phase6_changes.test.sql`. With A `in_progress` on P: `admin_withdraw_offer` and `admin_revoke_project_access` `ES409` ("use reassign"); `admin_make_offer` to A `ES409` (project not open anyway; also on a seeded open project with A `in_progress`, `ES409` live offer); `admin_reassign` → A `reassigned`, `closed_at`, `withdraw` row with message, project `open`, A's access revoked, A's stage `none`, A's interpretation and confirmation rows unchanged and still readable by admin; Review Focus 12 (new offer → accept → confirm creates a second assignment whose gate shows no confirmation and, with `requires_interpretation`, no accepted interpretation). Cancel from `in_progress` → project `cancelled`, A `withdrawn` with an admin `withdraw` row, access revoked; `on_hold` from `in_progress` `ES409`. Checklist: a live grant for an `in_progress` editor is absent; after reassignment it is listed as `no_active_assignment`. Update 044's expected list.
- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `npm run db:reset && npm run db:test`; expect pass**, including 044, 054–057.

---

### Task 7: Function-security and data-hygiene tests for Phase 7

**Files:**

- Test: `supabase/tests/database/066_phase7_function_security.test.sql`

**Interfaces:**

- Consumes everything above; produces guardrails only.

- [ ] **Step 1: Write the test.** New public functions exist and are executable by `anon` and `authenticated`: `editor_submit_interpretation(uuid, int, text, text, text)`, `admin_review_interpretation(uuid, text, text)`, `editor_confirm_brief(uuid, int, date, numeric, text)`, `editor_start_work(uuid)`, `admin_start_work(uuid)`, `get_assignment_gate(uuid)`, plus the six replaced ones; `prosrc` of `admin_*` contains `private.require_admin()`, of `editor_*` `private.require_active_editor()`, of `get_assignment_gate` `private.require_user()`. Every new private helper and trigger function: security definer, `search_path=""`, no API grantee. Data hygiene: no column matching `client|email|phone|company|contact|price` on `editor_interpretations` or `brief_confirmations`; all policies on both tables `cmd = 'SELECT'`. Triggers present by name: `guard_assignment_start` on `assignments`, `guard_project_in_progress` on `projects`, `carry_forward_confirmations` on `brief_versions`, append-only guards on both new tables. Audit: one full flow (offer, accept, confirm, interpretation submit/changes/accept, brief confirm, v2 `false`, start, v3 `true`, re-confirm, reassign) and assert actions `interpretation.%`, `brief_confirmation.%`, `assignment.in_progress`, `project.in_progress` exist and none has keys `amount`, `confirmed_amount`, `deadline`, `feedback`, `will_reproduce`, `deliverables` or `details::text` containing the amount, the deadline or any interpretation text used.
- [ ] **Step 2: Run `npm run db:test`.** Fix any failure in its own uncommitted migration (or a new one if committed).

---

### Task 8: Docs, types, advisors and security review

**Files:**

- Modify: `docs/DATABASE_SCHEMA.md` (two tables and `assignments` changes as built), `docs/SECURITY_AND_PRIVACY.md` (access matrix rows; gate described), `docs/WORKFLOWS.md` (§3 actual order with the decision B reasoning; assignment lifecycle with `in_progress`; re-acknowledgement and drift), `docs/BUSINESS_RULES.md` (only if compensation wording conflicts), `docs/DEVELOPMENT_ROADMAP.md`, `docs/CURRENT_STATUS.md`, `docs/CHANGELOG.md`, `src/lib/supabase/database.types.ts` (generated).

- [ ] **Step 1:** `npm run db:types`; confirm the diff adds only the new enums, enum value, columns, tables and functions.
- [ ] **Step 2:** `npm run db:advisors`; expect no new security warnings.
- [ ] **Step 3:** Update the docs (spec calls and plan calls recorded as awaiting owner review; the order call and the drift call flagged at the top of `CURRENT_STATUS.md`). Do not edit `EDITSTATION_MASTER_KNOWLEDGE_BASE.md`; do not decide F or KB5.
- [ ] **Step 4:** `npm run check` and `npm run db:test`; both green.
- [ ] **Step 5:** Dispatch the `db-security` agent over the six migrations, tests 060–066 and the 044/052 edits; fix findings with tests; re-run Step 4.

---

## Self-review notes

Spec coverage: enum value (§5) Task 1; schema, immutability and RLS (§5, §6) Task 2; gate, stage, triggers and carry-forward (§7, §8 trigger) Task 3; interpretation functions (§8) Task 4; confirmation and start (§8, §9) Task 5; Phase 6/4 replacements (§8, §9 reassign/cancel) Task 6; function security and hygiene (§10) Task 7; docs Task 8. §11 screens and derived labels are app-side (screens plan). Every §10 test class maps to a task: constraints and immutability (060), visibility and suspension (060, 061), stage for `in_progress` (061), gate fields (061), transitions and refusals (062–065), carry-forward vs re-acknowledgement (061, 063), drift (061, 063, 064), optimistic checks (063), trigger enforcement (061), reassign/cancel (065), matrices (044, 052), catalogue and hygiene (066). Phase 8 must call `private.assignment_gate(..).ready` before accepting a submission (spec §7).
