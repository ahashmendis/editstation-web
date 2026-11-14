# Phase 4 Database Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Phase 4 projects, briefs, clients and inquiry-conversion database layer, with function-only writes, admin-only RLS, and full pgTAP coverage.

**Architecture:** Six new admin-readable tables with no write grants. Every write is a `public.admin_*` security-definer function that calls `private.require_admin()` first; shared logic lives in `private` helpers. Conversion is one plpgsql transaction. Delivered as several small append-only migrations, one per task.

**Tech Stack:** Postgres (Supabase local, CLI pinned 2.122.1), pgTAP, plpgsql. No application code in this plan: the admin screens are a separate plan written after this layer is reviewed.

**Spec:** `docs/superpowers/specs/2026-11-13-phase4-projects-briefs-design.md` (approved 2026-11-14). Section numbers below (§) refer to it.

## Global Constraints

- RLS enabled on every table; `revoke all ... from anon, authenticated`, then only `grant select ... to authenticated` plus an admin-only policy `using ((select private.is_admin()))`. No insert/update/delete grant or policy anywhere.
- Every `public.admin_*` function: `language plpgsql security definer set search_path = ''`, first statement `private.require_admin()`, then `revoke all on function <sig> from public, anon, authenticated;` followed by `grant execute on function <sig> to anon, authenticated;`. Every `private.*` function and trigger function: `revoke all ... from public, anon, authenticated;` and no grant.
- Errors only `ES401`/`ES403` (from `require_admin`), `ES409` (state conflict), `ES422` (invalid input); never `42501`. Messages are user-safe plain sentences.
- Money: `numeric(12,2)` with a sibling `char(3)` currency, `check (currency ~ '^[A-Z]{3}$')`, default `'LKR'`.
- Client email stored as `lower(btrim(email))`, enforced by check constraint; unique index on it where `merged_into_id is null`.
- Never edit an applied (committed) migration; new migrations via `npx supabase migration new <name>`. Local database only; no `link`/`db push`.
- Audit rows go to `public.activity_logs (actor_id, action, entity_type, entity_id, details)`; `details` holds ids and status names only, no personal data.
- Run `npm run db:reset` then `npm run db:test` after each task. All 151 existing pgTAP tests stay green.
- Committing needs owner approval in this repo: each task's commit step is a request, not automatic.

## Review Focus

Input classes the spec implies but does not pin; each line has a test in the owning task.

