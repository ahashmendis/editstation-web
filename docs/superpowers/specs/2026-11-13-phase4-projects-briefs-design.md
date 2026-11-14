# Phase 4 design: projects, briefs and inquiry conversion

Status: **DRAFT for owner approval (2026-11-13). Nothing is built, no migration exists.**
Inputs: KB §4, §5, §10; `WORKFLOWS.md` §1, §3, §5; `DATABASE_SCHEMA.md`; `SECURITY_AND_PRIVACY.md`;
Phase 3 migration `20261111140306_phase3_public_inquiries.sql`; owner decisions T, J (2026-11-13).

## 1. Intent

Give admins one place to turn a confirmed client inquiry (or a job that never came through the
form) into a **project** with a complete **brief**: type, instructions, deliverables, references,
deadline and proposed editor pay. Client identity and client price stay admin-only. This is the
foundation for later phases (assets, invitations, assignments, delivery, payment), so the data
model and the rules that guard it matter more than the screens.

Roadmap "done when": an admin can create or convert a project of any of the three brief types;
editors and anonymous users can see none of it.

## 2. Goals, non-goals, anti-goals

Goals

- Atomic inquiry conversion: client, project, internal record, brief v1, deliverables, references
  and the inquiry's `converted` status either all happen or none do.
- All three brief types fully creatable, including structured reference links (owner, 2026-11-13).
- Brief versioning that keeps an immutable history editors can later confirm against (Phase 7).
- Every rule enforced in Postgres; screens only call functions.

Non-goals (later phases)

- Editor visibility, invitations, `project_access`, assignments, negotiation (Phase 6).
- Footage/asset links (`project_assets`, Phase 5), uploads, notifications, payments, client portal.
- Any editor-facing page. Editors see nothing in Phase 4.

Anti-goals (would be a failure even if it "works")

- A table an editor, applicant or anonymous user can read or write directly.
- Client name, contact, company or client price on any table editors will later read.
- Any path that sets inquiry status `converted` other than the conversion function.
- A half-created project after a failure.
- Any overwrite or deletion of a brief version once its project has ever been opened (an editor
  can only confirm a version of an opened project, so a confirmed version can never change).

## 3. Constraints

RLS on every table, default deny; admin = `private.is_admin()` (MFA); functions in `public` are
executable by `anon` and `authenticated` and authorise in their body via `private.require_admin()`;
errors use `ES401/403/409/422`; money is `numeric(12,2)` plus `currency char(3)` (default `LKR` as
in Phase 3 `budget_ranges`; this does not settle decision H, it only stores the currency with every
amount); no large media in Postgres; no pricing or legal facts invented.

## 4. Approaches considered

1. **Database writes everything through functions (chosen).** Same pattern as Phases 2 and 3.
   Invariants live in one place; conversion is one transaction. Cost: more SQL and tests.
2. Admin writes tables directly through RLS policies, functions only for conversion and
   versioning. Less SQL, but the rules end up split between UI and database. Rejected.

Order of work: **A, database first (migration, access tests, db-security review), then admin
screens**, as two reviewable commits. A single combined change was rejected: a database mistake
would surface only after screens exist.

## 5. Schema

All new tables: `uuid` PK (`gen_random_uuid()`), `created_at`/`updated_at` with
`private.set_updated_at()`, RLS enabled, `revoke all ... from anon, authenticated`, then only the
grants below. Every FK is indexed.

### Enums

- `project_status`: `draft, open, assigned, in_progress, in_review, revision_requested, approved,
completed, on_hold, cancelled` (decision J).
- `brief_type`: `fully_instructed, reference_based, creative_led` (KB §4).
- `reference_priority`: `essential, optional` (KB §4.2).

### `clients` (admin-only; decision T)

`name` (contact), `company`, `email`, `phone`, `notes`, `merged_into_id` (self FK, null = not merged),
`archived_at`. `email` is stored normalised and enforced by
`check (email = lower(btrim(email)))`; functions normalise with `lower(btrim(...))` before
every comparison and insert, so the matching key is exactly `lower(trim(email))`.
**Unique index on `email` where `merged_into_id is null`**: one record per email among all
unmerged clients, archived ones included. Created only by conversion or by `admin_create_client`.
`client_contacts` is not built (undecided).

Handling of duplicates and archived clients:

- _Archived_ clients stay in the unique index, so an archived client can never be silently
  duplicated. If a conversion's email matches an archived client, the conversion fails with
  `ES409` ("This client is archived. Restore it first."); `admin_update_client` can restore it.
  Conversion never un-archives anything on its own.
