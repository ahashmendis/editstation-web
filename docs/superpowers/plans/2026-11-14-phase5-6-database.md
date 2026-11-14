# Phases 5–6 Database Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Phase 5 (assets, early access, folder-share log) and Phase 6 (project access, offers, negotiation, assignments, admin notes, editor visibility) database layer, with function-only writes, tiered editor RLS, and full pgTAP coverage.

**Architecture:** New tables with `select`-only grants and no write policies. Admin writes are `public.admin_*` security-definer functions that call `private.require_admin()` first; editor writes are `public.editor_*` functions that call a new `private.require_active_editor()` first. Editor reads go through new `for select to authenticated` policies on the base tables, filtered by `private.editor_project_stage(project_id)` (`none` / `opportunity` / `assigned`). Assignment status transitions are enforced twice: in the functions and by a guard trigger. Delivered as seven small append-only migrations, one per schema/function task.

**Tech Stack:** Postgres (Supabase local, CLI pinned 2.122.1), pgTAP, plpgsql. No application code in this plan: the admin and editor screens are a separate plan written after this layer is reviewed.

**Spec:** `docs/superpowers/specs/2026-11-14-phase5-6-editor-access-design.md` (draft under the owner's standing instruction of 2026-11-14; implements decisions B, C, K, KB6). Section numbers below (§) refer to it. Plan calls beyond the spec are listed under **Calls** and flagged `(call)` where used.

## Global Constraints

- RLS enabled on every new table; `revoke all ... from anon, authenticated`, then only `grant select ... to authenticated` plus an admin-only policy `using ((select private.is_admin()))`. Editor policies are added only in Task 4. No insert/update/delete grant or policy anywhere.
- Every `public.admin_*` / `public.editor_*` function: `language plpgsql security definer set search_path = ''`, first statement `private.require_admin()` (admin) or `private.require_active_editor()` (editor), then `revoke all on function <sig> from public, anon, authenticated;` followed by `grant execute on function <sig> to anon, authenticated;`. Every `private.*` function and trigger function: `revoke all ... from public, anon, authenticated;` and no grant, except `private.editor_project_stage(uuid)`, which RLS policies call as the API role: `grant execute ... to authenticated` only (a missing EXECUTE in a policy crashes this Postgres image; see `20261114060306_revoke_public_function_execute.sql`).
- Errors only `ES401`/`ES403` (from `require_admin` / `require_active_editor`), `ES409` (state conflict), `ES422` (invalid input); never `42501`. Messages are user-safe plain sentences. Wrap `check_violation` into `ES422` with the Phase 4 pattern (`exception when check_violation then raise ... using errcode = 'ES422'`).
- Money: `numeric(12,2)` with a sibling `char(3)` currency, `check (currency ~ '^[A-Z]{3}$')`, default `'LKR'`. Amounts never appear in `activity_logs`.
- Links: `check (url ~ '^https://[^\s]+$' and char_length(url) <= 2048)`, same as `project_references.url`.
- Emails (folder shares): stored as `lower(btrim(email))`, enforced by a check constraint identical to `clients.email`.
- Lock order in every function that touches an assignment: the `projects` row `for update` first, then the `assignments` row `for update` (via `private.lock_assignment`). No function locks in the other order.
- Never edit an applied (committed) migration; new migrations via `npx supabase migration new <name>`. Local database only; no `link`/`db push`. Changes to Phase 4 functions are `create or replace` in a new migration.
- Audit rows go to `public.activity_logs (actor_id, action, entity_type, entity_id, details)`; `details` holds ids and status/enum names only: no amounts, messages, emails, titles, URLs or note text.
- Run `npm run db:reset` then `npm run db:test` after each task. All existing pgTAP tests (472 at the start of this plan) stay green, except the two Phase 4 test edits named in Tasks 4 and 7.
- No commit steps: commits are made by the main session with owner approval.

## Review Focus

Input classes the spec implies but does not pin; each line has a test in the owning task.

1. `admin_save_assets` `p_items` that is `null`, `{}`, a string, contains a non-object, unknown keys (ignored), more than 100 items, an `http://` URL, a foreign or duplicated `id` (expect `ES422`; `null`/`[]` clear the list). Task 2.
2. Folder-share email with mixed case and padding (`'  Editor@Drive.COM '`) matching a live grant (expect `ES409`); the same email after revoking (expect a new grant). Task 2.
3. Amounts `0`, negative, three decimals, `10000000000`, `null`; currency `'lkr'` (accepted, upper-cased), `'LK'`, and a counter in a different currency from the offer (all invalid ones `ES422`). Tasks 5 and 6.
4. `p_editor_ids` that is `null`, empty, has duplicates, or contains an unknown, non-active or the calling admin's own id (expect `ES422` and nothing granted: all-or-nothing). Task 5.
5. Two accepted editors and two confirm calls on one project (expect one `confirmed`, the other `not_selected`, second confirm `ES409`; `for update` present in `prosrc`; partial unique index rejects a second confirmed row). Task 5.
6. An editor passing another editor's assignment id, or a non-existent id (expect the same `ES422` "Offer not found." for both: no existence leak). Task 6.
7. Editor suspended between offer and response (expect `editor_respond_offer` `ES403`, `admin_confirm_assignment` `ES409`, grant listed by `admin_pending_revocations`). Tasks 5 and 6.
8. Offer to an editor who already has a live assignment on the project (expect `ES409`, or re-offer when `counteroffer_pending`); offer after a terminal state (expect a new assignment row, old row unchanged). Task 5.
9. `p_action` `null`, wrong case or unknown (expect `ES422`). Tasks 5 and 6.
10. Messages over 2000 characters (`ES422`) and whitespace-only (stored as `null`). Task 5.
11. Project `on_hold` during negotiation (expect offer, confirm and editor response `ES409`; editor stage stays `opportunity`). Tasks 4, 5 and 6.
12. Archived project with a confirmed editor (expect stage `none`, nothing visible; restoring brings it back). Task 4.

## Calls

Places a builder would have to guess, settled with the safest reasonable choice. The owner may override any of them.

1. **One plan, two phases.** Tasks 1–2 are Phase 5, Tasks 3–7 Phase 6; Tasks 8–9 cover both.
2. **Phase 5 cannot reference Phase 6 tables.** `admin_pending_revocations` ships in Task 2 with two reasons (`editor_not_active`, `project_closed`) and is `create or replace`d in Task 5 to add `no_active_assignment`. `admin_record_asset_grant` requires only an active editor (no access/assignment check), in both phases; the checklist catches stale shares.
3. **`no_active_assignment` is literal to §7:** a live grant is listed when the editor has no assignment on the project in (`offered`, `counteroffer_pending`, `accepted`, `confirmed`), even if they still hold live `project_access`. False positives are cheap; missed revocations are not. One row per grant, first matching reason in the order `editor_not_active`, `project_closed`, `no_active_assignment`.
4. **Stage is `none` for cancelled or archived projects in every case**, including a confirmed editor (§6 says this only for `opportunity`). Restoring an archived project restores visibility. Archiving does not touch assignments.
5. **`brief_versions` at stage `assigned`: all versions** of the project, not only the current one (needed for re-acknowledgement in Phase 7).
6. **Editor policies on `assignments`, `negotiation_offers` and `project_access` all require `private.is_active_editor()`**, so a suspended editor loses even their own history.
7. **`admin_save_assets` does not read or write `early_access`**; new rows get `false`; toggles go through the two setters only. Asset `kind` is free text 1–40 (the §5 list is a UI suggestion). Missing `provider` defaults to `other`. Cap 100 assets per call. Returns `void`.
8. **`early_access` is not part of `private.brief_snapshot` or `private.sync_brief_rows`**, so toggling it never creates a brief version; a reference deleted and re-added by `admin_save_brief` comes back with `early_access = false`.
9. **Writes refused on cancelled or archived projects:** `admin_save_assets`, both early-access setters, `admin_record_asset_grant` (`ES409`). Always allowed: `admin_revoke_asset_grant`, `admin_revoke_project_access`, `admin_withdraw_offer`, `admin_add_project_note`.
10. **Offers, counters, responses and confirmation need the project in status `open` and not archived** (`ES409`); `on_hold` blocks them but keeps live rows and the editor's `opportunity` stage.
11. **Pay:** `p_amount` is required and must be `> 0` for offers and counters (an explicit agreed amount, §1); at most 2 decimals; `<= 9999999999.99`. `p_currency` `null` means the project's `proposed_currency` on a new offer and the assignment's currency afterwards; one currency per assignment (a counter in another currency is `ES422`; change currency by withdrawing and offering again). An editor counter equal to the current offer is `ES422` ("accept instead"). No cap on counter rounds.
12. **Accept** (by editor from `offered`, by admin from `counteroffer_pending`) copies `proposed_amount`/`currency` into `agreed_amount`/`agreed_currency`; `p_amount` and `p_currency` are ignored for `accept` and `decline`. The `accept` negotiation row carries the agreed amount; `decline` and `withdraw` rows have `amount` and `currency` null.
13. **Confirmation revokes every other live `project_access` row on the project** (invited-only editors included), not only those with assignments; otherwise invited editors would keep seeing an assigned project. Other live assignments become `not_selected` with no negotiation row (activity log only). The confirmed editor must still be active (`ES409`).
14. **Reassign** requires project status `assigned`; sets the project back to `open` directly (not via `admin_set_project_status`); revokes only that editor's access; earlier revoked editors are not restored. `p_message` is stored as an admin `withdraw` negotiation row so the editor sees the reason.
15. **Cancellation from any allowed status (`draft`, `open`, `assigned`)** closes every live assignment as `withdrawn` (admin `withdraw` negotiation row, message null) and revokes every live `project_access` row. `on_hold` from `assigned` stays refused.
16. **`open → draft` is refused when any `project_access` row or assignment exists for the project, revoked or closed ones included** (an editor has seen it).
17. **`admin_grant_project_access`** is all-or-nothing, dedups ids, caps at 100 ids, refuses the calling admin's own id, leaves an existing live row (and its `reason`) unchanged, and returns the number of rows newly granted.
18. **`admin_revoke_project_access`** with no live access and no live assignment is `ES409`; with a confirmed assignment it is `ES409` ("use reassign").
19. **`admin_make_offer`** creates a live `project_access` row (`invited`) if missing; refuses `p_editor_id` equal to the caller (`ES422`); on `counteroffer_pending` behaves exactly like `admin_respond_counter(..., 'counter', ...)`; on `offered`/`accepted`/`confirmed` is `ES409`.
20. **Not-own assignment = not found.** Editor functions raise `ES422` "Offer not found." for another editor's id and for an unknown id.
21. **Enums added beyond §5:** `public.negotiation_role` (`admin`, `editor`) and `public.negotiation_action` (`offer`, `counter`, `accept`, `decline`, `withdraw`). `p_action` parameters are `text` validated in the body (so a bad value is `ES422`, not `22P02`).
22. **Guard triggers** (`BEFORE UPDATE` only, so tests can seed any status as postgres): `assignments.project_id`/`editor_id` immutable and status changes must pass `private.assignment_transition_allowed`; `negotiation_offers` and `project_notes` are append-only except clearing `created_by`/`author_id` with every other column unchanged (the `on delete set null` case fixed for `activity_logs` in Phase 2).
23. **Foreign keys:** `editor_id` columns reference `editor_profiles (user_id)` `on delete restrict` (account deletion and retention stay question P); `project_id` `on delete restrict` except `project_assets` (`cascade`, like deliverables); actor columns (`granted_by`, `shared_by`, `created_by`, ...) reference `profiles (id)` `on delete set null`.
24. **Audit actions:** `project.assets_changed`, `project.early_access_changed`, `asset_grant.recorded`, `asset_grant.revoked`, `project_access.granted`, `project_access.revoked`, `assignment.<status>` (trigger, on insert and status change), `project.note_added`. Project status changes keep using the Phase 4 `projects_audit` trigger (`project.assigned`, `project.open`, `project.cancelled`).
25. **Notes** are allowed on any project, archived and cancelled included, and return the note id.

## File Structure

| File                                                         | Responsibility                                                                                                  |
| ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/<ts>_phase5_assets_schema.sql`          | `asset_provider`, `project_assets`, `project_references.early_access`, `asset_access_grants`, admin RLS         |
| `supabase/migrations/<ts>_phase5_assets_functions.sql`       | Phase 5 helpers, asset sync, early-access setters, grant record/revoke, `admin_pending_revocations` (v1)        |
| `supabase/migrations/<ts>_phase6_access_schema.sql`          | Phase 6 enums, `project_access`, `assignments`, `negotiation_offers`, `project_notes`, guard and audit triggers |
| `supabase/migrations/<ts>_phase6_editor_visibility.sql`      | `require_active_editor`, `editor_project_stage`, editor select policies                                         |
| `supabase/migrations/<ts>_phase6_admin_negotiation.sql`      | Phase 6 helpers, admin access/offer/negotiation/confirm/reassign/withdraw/revoke/note functions, checklist v2   |
| `supabase/migrations/<ts>_phase6_editor_respond.sql`         | `editor_respond_offer`                                                                                          |
| `supabase/migrations/<ts>_phase6_project_status_changes.sql` | `project_transition_allowed` and `admin_set_project_status` replaced                                            |
| `supabase/tests/database/050`-`058_phase5_6_*.test.sql`      | pgTAP, see each task                                                                                            |
| `supabase/tests/database/044_*.test.sql`, `046_*.test.sql`   | expected-transition list (Task 7) and RLS-helper allow-list (Task 4) updated                                    |
| `docs/*`, `src/lib/supabase/database.types.ts`               | updated in Task 9                                                                                               |

Use timestamps after `20261114060306`. Add tests with the same helpers as `044_phase4_status.test.sql` (`pg_temp.as_user(uid, 'aal2')`, `pg_temp.as_anon()`, `private.grant_admin_by_email(email, 'test')`, editors activated with `update public.editor_profiles set access_status = 'active' where user_id in (...)` as postgres, temp id tables granted to `authenticated`). Identities: admin (aal2), admin at aal1, editor A, editor B, suspended editor S (`access_status = 'suspended'`), pending applicant (default `none`), anon. UUID prefix `5X000000-...` per file (`50000000-` for 050, `51000000-` for 051, ...). Fixture projects for tests before Task 5 are seeded directly as postgres (status, `first_opened_at`, assignments in any status).

---

### Task 1: Phase 5 schema

**Files:**

- Create: `supabase/migrations/<ts>_phase5_assets_schema.sql`
- Test: `supabase/tests/database/050_phase5_schema.test.sql`

**Interfaces:**

- Produces: enum `public.asset_provider` = (`google_drive`, `dropbox`, `other`).
- Produces: `public.project_assets` — `id uuid pk default gen_random_uuid()`, `project_id uuid not null` FK `projects` `on delete cascade`, `label text not null check (1..200)`, `url text not null` (https check), `provider public.asset_provider not null default 'other'`, `kind text check (1..40)`, `notes text check (1..2000)`, `early_access boolean not null default false`, `sort_order int not null default 0`, `created_at`, `updated_at` (+ `private.set_updated_at()` trigger). Index `(project_id, sort_order)`.
- Produces: `public.project_references.early_access boolean not null default false`.
- Produces: `public.asset_access_grants` — `id uuid pk`, `project_id uuid not null` FK `projects` restrict, `editor_id uuid not null` FK `editor_profiles (user_id)` restrict, `shared_with_email text not null` (check: `= lower(btrim(...))`, `<= 254`, `~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'`), `provider public.asset_provider not null`, `folder_url text` (https check when not null), `shared_by uuid` FK `profiles` set null, `shared_at timestamptz not null default now()`, `revoked_by uuid` FK `profiles` set null, `revoked_at timestamptz`, `revoke_reason text check (1..500)`, `created_at`, `updated_at`; constraint `asset_access_grants_revoke_chk check (revoked_at is not null or (revoked_by is null and revoke_reason is null))`. Partial unique index `asset_access_grants_live_key on (project_id, editor_id, shared_with_email) where revoked_at is null`; indexes on `editor_id`, `shared_by`, `revoked_by`.
- Produces: policies `project_assets_select_admin`, `asset_access_grants_select_admin` (`using ((select private.is_admin()))`).

- [ ] **Step 1: Write the failing test** `050_phase5_schema.test.sql`. Assertions: `has_column('public', 'project_references', 'early_access')` with default `false`; `has_type('public', 'asset_provider')` and `enum_has_labels` exactly the three values; for `project_assets` and `asset_access_grants`: anon `throws_ok(..., '42501')` on select; editor A, editor B, suspended S and applicant `is(count, 0)` after postgres seeds one row each; admin aal2 sees 1; admin aal1 sees 0; direct `insert`, `update`, `delete` as admin aal2 throw `42501`. Constraints (as postgres): `project_assets.url = 'http://x'` and a 201-char label rejected (`23514`); `kind` of 41 chars rejected; `asset_access_grants.shared_with_email = ' A@B.com'` rejected; second live grant with the same (project, editor, email) violates `23505`; succeeds once the first has `revoked_at` set; `revoke_reason` without `revoked_at` rejected; deleting a project cascades its assets.

- [ ] **Step 2: Run to verify failure** — `npm run db:test`; expect failures for missing relations.

- [ ] **Step 3: Implement the migration** per §5 Phase 5 and the Interfaces above. `alter table public.project_references add column early_access boolean not null default false` (no data change needed). RLS, `revoke all ... from anon, authenticated`, `grant select ... to authenticated`, admin policies.

- [ ] **Step 4: Run to verify pass** — `npm run db:reset && npm run db:test`; expect 050 and `000_rls_guardrail` green, all Phase 1–4 files unchanged.

---

### Task 2: Phase 5 functions

**Files:**

- Create: `supabase/migrations/<ts>_phase5_assets_functions.sql`
- Test: `supabase/tests/database/051_phase5_functions.test.sql`

**Interfaces:**

- Consumes: `private.require_admin()`, `private.jsonb_text`, `private.jsonb_int`, `private.jsonb_uuid` (Phase 4), `private.is_active_editor()` semantics via `editor_profiles.access_status`.
- Produces (all `private`, security definer, no API grants):
  - `private.lock_writable_project(p_project_id uuid) returns public.projects` — `select ... for update`; `ES422` "Project not found."; `ES409` when `status = 'cancelled'` or `archived_at is not null`.
  - `private.clean_text(p_value text, p_max int, p_label text) returns text` — trims `E' \t\r\n'`, empty to null, longer than `p_max` → `ES422`.
  - `private.normalise_email(p_email text) returns text` — `lower(btrim())`, `ES422` unless it matches the `clients.email` rule.
  - `private.parse_assets(p_items jsonb) returns jsonb` — null/JSON null → `[]`; non-array `ES422`; > 100 items `ES422`; item keys `id, label, url, provider, kind, notes, sort_order` (others ignored); `label` and `url` required; https ≤ 2048; `provider` in the enum (default `other`); `kind` ≤ 40, `notes` ≤ 2000; `sort_order` defaults to position.
  - `private.sync_asset_rows(p_project_id uuid, p_items jsonb) returns boolean` — same id-matching rule as `private.sync_brief_rows` (foreign or duplicate id `ES422`; delete missing; update by id; insert without id); never touches `early_access`; returns true if a field other than `sort_order` changed or a row was added/removed.
- Produces (public):
  - `public.admin_save_assets(p_project_id uuid, p_items jsonb) returns void` — `lock_writable_project`; audit `project.assets_changed` `{project_id}` only when `sync_asset_rows` returns true; never touches `brief_versions` or `current_brief_version`.
  - `public.admin_set_reference_early_access(p_reference_id uuid, p_value boolean) returns void` and `public.admin_set_asset_early_access(p_asset_id uuid, p_value boolean) returns void` — `ES422` for null value or unknown id; `lock_writable_project` on the parent; no-op (no audit) when unchanged; audit `project.early_access_changed` `{project_id, reference_id | asset_id, early_access}`.
  - `public.admin_record_asset_grant(p_project_id uuid, p_editor_id uuid, p_email text, p_provider public.asset_provider, p_folder_url text default null) returns uuid` — `lock_writable_project`; editor must have `access_status = 'active'` (`ES422` "Choose an active editor."); `p_provider` null `ES422`; `p_folder_url` https ≤ 2048 or null (`ES422`); live duplicate `ES409` "This share is already recorded."; sets `shared_by`; audit `asset_grant.recorded` `{grant_id, project_id, editor_id}`.
  - `public.admin_revoke_asset_grant(p_grant_id uuid, p_reason text default null) returns void` — unknown `ES422`; already revoked `ES409`; `p_reason` via `clean_text(.., 500, ..)`; works on cancelled/archived projects; audit `asset_grant.revoked` `{grant_id, project_id, editor_id}`.
  - `public.admin_pending_revocations() returns table (grant_id uuid, project_id uuid, editor_id uuid, shared_with_email text, provider public.asset_provider, folder_url text, shared_at timestamptz, reason text)` — live grants only; `reason` = `editor_not_active` (editor `access_status <> 'active'`) else `project_closed` (project `cancelled`, `completed` or archived); ordered by `shared_at, grant_id`. Replaced in Task 5.

- [ ] **Step 1: Write the failing test** `051_phase5_functions.test.sql`. As admin aal2 on an open project: `admin_save_assets` with three items inserts 3 rows with given order and `early_access = false`; re-save with one id dropped, one label edited, one new item → 3 rows, edited label, one `project.assets_changed` row; re-save identical content (and a reorder only) → no new audit row; `current_brief_version` and `count(brief_versions)` unchanged after asset edits on an opened project; Review Focus 1 cases each `ES422` (`'{}'`, `'"x"'`, `'[1]'`, 101 items, `http://`, foreign id, duplicate id) and `null` / `'[]'` clear the list; unknown keys ignored. Early access: setter flips the value, writes one audit row with ids and `early_access`, unchanged value writes none, unknown id `ES422`; `admin_save_brief` with an unchanged reference list leaves `early_access = true` and creates no version. Grants: record returns an id with `shared_with_email = 'editor@drive.com'` for input `'  Editor@Drive.COM '`; Review Focus 2 (`ES409`, then revoke, then re-record succeeds); applicant or suspended editor id `ES422`; bad email, `http://` folder URL, null provider `ES422`; revoke twice `ES409`; revoke works after the project is archived; record on cancelled or archived project `ES409`; save assets on cancelled or archived `ES409`. Checklist: seed four live grants (active editor/open project; S suspended; project cancelled; project archived) and one revoked grant → `results_eq` returns exactly the three expected `(grant_id, reason)` pairs in order; editor email is returned. Every public function: anon `ES401`; admin aal1, editor A, applicant `ES403`. `activity_logs` rows from this file contain no `@`, no URL and no label text.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement** the helpers and functions; `jsonb_to_recordset` for the sync, mirroring `private.sync_brief_rows`; `revoke ... from public, anon, authenticated` on every function, grant the six public ones to `anon, authenticated`.

- [ ] **Step 4: Run `npm run db:reset && npm run db:test`; expect pass.**

---

### Task 3: Phase 6 schema

**Files:**

- Create: `supabase/migrations/<ts>_phase6_access_schema.sql`
- Test: `supabase/tests/database/052_phase6_schema.test.sql`

**Interfaces:**

- Produces enums: `public.project_access_reason` = (`invited`, `available`); `public.assignment_status` = (`offered`, `counteroffer_pending`, `accepted`, `confirmed`, `declined`, `withdrawn`, `not_selected`, `reassigned`); `public.negotiation_role` = (`admin`, `editor`); `public.negotiation_action` = (`offer`, `counter`, `accept`, `decline`, `withdraw`).
- Produces `public.project_access` — `id uuid pk`, `project_id` FK `projects` restrict, `editor_id` FK `editor_profiles (user_id)` restrict, `reason public.project_access_reason not null`, `granted_by` FK `profiles` set null, `granted_at timestamptz not null default now()`, `revoked_by` FK `profiles` set null, `revoked_at timestamptz`, `created_at`, `updated_at`. Partial unique index `project_access_live_key on (project_id, editor_id) where revoked_at is null`; index `(editor_id)`.
- Produces `public.assignments` — `id uuid pk`, `project_id` FK restrict, `editor_id` FK `editor_profiles (user_id)` restrict, `status public.assignment_status not null default 'offered'`, `proposed_amount numeric(12,2) not null check (> 0)`, `currency char(3) not null default 'LKR'` (regex), `agreed_amount numeric(12,2) check (> 0)`, `agreed_currency char(3)` (regex when not null), `confirmed_by` FK `profiles` set null, `confirmed_at timestamptz`, `closed_at timestamptz`, `created_at`, `updated_at`. Constraints: `assignments_agreed_chk` = `(agreed_amount is null) = (agreed_currency is null) and (agreed_currency is null or agreed_currency = currency) and (status not in ('accepted','confirmed') or agreed_amount is not null) and (status not in ('offered','counteroffer_pending') or agreed_amount is null)`; `assignments_confirmed_chk` = `(status = 'confirmed') <= (confirmed_at is not null)`; `assignments_closed_chk` = `(status in ('declined','withdrawn','not_selected','reassigned')) = (closed_at is not null)`. Partial unique indexes `assignments_live_key on (project_id, editor_id) where status in ('offered','counteroffer_pending','accepted','confirmed')` and `assignments_one_confirmed_key on (project_id) where status = 'confirmed'`; indexes on `editor_id`, `confirmed_by`.
- Produces `public.negotiation_offers` — `id uuid pk`, `assignment_id` FK `assignments` restrict, `from_role public.negotiation_role not null`, `action public.negotiation_action not null`, `amount numeric(12,2) check (> 0)`, `currency char(3)` (regex), `message text check (1..2000)`, `created_by` FK `profiles` set null, `created_at`. Constraint `negotiation_offers_amount_chk` = `(action in ('decline','withdraw')) = (amount is null) and (amount is null) = (currency is null)`. Index `(assignment_id, created_at)`.
- Produces `public.project_notes` — `id uuid pk`, `project_id` FK restrict, `author_id` FK `profiles` set null, `note text not null check (1..4000)`, `created_at`. Index `(project_id, created_at desc)`.
- Produces `private.assignment_transition_allowed(p_from public.assignment_status, p_to public.assignment_status) returns boolean` (immutable): `offered → accepted|declined|counteroffer_pending|withdrawn|not_selected`; `counteroffer_pending → accepted|offered|declined|withdrawn|not_selected`; `accepted → confirmed|withdrawn|not_selected`; `confirmed → reassigned|withdrawn`; everything else false.
- Produces triggers: `private.guard_assignments()` (BEFORE UPDATE on `assignments`; `ES409` if `project_id`/`editor_id` change or a status change fails `assignment_transition_allowed`); `private.guard_append_only()` (BEFORE UPDATE OR DELETE on `negotiation_offers` and `project_notes`; `ES409` except an UPDATE that only sets `created_by`/`author_id` from non-null to null); `private.audit_assignments()` (AFTER INSERT OR UPDATE OF status on `assignments`; action `assignment.<new status>`, entity `assignment`, details `{assignment_id, project_id, editor_id, from, to}`; actor as in `private.audit_projects()`).
- Produces admin-only select policies on all four tables: `<table>_select_admin`.

- [ ] **Step 1: Write the failing test** `052_phase6_schema.test.sql`. Enum labels exact for all four enums. For each of the four tables: anon `42501` on select; editor A (with a seeded assignment and access row of their own), editor B, S and applicant see 0 (editor policies arrive in Task 4); admin aal2 sees the seeded rows, admin aal1 0; direct insert/update/delete as admin aal2 `42501`. As postgres: second live assignment for the same (project, editor) `23505`; a `declined` row plus a new `offered` row for the same pair succeeds; two `confirmed` rows on one project `23505`; `accepted` without `agreed_amount` `23514`; `agreed_currency <> currency` `23514`; `withdrawn` without `closed_at` `23514`; `proposed_amount = 0` `23514`; table-driven over all 64 status pairs, `update assignments set status` succeeds exactly for the 15 allowed pairs (plus same-status no-op updates of other columns) and raises `ES409` otherwise; changing `editor_id` raises `ES409`. `negotiation_offers`: `decline` with an amount `23514`, `offer` without amount `23514`, update and delete raise `ES409`, setting `created_by = null` alone succeeds, setting `created_by = null` and `message` together raises; same pair for `project_notes` (`author_id`). Second live `project_access` row for a pair `23505`, succeeds after revoke. Inserting an assignment and changing its status writes `assignment.offered` and `assignment.accepted` rows whose `details` have exactly the keys `assignment_id, project_id, editor_id, from, to`.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement the migration**; trigger functions `security definer set search_path = ''`, revoked from all API roles; `set_updated_at` triggers on `project_access` and `assignments` only.

- [ ] **Step 4: Run `npm run db:reset && npm run db:test`; expect pass.**

---

### Task 4: Editor stage helper and editor read policies

**Files:**

- Create: `supabase/migrations/<ts>_phase6_editor_visibility.sql`
- Test: `supabase/tests/database/053_phase6_visibility.test.sql`
- Modify: `supabase/tests/database/046_phase4_function_security.test.sql` (allow-list only)

**Interfaces:**

- Consumes: `private.require_user()`, `private.is_active_editor()` (Phases 1–2), tables from Tasks 1 and 3.
- Produces: `private.require_active_editor() returns uuid` — plpgsql stable security definer; `private.require_user()` (`ES401` "Please sign in.") then `ES403` "Your editor access is not active." unless `private.is_active_editor()`; returns the uid. No API grant.
- Produces: `private.editor_project_stage(p_project_id uuid) returns text` — sql stable security definer; returns `'none'` unless `private.is_active_editor()` and the project exists with `status <> 'cancelled' and archived_at is null`; `'assigned'` if the caller has an assignment on it with status `confirmed`; `'opportunity'` if the caller has a live `project_access` row or an assignment in (`offered`, `counteroffer_pending`, `accepted`); else `'none'`. `grant execute ... to authenticated` (not anon).
- Produces policies (`for select to authenticated`), alongside the existing admin ones:
  - `projects_select_editor`: `private.editor_project_stage(id) in ('opportunity','assigned')`
  - `project_deliverables_select_editor`: `private.editor_project_stage(project_id) in ('opportunity','assigned')`
  - `project_references_select_editor` / `project_assets_select_editor`: `private.editor_project_stage(project_id) = 'assigned' or (early_access and private.editor_project_stage(project_id) = 'opportunity')`
  - `brief_versions_select_editor`: `private.editor_project_stage(project_id) = 'assigned'`
  - `assignments_select_editor` / `project_access_select_editor`: `editor_id = (select auth.uid()) and (select private.is_active_editor())`
  - `negotiation_offers_select_editor`: `(select private.is_active_editor()) and exists (select 1 from public.assignments a where a.id = assignment_id and a.editor_id = (select auth.uid()))`
- No policy for editors on `asset_access_grants`, `project_notes`, `project_internal`, `clients`.

- [ ] **Step 1: Write the failing test** `053_phase6_visibility.test.sql`. Fixtures (as postgres): projects `P_inv` (open, A access `invited`, B none), `P_avail` (open, A access `available`), `P_offer` (open, B `offered`, no access row), `P_conf` (assigned, A `confirmed`, B `not_selected` with revoked access), `P_hold` (on_hold, A access), `P_cancel` (cancelled, A access live), `P_arch` (archived, A `confirmed`), `P_revoked` (open, A access revoked), `P_none` (open); each with one deliverable, one current brief version, two references and two assets (one `early_access`), plus one `asset_access_grants` row and one `project_notes` row; negotiation rows on every assignment. Assertions, using `results_eq` on sorted id lists:
  - Stage function (called as each identity): A → `opportunity` for `P_inv`, `P_avail`, `P_hold`; `assigned` for `P_conf`; `none` for `P_cancel`, `P_arch`, `P_revoked`, `P_none`, `P_offer`; B → `opportunity` for `P_offer`, `none` for `P_conf`.
  - A sees `projects` = {`P_inv`, `P_avail`, `P_hold`, `P_conf`}; deliverables of those four; references and assets: only the early-access ones of `P_inv`, `P_avail`, `P_hold` and both of `P_conf`; `brief_versions` of `P_conf` only (all its versions, Call 5).
  - B sees `projects` = {`P_offer`}, early-access refs/assets of `P_offer`, no brief versions; zero rows of anything on `P_conf` except their own `not_selected` assignment and its negotiation rows.
  - A sees only own `assignments`, own `negotiation_offers`, own `project_access` rows (B's rows on shared projects absent); B likewise.
  - A and B see 0 rows of `asset_access_grants`, `project_notes`, `project_internal`, `clients`, even on `P_conf`.
  - S (suspended, with a live access row and a confirmed assignment on a project of their own), applicant and admin at aal1: 0 rows on every table above; stage `none`. Anon `42501` on every table.
  - Admin aal2 still sees every row of every table.
  - Immediate loss: as postgres set A `suspended` → A sees 0 rows everywhere including own assignments; set back `active` → visible again; set `revoked` → 0.
  - Review Focus 11 and 12: `P_hold` stays visible; restoring `P_arch` (`archived_at = null`) makes it `assigned` for A.
  - Toggling an asset's `early_access` on `P_inv` changes A's count accordingly.
  - Editor A direct `update public.assignments set agreed_amount = 1` and `insert into public.project_access` raise `42501`.
  - `has_function_privilege('authenticated', 'private.editor_project_stage(uuid)', 'execute')` true; anon false; `private.require_active_editor()` false for both.
  - `require_active_editor` (called via a `pg_temp` wrapper run as postgres with claims set) raises `ES401` for anon, `ES403` for applicant, S and admin, returns A's uid for A.
- Update 046: add `private.editor_project_stage` to `allow_private_exec`, to the name list in the "no explicit grant" check, and add one `ok` asserting it is executable by `authenticated` and not by `anon`; bump `plan()`.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement** the helper, the stage function and the policies. Keep `(select ...)` wrapping for `auth.uid()` and `is_active_editor()`; the per-row stage call takes a column argument and cannot be wrapped.

- [ ] **Step 4: Run `npm run db:reset && npm run db:test`; expect pass**, including `040_phase4_schema` (editors with no access still see 0) and the updated 046.

---

### Task 5: Admin access, offer, negotiation, confirmation and note functions

**Files:**

- Create: `supabase/migrations/<ts>_phase6_admin_negotiation.sql`
- Test: `supabase/tests/database/054_phase6_offers.test.sql`, `supabase/tests/database/055_phase6_confirm.test.sql`

**Interfaces:**

- Consumes: `private.require_admin()`, `private.clean_text`, `private.lock_writable_project` (Task 2), `private.assignment_transition_allowed` (Task 3).
- Produces (all `private`, security definer, no API grants):
  - `private.check_amount(p_amount numeric, p_label text) returns numeric` — `ES422` if null, `<= 0`, more than 2 decimals, or `> 9999999999.99`.
  - `private.check_currency(p_currency text, p_default char(3)) returns char(3)` — null → `p_default`; `upper(btrim())`; `ES422` unless `^[A-Z]{3}$`.
  - `private.lock_assignment(p_assignment_id uuid) returns public.assignments` — locks the parent project `for update`, then the assignment `for update`; `ES422` "Offer not found.".
  - `private.add_negotiation(p_assignment_id uuid, p_role public.negotiation_role, p_action public.negotiation_action, p_amount numeric, p_currency char(3), p_message text, p_actor uuid) returns void`.
  - `private.close_live_assignments(p_project_id uuid, p_to public.assignment_status, p_actor uuid, p_editor_id uuid default null, p_except_assignment uuid default null) returns int` — `p_to` in (`withdrawn`, `not_selected`) only; sets `closed_at = now()`; for `withdrawn` appends an admin `withdraw` negotiation row (message null). Live = `offered`, `counteroffer_pending`, `accepted`, and `confirmed` only when `p_to = 'withdrawn'`.
  - `private.revoke_live_access(p_project_id uuid, p_actor uuid, p_editor_id uuid default null, p_except_editor uuid default null) returns int` — sets `revoked_at`, `revoked_by`; audit `project_access.revoked` `{project_id, editor_id}` per row.
- Produces (public, all `require_admin()` first):
  - `public.admin_grant_project_access(p_project_id uuid, p_editor_ids uuid[], p_reason public.project_access_reason) returns int` — project locked; `first_opened_at is not null`, `status = 'open'`, not archived (`ES409`); Review Focus 4 / Call 17; audit `project_access.granted` `{project_id, editor_id, reason}` per new row.
  - `public.admin_revoke_project_access(p_project_id uuid, p_editor_id uuid) returns void` — Call 18; withdraws the editor's live unconfirmed assignment via `close_live_assignments(.., 'withdrawn', .., p_editor_id)`; revokes the live access row.
  - `public.admin_make_offer(p_project_id uuid, p_editor_id uuid, p_amount numeric, p_currency text default null, p_message text default null) returns uuid` — Calls 10, 11, 19; editor active (`ES422`); new assignment `offered` + negotiation `offer` (admin, amount, currency, message); on `counteroffer_pending` sets `proposed_amount`, status `offered`, negotiation `counter`; returns the assignment id.
  - `public.admin_respond_counter(p_assignment_id uuid, p_action text, p_amount numeric default null, p_currency text default null, p_message text default null) returns void` — `p_action` in (`accept`, `counter`, `decline`); from `counteroffer_pending` only (`ES409`); `accept` → `accepted` + agreed fields (Call 12); `counter` → `offered` with new `proposed_amount`; `decline` → `declined`, `closed_at`.
  - `public.admin_withdraw_offer(p_assignment_id uuid, p_message text default null) returns void` — from `offered`, `counteroffer_pending`, `accepted` (`ES409` otherwise, `confirmed` included: use reassign); negotiation `withdraw` with message.
  - `public.admin_confirm_assignment(p_assignment_id uuid) returns void` — `lock_assignment`; status `accepted` with `agreed_amount` (`ES409`); project `open`, not archived (`ES409`); editor still active (`ES409`); sets `confirmed`, `confirmed_by`, `confirmed_at`; project `status = 'assigned'`; `close_live_assignments(.., 'not_selected', .., p_except_assignment => id)`; `revoke_live_access(.., p_except_editor => editor_id)` (Call 13).
  - `public.admin_reassign(p_assignment_id uuid, p_message text default null) returns void` — Call 14; from `confirmed` with project `assigned` (`ES409`); sets `reassigned`, `closed_at`; negotiation `withdraw` with message; project `status = 'open'`; revokes that editor's live access.
  - `public.admin_add_project_note(p_project_id uuid, p_note text) returns uuid` — `clean_text(p_note, 4000, 'note')`, required (`ES422`); project must exist (`ES422`); audit `project.note_added` `{project_id, note_id}`.
  - `public.admin_pending_revocations()` — `create or replace` with the same signature, adding reason `no_active_assignment` (Call 3).
- Messages everywhere: `clean_text(p_message, 2000, 'message')`.

- [ ] **Step 1: Write the failing tests.**
  - `054_phase6_offers.test.sql` (open project opened via `admin_set_project_status`; editors A, B active; S suspended): grant access to `{A, B}` returns 2, again returns 0 (idempotent, `reason` unchanged); Review Focus 4 cases each `ES422` with `count(project_access)` unchanged; grant on a never-opened project, a draft, an on_hold, a cancelled and an archived project `ES409`; null reason `ES422`. Offer to A → assignment `offered`, one `offer` negotiation row with amount and currency, `assignment.offered` audit; offer to a non-invited active editor creates an `invited` access row; Review Focus 3 cases `ES422`, `'lkr'` stored as `LKR`, null currency takes the project's `proposed_currency`; offer to self, applicant or S `ES422`; Review Focus 8 (second offer to A while `offered` `ES409`; set A's row to `counteroffer_pending` as postgres → `admin_make_offer` re-offers on the same row with a `counter` row; after `admin_withdraw_offer`, a new offer creates a second row and the first row is byte-for-byte unchanged); `admin_respond_counter` from `offered` `ES409`; from `counteroffer_pending`: `accept` sets `accepted` and `agreed_amount = proposed_amount`, `counter` sets `offered` with the new amount, `decline` sets `declined` with `closed_at`; Review Focus 9 (`null`, `'Accept'`, `'confirm'` → `ES422`); Review Focus 10 (2001-char message `ES422`; `'   '` stored null); withdraw from `offered`, `counteroffer_pending` and `accepted` each succeed, from `declined` and `confirmed` `ES409`; revoke access with a live offer withdraws it (status `withdrawn`, `withdraw` row, access `revoked_at` set); revoke for an editor with nothing live `ES409`; Review Focus 11 (project `on_hold`: offer and respond-counter `ES409`, rows unchanged). Every function: anon `ES401`; admin aal1, editor A, applicant `ES403`. `negotiation_offers` row count equals the number of money/offer actions performed.
  - `055_phase6_confirm.test.sql`: Review Focus 5 — A and B both `accepted` (driven to that state with the admin functions plus a postgres-set editor accept), invited-only editor C with live access; confirm A → A `confirmed` with `confirmed_by`, project `assigned` (`project.assigned` audit row from the Phase 4 trigger), B `not_selected` with `closed_at`, B's and C's access revoked, A's kept; confirm B `ES409`; as postgres inserting a second `confirmed` row `23505`; `pg_get_functiondef('public.admin_confirm_assignment(uuid)'::regprocedure)` and `private.lock_assignment(uuid)` match `for\s+update`. Confirm from `offered` or `counteroffer_pending` `ES409`; confirm on a project `on_hold` or archived `ES409`; Review Focus 7 (A suspended after accepting → confirm `ES409`). Reassign: from `confirmed` → `reassigned`, `closed_at`, `withdraw` row with the message, project back to `open`, A's access revoked; reassign of a non-confirmed row `ES409`; afterwards a new offer to A creates a new row. Notes: `admin_add_project_note` returns an id, works on an archived project, blank or 4001-char note `ES422`, unknown project `ES422`; audit row has no note text. Checklist v2: live grants for (a) A after reassign, (b) B `not_selected`, (c) invited-only C, (d) confirmed editor on an open-then-assigned project, (e) S suspended → `results_eq` gives (a) `no_active_assignment`, (b) `no_active_assignment`, (c) `no_active_assignment`, (e) `editor_not_active`, and (d) absent. Every function: anon `ES401`; admin aal1, editor A, applicant `ES403`.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement** the helpers and functions. Keep the transition rules in `private.assignment_transition_allowed` plus the function-level "from" checks; do not scatter extra rules. Audit rows for assignments come from the `assignments` trigger; access and note audits are written in the functions.

- [ ] **Step 4: Run `npm run db:reset && npm run db:test`; expect pass.**

---

### Task 6: `editor_respond_offer`

**Files:**

- Create: `supabase/migrations/<ts>_phase6_editor_respond.sql`
- Test: `supabase/tests/database/056_phase6_editor_respond.test.sql`

**Interfaces:**

- Consumes: `private.require_active_editor()` (Task 4), `private.lock_assignment`, `private.add_negotiation`, `private.check_amount`, `private.check_currency`, `private.clean_text` (Tasks 2, 5).
- Produces: `public.editor_respond_offer(p_assignment_id uuid, p_action text, p_amount numeric default null, p_currency text default null, p_message text default null) returns void` — `require_active_editor()` first; `lock_assignment`; not own → `ES422` "Offer not found." (Call 20); project `open` and not archived (`ES409`); from `offered` only (`ES409`); `p_action` in (`accept`, `decline`, `counter`) else `ES422`; `accept` → `accepted`, `agreed_amount = proposed_amount`, `agreed_currency = currency`, editor `accept` row with that amount; `decline` → `declined`, `closed_at`, editor `decline` row; `counter` → `check_amount`, currency must equal the assignment's (`ES422`), amount must differ from `proposed_amount` (`ES422`), sets `proposed_amount` and `counteroffer_pending`, editor `counter` row. Message via `clean_text(.., 2000, ..)`.

- [ ] **Step 1: Write the failing test** `056_phase6_editor_respond.test.sql`. As editor A with an `offered` assignment: `accept` → `accepted`, agreed fields equal the offer, one editor `accept` row, `assignment.accepted` audit with no amount in `details`; fresh offer, `decline` → `declined` with `closed_at`; fresh offer, `counter` 15000 → `counteroffer_pending`, `proposed_amount = 15000`, editor `counter` row; then `admin_respond_counter(.., 'accept')` → `accepted` at 15000 (full round trip); counter equal to the offer `ES422`; counter in `USD` on an `LKR` offer `ES422`; Review Focus 3 amounts `ES422`; Review Focus 9; responding from `counteroffer_pending`, `accepted`, `withdrawn` `ES409`; Review Focus 6 (B calling with A's id and anyone with a random uuid → same `ES422` message, A's row unchanged); Review Focus 7 (A suspended → `ES403`; row unchanged); Review Focus 11 (project `on_hold` → `ES409`); anon `ES401`; applicant and admin aal2 `ES403`; editor A calling `admin_make_offer`, `admin_confirm_assignment`, `admin_withdraw_offer` → `ES403`; editor A direct `update public.assignments set status = 'confirmed'` → `42501`.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement** the function; revoke from `public, anon, authenticated`, grant to `anon, authenticated`.

- [ ] **Step 4: Run `npm run db:reset && npm run db:test`; expect pass.**

---

### Task 7: Phase 4 status changes

**Files:**

- Create: `supabase/migrations/<ts>_phase6_project_status_changes.sql`
- Test: `supabase/tests/database/057_phase6_project_status.test.sql`
- Modify: `supabase/tests/database/044_phase4_status.test.sql` (expected allowed-transition list gains `assigned>cancelled`; nothing else)

**Interfaces:**

- Consumes: `private.close_live_assignments`, `private.revoke_live_access` (Task 5).
- Produces: `create or replace private.project_transition_allowed(p_from public.project_status, p_to public.project_status, p_before_hold public.project_status) returns boolean` — Phase 4 rules plus `when p_from = 'assigned' then p_to = 'cancelled'`.
- Produces: `create or replace public.admin_set_project_status(p_project_id uuid, p_status public.project_status, p_note text default null) returns void` — same signature and existing behaviour, plus: `open → draft` raises `ES409` "Editors have already been given access to this project, so it cannot go back to draft." when any `project_access` or `assignments` row exists for the project (Call 16); on `cancelled` (from `draft`, `open` or `assigned`) calls `close_live_assignments(p_project_id, 'withdrawn', v_admin)` then `revoke_live_access(p_project_id, v_admin)` (Call 15). `assigned` stays refused as a target. Re-issue `revoke`/`grant` for both functions.

- [ ] **Step 1: Write the failing test** `057_phase6_project_status.test.sql`. `open → draft` succeeds with no access rows; refused `ES409` with a live access row, with only a revoked access row, and with only a `declined` assignment; `admin_set_project_status(.., 'assigned')` still `ES409` from `open`; cancel from `assigned` with A `confirmed` → project `cancelled`, A `withdrawn` with `closed_at` and an admin `withdraw` row, A's access revoked, A's stage `none`; cancel from `open` with B `offered` and C `accepted` → both `withdrawn`, all access revoked; `on_hold` from `assigned` `ES409`; after cancellation `admin_pending_revocations` lists A's live grant as `editor_not_active` or `project_closed` (project closed here). Update 044's expected list and confirm the matrix is otherwise unchanged.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement** the migration (`create or replace` both functions; same `revoke ... from public, anon, authenticated` / `grant execute ... to anon, authenticated` lines as Phase 4).

- [ ] **Step 4: Run `npm run db:reset && npm run db:test`; expect pass**, including 044 and 046.

---

### Task 8: Function-security and data-hygiene tests for Phases 5–6

**Files:**

- Test: `supabase/tests/database/058_phase5_6_function_security.test.sql`

**Interfaces:**

- Consumes: everything above. Produces no code, only guardrails (§10). The 046 catalogue rules already run over every function; this file pins the new objects by name so a missing one fails loudly.

- [ ] **Step 1: Write the test.** All 16 new or replaced public functions exist and are executable by `anon` and `authenticated` (`admin_save_assets(uuid, jsonb)`, `admin_set_reference_early_access(uuid, boolean)`, `admin_set_asset_early_access(uuid, boolean)`, `admin_record_asset_grant(uuid, uuid, text, public.asset_provider, text)`, `admin_revoke_asset_grant(uuid, text)`, `admin_pending_revocations()`, `admin_grant_project_access(uuid, uuid[], public.project_access_reason)`, `admin_revoke_project_access(uuid, uuid)`, `admin_make_offer(uuid, uuid, numeric, text, text)`, `admin_respond_counter(uuid, text, numeric, text, text)`, `admin_withdraw_offer(uuid, text)`, `admin_confirm_assignment(uuid)`, `admin_reassign(uuid, text)`, `admin_add_project_note(uuid, text)`, `editor_respond_offer(uuid, text, numeric, text, text)`, `admin_set_project_status(uuid, public.project_status, text)`); each new `private` helper and trigger function is security definer, `search_path=""`, executable by no API role (except `editor_project_stage` → `authenticated` only); `prosrc` of every new `public.admin_*` contains `private.require_admin()` and of `editor_respond_offer` contains `private.require_active_editor()`. Data hygiene: no column matching `client|email|phone|company|contact` on `project_assets`, `assignments`, `negotiation_offers`, `project_access` (editor-readable); `client_price%` still only in `project_internal`; `asset_access_grants` and `project_notes` have no editor policy (`pg_policies` for them = only `*_select_admin`); every editor-readable table's policies are `for select` only (`pg_policies.cmd = 'SELECT'` for all policies on the eight tables). Audit: run one full flow as admin and editor (assets, early access, grant/revoke, access, offer, counter, accept, confirm, reassign, note, cancel) and assert `activity_logs` rows with actions `assignment.%`, `project_access.%`, `asset_grant.%`, `project.assets_changed`, `project.early_access_changed`, `project.note_added` exist and none has `details ?| array['amount','proposed_amount','agreed_amount','message','note','email','url','label','title']` or `details::text` containing `@`, `https://` or the amounts used.

- [ ] **Step 2: Run `npm run db:test`.** If a new function fails a rule, fix it in its own (uncommitted) migration, or a new migration if it has been committed.

---

### Task 9: Docs, types, advisors and security review

**Files:**

- Modify: `docs/DATABASE_SCHEMA.md`, `docs/SECURITY_AND_PRIVACY.md` (access matrix rows for the new tables and the editor stages), `docs/WORKFLOWS.md` (§3 assignment lifecycle as built, §6 cancellation), `docs/BUSINESS_RULES.md` (only if pay/offer wording conflicts with what was built), `docs/DEVELOPMENT_ROADMAP.md`, `docs/CURRENT_STATUS.md`, `docs/CHANGELOG.md`, `src/lib/supabase/database.types.ts` (generated).

- [ ] **Step 1:** `npm run db:types`; confirm the diff only adds the new tables, column, functions and enums.
- [ ] **Step 2:** `npm run db:advisors`; expect no new security warnings (unused-index performance notes may be recorded, not fixed; note any `auth_rls_initplan` finding on the per-row stage calls and confirm it is the uncachable column-argument case).
- [ ] **Step 3:** Update the docs (tables as built, the Calls list above recorded as plan calls awaiting owner review, current status "Phases 5–6 database done, screens next"). Do not edit `EDITSTATION_MASTER_KNOWLEDGE_BASE.md`; do not decide `OPEN_QUESTIONS.md` items (F, KB7 stay open).
- [ ] **Step 4:** `npm run check` and `npm run db:test`; both green.
- [ ] **Step 5:** Dispatch the `db-security` agent over the seven new migrations, tests 050–058 and the 044/046 edits; fix anything it flags with tests; re-run Step 4.

---

## Self-review notes

Spec coverage: Phase 5 schema (§5) Task 1; Phase 5 functions (§7) Task 2; Phase 6 schema (§5) Task 3; visibility (§6) Task 4; admin functions and transition table (§7) Task 5; editor function (§7) Task 6; Phase 4 change (§7) Task 7; function security and hygiene (§10) Task 8; docs Task 9. §8 derived labels are app-side (screens plan). §9 screens and §10 Vitest/Playwright are out of scope for this database plan. Every §10 test class maps to a task: visibility cells (053), every transition and refusal (052 trigger matrix, 054–056), one confirmed per project (055), append-only offers and notes (052), cross-role refusals (054–056), `open → draft` (057), checklist conditions (051, 055, 057), function catalogue (046, 058), no client data on editor-readable tables (058).