1. `jsonb` arguments that are `null`, `{}`, `[]`, not an object, or contain unknown keys (expect `ES422` for wrong type, unknown keys ignored). Task 3.
2. More than 50 deliverables or 100 references in one call (expect `ES422`; limits are this plan's call). Task 3.
3. Negative or non-integer timecodes, `end_seconds < start_seconds`, past deadlines (past deadline accepted; the others `ES422`). Task 3.
4. `admin_save_brief` called with content identical to the current version (expect no new version, current version returned). Task 4.
5. Changing `brief_type` after `first_opened_at` is set (this plan's call: `ES409`, because it would change what a version means). Task 5.
6. Two sessions converting the same inquiry at once (expect exactly one project, the other `ES409`). Task 6.
7. An inquiry email with mixed case and padding matching an existing client (expect reuse, no duplicate). Task 6.

## File Structure

| File                                                           | Responsibility                                                                |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `supabase/migrations/<ts>_phase4_schema.sql`                   | enums, six tables, indexes, RLS, grants, guard triggers, status-audit trigger |
| `supabase/migrations/<ts>_phase4_inquiry_link.sql`             | `client_inquiries.converted_project_id` with pre-flight and validated check   |
| `supabase/migrations/<ts>_phase4_brief_helpers_and_create.sql` | `private` helpers, `admin_create_project`                                     |
| `supabase/migrations/<ts>_phase4_brief_versioning.sql`         | `admin_save_brief`                                                            |
| `supabase/migrations/<ts>_phase4_project_status.sql`           | `admin_update_project`, `admin_set_project_status`, `admin_archive_project`   |
| `supabase/migrations/<ts>_phase4_clients_and_conversion.sql`   | client functions, `admin_convert_inquiry`                                     |
| `supabase/tests/database/040`-`045_phase4_*.test.sql`          | pgTAP, one file per task                                                      |
| `docs/*`                                                       | updated per spec §12 in the last task                                         |

Use timestamps after `20261111140306`. Add tests with the same helpers as `030_phase3_inquiries.test.sql` (`pg_temp.as_user(uid, 'aal2')`, `pg_temp.as_anon()`, `private.grant_admin_by_email(email, 'test')`); identities: admin (aal2), admin at aal1, editor A, editor B, pending applicant, anon. UUID prefix `40000000-...` for fixtures.

---

### Task 1: Tables, RLS and guard triggers

**Files:**

- Create: `supabase/migrations/<ts>_phase4_schema.sql`
- Test: `supabase/tests/database/040_phase4_schema.test.sql`

**Interfaces:**

- Produces: enums `public.project_status` (§5), `public.brief_type`, `public.reference_priority`; tables `clients`, `projects`, `project_internal`, `brief_versions`, `project_deliverables`, `project_references` with the columns in §5 (column names exactly as in the spec: e.g. `projects.first_opened_at`, `projects.status_before_hold`, `projects.current_brief_version`, `brief_versions.requires_reacknowledgement`, `brief_versions.deliverables`/`references` as `jsonb`, `project_references.start_seconds`/`end_seconds`).
- Produces: `private.guard_first_opened_at()` (BEFORE UPDATE trigger on `projects`), `private.guard_brief_versions()` (BEFORE UPDATE/DELETE trigger on `brief_versions`), `private.audit_projects()` (AFTER INSERT OR UPDATE OF status trigger writing `project.created` / `project.<status>`).

- [ ] **Step 1: Write the failing test** `040_phase4_schema.test.sql`. Assertions: for each of the six tables, anon `throws_ok(..., '42501')` on select; editor A, editor B and applicant `is(count, 0)` after postgres seeds one row per table; admin at aal2 sees the seeded row; admin at aal1 sees zero; direct `insert`, `update`, `delete` as admin at aal2 throw `42501`. Trigger tests (run as postgres): updating `projects.first_opened_at` from non-null to another value or to null raises; setting it from null works; `delete from brief_versions` always raises; `update brief_versions` raises when the project's `first_opened_at is not null` and succeeds when null; email check rejects `' A@B.com'`; second unmerged client with the same email violates the unique index, but succeeds if the first has `merged_into_id` set; `project_references` check rejects `end_seconds < start_seconds` and `http://` URLs; updating `projects.status` writes a `project.open` row in `activity_logs`.

- [ ] **Step 2: Run to verify failure** — `npm run db:test`; expect failures for missing relations.

- [ ] **Step 3: Implement the migration.** Follow §5 and §6 exactly: PKs `uuid default gen_random_uuid()`, `created_at`/`updated_at` with `private.set_updated_at()` triggers, every FK indexed, length checks like Phase 3 (titles 1-200, long text 1-5000), `revision_allowance smallint default 3 check (between 0 and 20)`, `brief_versions unique (project_id, version)`, `project_internal.source_inquiry_id` unique and nullable (the FK to `client_inquiries`). Guard-trigger functions are `security definer set search_path = ''`, revoked from all API roles. Do not add `converted_project_id` here.

- [ ] **Step 4: Run to verify pass** — `npm run db:reset && npm run db:test`; expect the 040 file and the existing guardrail test (RLS on every table) green.

- [ ] **Step 5: Commit** (owner approval) — `git add supabase/migrations/*phase4_schema.sql supabase/tests/database/040_phase4_schema.test.sql` / `git commit -m "Add Phase 4 tables, RLS and guard triggers"`.

---

### Task 2: `converted_project_id` migration

**Files:**

- Create: `supabase/migrations/<ts>_phase4_inquiry_link.sql`
- Test: `supabase/tests/database/041_phase4_inquiry_link.test.sql`

**Interfaces:**

- Consumes: `public.projects` (Task 1), `public.client_inquiries` (Phase 3).
- Produces: `client_inquiries.converted_project_id uuid` (FK `projects`, indexed) and constraint `client_inquiries_converted_link_chk` = `check ((status = 'converted') = (converted_project_id is not null))`.

- [ ] **Step 1: Write the failing test.** Assertions: column exists; constraint rejects `update ... set status='converted'` with null link, and rejects a non-null link with a non-converted status; `admin_set_inquiry_status(..., 'converted')` still raises `ES409`.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement** in this order (§5, "Migration safety"): add the column nullable; a `do $$` block that counts `status = 'converted'` rows and, if the count is not zero, `raise exception 'Cannot add the conversion link: % inquiries are already marked converted. Review them first.', n` (no data changes); add the constraint `not valid`, then `validate constraint` in the same migration.

- [ ] **Step 4: Verify the pre-flight manually** (not a committed test, since a failing migration cannot run inside pgTAP): on a scratch local DB, temporarily insert a converted row via psql before applying the migration and confirm it aborts with that message; then `db:reset`. Record the outcome in the task report.

- [ ] **Step 5: Run `npm run db:reset && npm run db:test`; expect pass. Commit** (owner approval): `"Add inquiry conversion link with safe pre-flight"`.

---

### Task 3: Helpers and `admin_create_project`

**Files:**

- Create: `supabase/migrations/<ts>_phase4_brief_helpers_and_create.sql`
- Test: `supabase/tests/database/042_phase4_create.test.sql`

**Interfaces:**

- Produces (all `private`, security definer, no API grants):
  - `private.parse_deliverables(p_items jsonb) returns jsonb` and `private.parse_references(p_items jsonb) returns jsonb`: validate and normalise (trim; empty string to null), cap 50 / 100 items, raise `ES422` for wrong types, bad `https://` URL (≤2048), negative or non-integer seconds, `end < start`, bad `priority` (`essential|optional`); return a clean jsonb array preserving optional `id`.
  - `private.sync_brief_rows(p_project_id uuid, p_deliverables jsonb, p_references jsonb) returns boolean`: applies the id-matching rule of §14 (update by id, insert without id, delete missing) and returns `true` if any trimmed field value changed or any item was added or removed (reordering by `sort_order` alone and whitespace-only edits are not changes). An `id` that does not belong to the project raises `ES422`.
  - `private.brief_snapshot(p_project_id uuid) returns jsonb` giving `{"deliverables":[...],"references":[...]}` ordered by `sort_order, id`.
  - `private.check_ready_to_open(p_project_id uuid) returns void`: raises `ES422` with the missing item named, per §10 (title, brief type, ≥1 deliverable, deadline, instructions for `fully_instructed`, ≥1 reference for `reference_based`, `desired_outcome` for `creative_led`).
- Produces: `public.admin_create_project(p_input jsonb) returns uuid`. `p_input` keys: `title, brief_type, service_type_code, summary, deadline, requires_interpretation, proposed_amount, proposed_currency, revision_allowance, client_id, client_price, client_price_currency, internal_notes, brief{instructions, desired_outcome, audience, core_message, brand_constraints, mandatory_content, prohibited_content}, deliverables[], references[]`. `requires_interpretation` defaults to `true` for `reference_based` and `creative_led`, `false` for `fully_instructed`. Inserts `projects` (draft, `current_brief_version = 1`), `project_internal`, brief v1 (snapshot included), live deliverables and references; audit `project.created`; returns the project id. `client_id`, when given, must reference an unmerged, un-archived client (`ES422` otherwise).
- Later tasks reuse all of the above by these exact names.

- [ ] **Step 1: Write the failing test.** As admin aal2: creates one project of each `brief_type` (three `lives_ok`), counts the child rows and v1 snapshot equals the live rows; Review Focus 1-3 cases (`null`, `[]`, `{}`, string input; 51 deliverables; 101 references; negative seconds; end before start; `http://` URL; past deadline accepted); missing title, unknown `service_type_code`, bad currency, unarchived-client rule each `ES422`; anon and admin-at-aal1 and editor A, editor B and applicant get `ES401`/`ES403` as appropriate (anon `ES401`, others `ES403`); `has_function_privilege('anon', 'public.admin_create_project(jsonb)', 'execute')` is true while the same on `private.parse_deliverables(jsonb)` is false; `activity_logs` contains one `project.created` row with no title text in `details`.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement** the helpers and function in the migration; use `jsonb_to_recordset` for child rows; wrap check violations into `ES422` with the Phase 3 `exception when check_violation` pattern; remember the explicit `revoke ... from public, anon, authenticated` before grants.

- [ ] **Step 4: Run `npm run db:reset && npm run db:test`; expect pass.**

- [ ] **Step 5: Commit** (owner approval): `"Add brief helpers and admin_create_project"`.

---

### Task 4: `admin_save_brief` and versioning

**Files:**

- Create: `supabase/migrations/<ts>_phase4_brief_versioning.sql`
- Test: `supabase/tests/database/043_phase4_briefs.test.sql`

**Interfaces:**

- Consumes: `private.parse_deliverables`, `private.parse_references`, `private.sync_brief_rows`, `private.brief_snapshot` (Task 3).
- Produces: `public.admin_save_brief(p_project_id uuid, p_input jsonb) returns int`. `p_input` keys: `brief{...}`, `deliverables[]`, `references[]`, `change_summary text`, `requires_reacknowledgement boolean`. Returns the current brief version number.

- [ ] **Step 1: Write the failing test.** Cases (§8, §14): before first opening, a change edits v1 in place (count of `brief_versions` stays 1, snapshot updated, `current_brief_version` 1); after `first_opened_at` is set (set it as postgres in the test), a content change creates version 2 with a faithful snapshot and v1 is byte-for-byte unchanged (compare `to_jsonb` of the v1 row before and after); `change_summary` required from version 2 on (`ES422`); `requires_reacknowledgement` forced `true` when deliverables changed even if input says `false`, honoured `false` for an instructions-only change; identical content creates no version and returns the current number (Review Focus 4); reordering via `sort_order` and whitespace-only edits create no version; setting `status` back to `draft` then editing still creates a new version; `cancelled` and archived projects raise `ES409`, `on_hold` allowed; foreign `id` raises `ES422`; non-admin identities rejected; direct `update` of v1 after opening raises (trigger).

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement** `admin_save_brief`: lock the project row `for update`; call `sync_brief_rows` and compare brief text fields to the current version; decide per §8; write audit `project.brief_version` (details: project id, version) only when a version is created.

- [ ] **Step 4: Run `npm run db:reset && npm run db:test`; expect pass.**

- [ ] **Step 5: Commit** (owner approval): `"Add admin_save_brief with immutable versioning"`.

---

### Task 5: Project details, status and archive

**Files:**

- Create: `supabase/migrations/<ts>_phase4_project_status.sql`
- Test: `supabase/tests/database/044_phase4_status.test.sql`

**Interfaces:**

- Consumes: `private.check_ready_to_open` (Task 3).
- Produces: `public.admin_update_project(p_project_id uuid, p_input jsonb) returns void` (keys: `title, summary, deadline, service_type_code, proposed_amount, proposed_currency, revision_allowance, requires_interpretation, brief_type, client_id, client_price, client_price_currency, internal_notes`; never creates a version; changing `brief_type` after `first_opened_at` raises `ES409`; refuses `cancelled`/archived projects); `public.admin_set_project_status(p_project_id uuid, p_status public.project_status, p_note text default null) returns void`; `public.admin_archive_project(p_project_id uuid, p_archive boolean) returns void`.
- Status rules (§10): allowed `draft→open`, `open→draft`, `draft|open→cancelled`, `draft|open→on_hold` (stores `status_before_hold`), `on_hold→status_before_hold` (clears it); everything else (`assigned` and later, `cancelled→*`, same status) raises `ES409`. First move to `open` runs `check_ready_to_open`, sets `first_opened_at = now()` if null. A non-empty `p_note` is stored as the `details` note of the audit row.

- [ ] **Step 1: Write the failing test.** Every allowed transition; every refused transition (table-driven over all status pairs for a freshly seeded project, asserting exactly the five allowed families succeed); hold/resume round trip returns to the previous status; readiness failures named in the message for each brief type; `first_opened_at` set once and survives `open→draft→open`; Review Focus 5; update never changes `current_brief_version`; archive refuses nothing but blocks later writes (`admin_save_brief` raises `ES409`); archived/cancelled refuse `admin_update_project`; non-admin identities rejected; audit rows `project.open` etc. appear once per change.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement** the three functions; lock with `select ... for update`; keep the transition table as a `case` or a small `private` lookup, not scattered ifs.

- [ ] **Step 4: Run `npm run db:reset && npm run db:test`; expect pass.**

- [ ] **Step 5: Commit** (owner approval): `"Add project update, status and archive functions"`.

---

### Task 6: Clients and inquiry conversion

**Files:**

- Create: `supabase/migrations/<ts>_phase4_clients_and_conversion.sql`
- Test: `supabase/tests/database/045_phase4_conversion.test.sql`

**Interfaces:**

- Consumes: `admin_create_project` internals from Task 3 (call the private helpers directly; do not call the public function).
- Produces: `public.admin_create_client(p_input jsonb) returns uuid` (keys `name, company, email, phone, notes`; email normalised; duplicate unmerged email `ES409`); `public.admin_update_client(p_client_id uuid, p_input jsonb) returns void` (same keys plus `archived boolean`; cannot edit a merged client `ES409`); `public.admin_merge_clients(p_source uuid, p_target uuid) returns void` (§5/§14 rules: target unmerged and un-archived, source ≠ target; repoints `project_internal.client_id`; sets `merged_into_id`; audit `client.merged`); `public.admin_convert_inquiry(p_inquiry_id uuid, p_input jsonb) returns uuid` with the §9 steps. `p_input` has the same keys as `admin_create_project` (all optional; defaults from the inquiry: `service_type_code`, `deadline` from `expected_deadline`, `summary` from `description`, title from `service_type_label` + company or contact name); optional `client_id` to use instead of matching.
- Produces audit `inquiry.converted` via the existing status trigger and `project.created`.

- [ ] **Step 1: Write the failing test.** Happy path: exactly one client, one project, one `project_internal` with `source_inquiry_id`, v1, inquiry `converted` with `converted_project_id` set and `status_changed_by` the admin; second conversion of the same inquiry `ES409`; inquiries in `declined`, `closed`, `spam`, `converted` refused `ES409`; Review Focus 7 (inquiry email `'  Asha@Example.COM '` reuses the client created from `asha@example.com`); archived matching client raises `ES409` with the "restore it first" message and creates nothing; **forced failure**: a `p_input` with an invalid deliverable (parsed after the client insert) leaves zero new clients, zero new projects and the inquiry still `reviewing`; Review Focus 6 (pgTAP cannot open two sessions, so assert that the function body locks the inquiry with `for update` by checking `prosrc`, and that the unique index on `project_internal.source_inquiry_id` rejects a duplicate insert as the last-line defence; merge refuses merged, archived and identical targets; merge repoints projects and frees the merged email for a new client; `admin_update_client` can restore an archived client; client price is never copied from the inquiry; non-admin identities rejected for all four functions.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement.** Match key `lower(btrim(email))` among unmerged clients; `insert ... on conflict (email) where merged_into_id is null do nothing`, then re-select (race-safe); conversion locks the inquiry row `for update` first.

- [ ] **Step 4: Run `npm run db:reset && npm run db:test`; expect pass.**

- [ ] **Step 5: Commit** (owner approval): `"Add clients and atomic inquiry conversion"`.

---

### Task 7: Function-security and data-hygiene tests

**Files:**

- Test: `supabase/tests/database/046_phase4_function_security.test.sql`

**Interfaces:**

- Consumes: everything above. Produces no code, only guardrails (spec §7 "Function security", §11).

- [ ] **Step 1: Write the test.** Over every function whose schema is `public` or `private` and that is not extension-owned: owner is `postgres`; `prosecdef` is true; `proconfig` contains `search_path=""` (pin this for the new Phase 4 functions; list pre-Phase-4 exceptions explicitly with a comment if any exist, and report them rather than silently skipping); no `PUBLIC` entry in `proacl` (acl grantee `0`); `public` functions executable by `anon` and `authenticated`; `private` functions executable by nobody except an explicit allow-list (`is_admin`, `is_admin_account`, `is_active_editor`, and whatever Phase 1-3 already grant, discovered by running the query first). Data hygiene: `is_empty` over `information_schema.columns` for `projects`, `brief_versions`, `project_deliverables`, `project_references` where `column_name` matches `client|email|phone|company|contact`, except `projects.client_*` is absent by definition (assert no such column exists) and `client_price` appears only in `project_internal`. Also assert `activity_logs.details` for the Phase 4 actions contains no key named `title`, `email`, `name`.

- [ ] **Step 2: Run `npm run db:test`.** If the allow-list query shows pre-existing deviations, fix the test list (not the old migrations) and note them in the report; if a Phase 4 function fails the rules, fix that function in its own migration file (still uncommitted) or a new one if committed.

- [ ] **Step 3: Commit** (owner approval): `"Add function-security and data-hygiene guardrail tests"`.

---

### Task 8: Docs, types, advisors and security review

**Files:**

- Modify: `docs/DATABASE_SCHEMA.md`, `docs/DEVELOPMENT_ROADMAP.md`, `docs/WORKFLOWS.md` (§1, §3), `docs/SECURITY_AND_PRIVACY.md`, `docs/CURRENT_STATUS.md`, `docs/CHANGELOG.md`, `src/lib/supabase/database.types.ts` (generated).

- [ ] **Step 1:** `npm run db:types`; confirm the diff only adds the new tables, functions and enums.
- [ ] **Step 2:** `npm run db:advisors`; expect no new security warnings (performance notes for unused new indexes may be noted, not fixed).
- [ ] **Step 3:** Update the docs per spec §12 (tables as built, references moved to Phase 4, access matrix rows, current status "Phase 4 database done, screens next").
- [ ] **Step 4:** `npm run check` (format, lint, typecheck, unit tests) and `npm run db:test`; both green.
- [ ] **Step 5:** Dispatch the `db-security` agent over the Phase 4 migrations and tests; fix anything it flags with tests; re-run the commands from Step 4.
- [ ] **Step 6: Commit** (owner approval): `"Phase 4 database: docs, types and review fixes"`.

---

## Self-review notes

Spec coverage: schema and RLS (§5, §6) Task 1; `converted_project_id` and pre-flight (§5) Task 2; functions and helpers (§7), versioning (§8), conversion (§9), statuses (§10) Tasks 3-6; function security and hygiene tests (§7, §11) Task 7; docs (§12) Task 8; later-phase constraints (§15) are doc-only and recorded in Task 8 docs. Plan calls beyond the spec, all flagged: 50/100 item caps, `brief_type` frozen after first opening, multiple migration files, `ES422` for `client_id` that is merged or archived.