- _Merged_ clients (`merged_into_id` set) leave the index, keep their row and email for history, and
  are never matched. Their email can later belong to a new unmerged client.
- _Duplicates_ that differ in email (same agency, two addresses) cannot be detected automatically;
  the admin merges them. A merge target must be unmerged and un-archived, the source may be
  archived, and source ≠ target, so chains and cycles cannot form.
- Later inquiries from a matched client do not overwrite its contact details; admins edit them.

### `projects` (editor-safe columns only)

`title`, `brief_type`, `service_type_code` (FK `service_types`), `status` (default `draft`),
`status_before_hold`, `summary`, `deadline` (date), `requires_interpretation` (bool),
`proposed_amount numeric(12,2)` + `proposed_currency` (the pay offered to editors: not client
data; null until the admin sets it), `revision_allowance smallint` (default 3, KB), `current_brief_version
int`, `first_opened_at timestamptz` (set by `admin_set_project_status` the first time the
project becomes `open`; a trigger forbids changing or clearing it afterwards), `created_by`,
`archived_at`. Never any client identity or client price.

### `project_internal` (admin-only, 1:1 with `projects`)

`project_id` (PK, FK), `client_id` (FK `clients`, nullable for no-client projects),
`source_inquiry_id` (FK `client_inquiries`, unique), `client_price numeric(12,2)` +
`client_price_currency`, `internal_notes`.

### `brief_versions` (immutable once the project has been opened)

`project_id`, `version int` (unique with project), `change_summary`, `created_by`, and a full
snapshot of what editors will confirm against:
`instructions`; creative-led fields from KB §4.3 (`desired_outcome`, `audience`, `core_message`,
`brand_constraints`, `mandatory_content`, `prohibited_content`); `requires_reacknowledgement`;
`deliverables jsonb` and `references jsonb` (copies at that version). No grants for writes.
Triggers: **delete is always refused**; **update is refused unless the project's `first_opened_at`
is null** (the only allowed update is the pre-open edit of version 1, §8). So no row can change
after its project is first opened, whoever calls it.

### `project_deliverables`

`project_id`, `name`, `format`, `resolution`, `aspect_ratio`, `duration_seconds`, `notes`,
`sort_order`. The live working set; the version snapshot is the history.

### `project_references` (pulled forward from Phase 5, admin-only here)

KB §4.2: `project_id`, `title`, `url` (https only, as Phase 3 links), `start_seconds`,
`end_seconds` (check end ≥ start), `observation_notes`, `priority reference_priority`,
`category` (text, admin-defined, e.g. pacing, colour; no fixed list), `access_notes`, `sort_order`.
Phase 5 adds editor-visibility rules; Phase 4 grants nothing to editors. Uploaded reference files
are out of scope (links only).

### Change to `client_inquiries`

Add `converted_project_id uuid` (FK `projects`, indexed) with
`check ((status = 'converted') = (converted_project_id is not null))`. `admin_set_inquiry_status`
keeps refusing `converted`. Both link directions are written together by the conversion function
and verified by tests.

**Migration safety (existing data is not assumed empty).** Phase 3 makes `converted` unreachable
through the API, and no `projects` table exists yet, so any `converted` row could only come from
direct SQL and would have no project to point at. The migration therefore, in this order:

1. adds the column (nullable, no constraint);
2. runs a pre-flight check that counts rows with `status = 'converted'`; if the count is not zero
   it **aborts with a message naming the count** and changes nothing (no silent rewriting of an
   owner's data; the owner decides what those rows should be);
3. adds the check constraint `NOT VALID` and immediately runs `VALIDATE CONSTRAINT`, so the
   migration also fails loudly if a row would violate it, and the lock is short.

Local reset has zero such rows. Before applying to any hosted database (owner approval needed
anyway) the same count is run by hand first. The activity-log trigger already records
`inquiry.converted` when the status changes, so no audit change is needed.

### Relationships

```
client_inquiries 0..1 ── 1 project_internal ── 1 projects
clients 1 ── * project_internal            (clients merge via merged_into_id)
projects 1 ── * brief_versions | project_deliverables | project_references
```

## 6. Privileges and RLS

| Table                                                                                                     | anon | authenticated non-admin (editor A/B, applicant) | admin       |
| --------------------------------------------------------------------------------------------------------- | ---- | ----------------------------------------------- | ----------- |
| `clients`, `projects`, `project_internal`, `brief_versions`, `project_deliverables`, `project_references` | none | none (no select, no write)                      | select only |

`grant select ... to authenticated` plus one policy `using ((select private.is_admin()))` per
table; **no insert/update/delete grants or policies on any table.** All writes are
`security definer` functions with `set search_path = ''`. Phase 6 will add an editor `select`
policy on `projects` (and the editor-safe children) via `project_access`; it will never touch
`project_internal` or `clients`.

## 7. Functions (all `public`, `require_admin()` first, execute granted to anon + authenticated)

Inputs arrive as `jsonb` for nested data; each function validates and raises `ES422` with a plain
message. Each call is one transaction.

- `admin_create_project(p_input jsonb) → uuid`: project (status `draft`), `project_internal`,
  brief v1, deliverables, references. Optional `client_id`. Writes `project.created` audit.
- `admin_convert_inquiry(p_inquiry_id uuid, p_input jsonb) → uuid`: see §9.
- `admin_update_project(p_project_id, p_input jsonb)`: details (title, summary, deadline, service
  type, proposed pay, revision allowance, requires_interpretation, client price, internal notes).
  Never creates a version (see §8).
- `admin_save_brief(p_project_id, p_input jsonb) → int`: replaces instructions/creative fields,
  deliverables and references; versioning per §8; returns current version.
- `admin_set_project_status(p_project_id, p_status, p_note)`: transitions per §10.
- `admin_archive_project(p_project_id, p_archive boolean)`.
- `admin_create_client`, `admin_update_client`, `admin_merge_clients(p_source, p_target)`:
  merge moves `project_internal.client_id` to the target, sets `merged_into_id`, never deletes.
  (Merge is the first thing to cut if the migration gets too big; the column stays.)
- `private.require_admin()` is reused; any other helper (diffing, validation) lives in `private`.

Audit: the functions write `activity_logs` rows (action text, `details` with ids and status names
only, no personal data) for project create, brief version created, inquiry conversion and client
merge; project status changes are audited by a trigger, as `client_inquiries` does in Phase 3.

### Function security (every function this phase adds)

Phase 1 already sets default privileges so new functions created by `postgres` in `public` and
`private` carry no `PUBLIC`, `anon` or `authenticated` execute. Phase 4 does not rely on that
alone. Each migration function follows this pattern:

1. `create function ... language plpgsql security definer set search_path = ''`, created by the
   migration role (`postgres`), which is the owner; every reference inside is schema-qualified.
2. `revoke all on function <sig> from public, anon, authenticated;` explicitly, then
3. `grant execute on function <sig> to anon, authenticated;` for the `public.admin_*` functions only
   (they authorise in their body, so a permission error never reaches the caller; project
   guardrail). `private.*` helpers, trigger functions and the diff/validation helpers are revoked
   from `public, anon, authenticated` and granted to nobody; they run only inside definer
   functions or as triggers.
4. The first statement of every `admin_*` function is `private.require_admin()` (`ES401` signed
   out, `ES403` not admin or no MFA).

A pgTAP test enforces this for **all** functions in `public` and `private` (not just new ones):
every function is `security definer` where the project requires it, has `search_path` pinned to
empty in `proconfig`, is owned by `postgres`, and `proacl` shows no `PUBLIC` grantee; `public`
functions are executable by exactly `anon`, `authenticated` (+ owner); `private` helpers by nobody
except the ones RLS policies need (`is_admin`, as today).

## 8. Brief versioning rules

- **Before the first opening** (`first_opened_at is null`), `admin_save_brief` edits version 1 in
  place. No editor can have seen or confirmed it: editors have no access in Phase 4, and a later
  invitation (Phase 6) requires an opened project.
- **From the first opening on**, a version is never overwritten or deleted, by anyone, including
  the database owner's functions (trigger-enforced, §5). A call that changes instructions,
  creative-led fields, deliverables or references (compared per the rules in §14) creates version
  n+1 with a full snapshot and a required `change_summary`. Reverting `open → draft` does not
  reopen the in-place window.
- **There is no "minor correction" mechanism.** A typo fixed after opening is a new version with
  `requires_reacknowledgement = false`. This guarantees a confirmed version is never altered.
- Title and summary edits (via `admin_update_project`) never create a version.
- **Re-acknowledgement rules.** Every version after the first carries `requires_reacknowledgement`.
  It is forced `true` when the deliverables changed; otherwise it defaults `true` and the admin may
  set it `false` with the `change_summary` as the recorded reason. Phase 4 stores and audits the
  flag; Phase 7 applies it: an editor's confirmation is tied to one version, and a later version
  with `requires_reacknowledgement = true` means the editor must confirm again before work
  continues, while `false` lets the earlier confirmation carry forward (recorded as carried
  forward, never as a new confirmation).
- Phase 7 must add `brief_confirmations.brief_version_id` as `on delete restrict` and make
  confirmation rows immutable; this design needs no change for that (§15).
- **Open for Phase 7, not decided here:** deadline and proposed-pay changes do not bump the
  version in Phase 4; Phase 7's confirmation stores deadline, deliverables and amount at
  confirmation time, so it can detect drift itself. Listed in §14.

## 9. Inquiry conversion (`admin_convert_inquiry`)

One transaction:

1. `require_admin()`; `select ... for update` on the inquiry (serialises double clicks).
2. Inquiry must exist and be `new`, `reviewing`, `contacted` or `in_discussion`. `converted` →
   `ES409`; `declined`/`closed`/`spam` → `ES409` ("reopen it first").
3. Match on `lower(btrim(email))` among unmerged clients; if the match is archived, fail `ES409`
   (§5). With no match, insert one from the inquiry's contact fields (`on conflict` on the unique
   email index makes a race safe: the loser re-reads the winner's row). The admin can instead
   pass an existing unmerged, un-archived `client_id`.
4. Insert project (`draft`) prefilled from the inquiry (service type, deadline, description →
   summary draft) overridden by `p_input`, `project_internal` (client, `source_inquiry_id`),
   brief v1, deliverables, references.
5. Set inquiry `status = 'converted'`, `converted_project_id`, `status_changed_at/by`.
6. Audit rows. Any error rolls everything back, including the client insert.

Returns the project id. Client price is never copied from the inquiry's budget label.

## 10. Status transitions (Phase 4 subset)

Admin-driven in this phase: `draft → open`, `open → draft`, `draft|open → cancelled`,
`draft|open → on_hold` (stores `status_before_hold`), `on_hold → previous status`. A `cancelled`
project is terminal. Moving to `assigned` and beyond is refused (`ES409`); those transitions
belong to the Phase 6-9 functions. `open` additionally requires: title, brief type, ≥1
deliverable, a deadline, non-empty instructions (fully instructed), ≥1 reference (reference-based),
a desired outcome (creative-led). Proposed pay is **not** required to open (compensation is
agreed in Phase 6). `open` exposes nothing yet: editors have no policy until Phase 6.

## 11. Test plan

pgTAP `040_phase4_projects.test.sql`, run through `npm run db:test`, with identities admin
(aal2), editor A, editor B, pending applicant, anon.

- For every new table: non-admin and anon read zero rows; direct insert/update/delete denied;
  admin direct writes denied too (functions only). The existing RLS guardrail and function-grant
  guardrail must stay green.
- Each function: anon and non-admin get `ES401`/`ES403`; admin without MFA denied.
- Creation: all three brief types succeed; each validation rule fails with `ES422` (bad URL,
  end before start, missing instructions for fully instructed, no references for reference-based
  when opening, too-long fields, bad currency).
- Conversion: happy path creates exactly one client, project, internal row, v1 and sets both links;
  repeat inquiry from the same email reuses the client; **forced failure** (invalid input after
  the client insert) leaves no client, no project and the inquiry unchanged; second conversion
  `ES409`; declined/spam/closed refused; two-session concurrent conversion yields one project;
  `admin_set_inquiry_status` still refuses `converted`; the check constraint holds.
- Versioning: edits before first opening stay v1 in place; after first opening a content change
  makes v2 with a faithful snapshot and v1 is byte-for-byte unchanged; `open → draft → edit` still
  makes a new version; a deliverables change forces `requires_reacknowledgement`; title-only edit
  makes no version; direct `update`/`delete` on `brief_versions` after first opening is refused
  even for a superuser-run function; `first_opened_at` cannot be changed or cleared; delete is
  refused always.
- Function security: the catalogue test in §7 (owner, `security definer`, empty `search_path`,
  no `PUBLIC` grantee, expected grantees) over every function in `public` and `private`.
- Migration: a pre-flight test inserts a fake `converted` inquiry (as superuser) into a scratch
  copy and asserts the migration step aborts with the count message; with zero rows it passes.
- Status: every allowed transition, every refused one, hold/resume round trip, open-readiness rules.
- Clients: email stored as `lower(btrim(...))` (mixed case and padded input match the same client);
  unique among unmerged clients including archived; conversion matching an archived client fails
  `ES409`; merged clients are not matched and free their email; merge moves projects and refuses
  merged, archived or identical targets.
- Data hygiene: no client identity or client price in `projects`, `brief_versions`,
  `project_deliverables`, `project_references` (column-name guard test).
- Then `npm run db:advisors`, `npm run db:types`, and the `db-security` agent review before any UI
  work starts.

Second commit (screens, planned separately): `/admin/projects` list, create and edit, brief
editor with the three type layouts, references and deliverables editors, "Convert to project" on
the inquiry page, and a minimal clients list. Vitest for input parsing, Playwright for the signed-out
gate, status labels via the existing `StatusPill`.

## 12. Docs to update with the migration

`DATABASE_SCHEMA.md` (tables as built; references moved to Phase 4), `DEVELOPMENT_ROADMAP.md`,
`WORKFLOWS.md` §1/§3, `SECURITY_AND_PRIVACY.md` (new tables in the access matrix),
`CURRENT_STATUS.md`, `CHANGELOG.md`.

## 13. Left to the builder

Column lengths and check constraints, index choices, exact jsonb input shapes, error message
wording, migration file split (one file is expected), and test fixtures.

## 14. My calls and open items (owner may override)

Calls made in this document: proposed editor pay lives on `projects` (not client data), client
price in `project_internal`; in-place edits only before first opening (§8); version snapshot stored
as jsonb copies; deadline and pay changes do not bump the version; references use seconds for
timecodes and free-text categories; `open` readiness rules in §10; client merge included;
`converted_project_id` added alongside `source_inquiry_id`.

Revision of 2026-11-13 (owner review): removed the minor-correction mechanism (no way to alter a
version after opening); defined re-acknowledgement; normalised email matching and defined archived,
merged and duplicate clients; added the function-security checklist and catalogue test; added the
safe migration for `converted_project_id`.

Calls added after the builder check (all mine; none changes the scope you approved):

- **Edits by state.** Every write function refuses `cancelled` and archived projects (`ES409`).
  `on_hold` allows edits; versioning follows the normal rule.
- **In-place v1 edits.** `projects.first_opened_at` (set the first time a project becomes `open`)
  replaces "while draft": v1 is rewritten in place only if `first_opened_at is null`. Reverting
  `open → draft` never reopens that window.
- **Matching deliverables and references.** Input items may carry their `id`. Items with an id are
  updated in place (ids stay stable for Phase 7/8 foreign keys), items without one are inserted,
  existing items missing from the input are removed. A "change" is any trimmed field value
  differing, or an item added or removed. Reordering alone (`sort_order`) and whitespace-only edits
  are not changes.
- **Conversion link.** `source_inquiry_id` is unique and a `converted` inquiry never leaves that
  status (the existing function refuses it). A cancelled project keeps its inquiry `converted`;
  there is no "un-convert" in Phase 4.
- **Client matching and merge.** `client_inquiries.email` is already `not null`; match key is
  `lower(btrim(email))` (§5). Merge repoints only `project_internal.client_id` (the one table that
  references clients), requires an unmerged, un-archived target that differs from the source, so
  chains and cycles cannot form. No un-merge in Phase 4.
- **Audit.** Functions write `activity_logs` rows directly (action text, `details` jsonb with ids
  only), matching the Phase 3 pattern; no new enum is needed. Status-change auditing on `projects`
  also uses a trigger like `client_inquiries`.
- **Errors.** `require_admin()` already distinguishes signed-out (`ES401`) from non-admin or
  no-MFA (`ES403`); tests assert those codes.
- **Allowance.** `revision_allowance` is only a stored number; consumption is Phase 8.

Open, not blocking Phase 4: decision H (currency policy; we only store a currency with each
amount), decision B (what editors see before assignment, Phase 5/6), whether
deadline/pay changes should force re-acknowledgement (Phase 7).

## 15. Constraints this design hands to later phases

- Phase 6: `project_access` (invitations) may only be created for projects with
  `first_opened_at is not null`; `open → draft` should be refused once any `project_access` or
  assignment exists.
- Phase 7: `brief_confirmations.brief_version_id` is `on delete restrict`; confirmation rows are
  immutable; a confirmation is only accepted for the project's current version; carry-forward on
  `requires_reacknowledgement = false` is recorded as such.
- Phase 5/6: editor `select` policies cover `projects`, `project_deliverables`,
  `project_references` and `brief_versions` only, never `project_internal` or `clients`.

## 16. Consistency with Phases 0-3

Same patterns, reused unchanged: `private` schema helpers, `private.require_admin()`/`is_admin()`,
function-only writes with ES4xx errors, `set_updated_at` triggers, `activity_logs` with ids only,
default-deny RLS with explicit grants, `numeric(12,2)` + currency, migrations append-only. Checked
against the Phase 1 default-privilege setup, the Phase 2 `require_admin`, and the Phase 3 inquiry
table, status function and audit trigger. The only change to an earlier table is the added
`client_inquiries.converted_project_id`, done by a new migration, never by editing Phase 3.
