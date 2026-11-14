# Database Schema (proposed)

Status: **Phase 1 to 4 tables migrated.** Phase 4 (`20261114050211_phase4_schema.sql`, `..050359_phase4_inquiry_link.sql`, `..050658_phase4_brief_helpers_and_create.sql`, `..051059_phase4_brief_versioning.sql`, `..051417_phase4_project_status.sql`, `..051655_phase4_clients_and_conversion.sql`; on branch `phase4-projects`, uncommitted): `clients`, `projects`, `project_internal`, `brief_versions`, `project_deliverables`, `project_references`, `client_inquiries.converted_project_id`; read-only for admins through RLS, all writes through `public.admin_*` functions (see the Projects and briefs section). Phase 3 (`20261111140306_phase3_public_inquiries.sql`): `service_types`, `budget_ranges`, `client_inquiries`, `client_inquiry_links`, `inquiry_notes`, `private.inquiry_throttle` (see the inquiries section below for columns as built: labels copied at submission, `budget_label`/`budget_currency`, `client_notes`, `privacy_notice_version`; no assigned-admin column yet; `converted_project_id` added in Phase 4). Phase 1 (`20261111122133_phase1_auth_access.sql`): `profiles`, `admin_users`, `editor_profiles` access columns, `activity_logs`. Phase 2 (`20261111133128_phase2_editor_applications.sql`): editor profile fields + `level`, `profile_options` (admin-managed list, seeded from KB §7.1/§7.3), `editor_profile_options`, `editor_portfolio_links`, `editor_applications` (with frozen `submitted_snapshot`), `application_requests` (info requests and practical tests, incl. assessment result), `editor_vetting_notes`. All workflow writes go through `public.*` functions (see SECURITY_AND_PRIVACY). **Everything not listed above is proposed, not yet migrated.** Helper functions live in the `private` schema. Derived from KB §11.4, the Phase 0 architecture review and
the owner clarification of 2026-11-11. Each table is created in the phase that needs it (see
DEVELOPMENT_ROADMAP). Update this file in the same change as the migration.

Conventions: `uuid` PKs, `created_at`/`updated_at` timestamptz, FKs indexed, enums for statuses,
`archived_at` for soft-archive, money as `numeric(12,2)` + `currency` (OPEN_QUESTIONS H).

## Changes from the Phase 0 proposal (2026-11-11)

| Change                                                      | Why                                                                                                                                                                                                                                                      |
| ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Removed** `profiles.role`; **added** `admin_users`        | Self-registration means every new account is untrusted. Admin status lives in a table nobody can write to except an existing admin's audited function or the owner's bootstrap step. One admin at launch, more later without schema change (decision A). |
| **Added** `editor_profiles.access_status`                   | The single switch for editor access (`none`/`active`/`suspended`/`revoked`, decision L).                                                                                                                                                                 |
| **Split** application out into `editor_applications`        | Application review progress is separate from access, and keeps history if re-application is allowed (question M).                                                                                                                                        |
| **Added** `application_requests`, `editor_assessments`      | Admin "request more information" and practical tests, with applicant responses.                                                                                                                                                                          |
| **Added** `client_inquiries`, `client_inquiry_links`        | Public inquiries, kept apart from projects (no account, no automatic project).                                                                                                                                                                           |
| **Added** `clients` (+ `client_contacts`)                   | Decision T (2026-11-13): minimal admin-only `clients` table, created at first conversion, for repeat clients/agencies. `client_contacts` is not decided.                                                                                                 |
| **Added** `project_internal.source_inquiry_id`, `client_id` | Conversion link lives in the admin-only table, never on editor-visible `projects`.                                                                                                                                                                       |
| **Added** `asset_access_grants`                             | Tracks manual Drive/Dropbox sharing per editor so revocation can be checked (question K).                                                                                                                                                                |

## Identity, roles and editors

| Table                    | Purpose / key columns                                                                                                                                                               | Created                               |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- |
| `profiles`               | id = `auth.users.id`; full name, email, phone. **No role column.** Created by sign-up trigger                                                                                       | Phase 1                               |
| `admin_users`            | user_id (PK, FK profiles), granted_by, granted_at, revoked_at. Future: permission set (A2, Phase 9)                                                                                 | Phase 1                               |
| `editor_profiles`        | user_id (PK); `access_status` (default `none`); level; region; experience; software; availability; turnaround; optional hardware; activated_by/at; suspended/revoked by/at + reason | Phase 1 (status) / 2 (profile fields) |
| `editor_applications`    | editor (FK), status (decision L), submitted_at, reviewed_by, decided_by/at, decision reason, terms + privacy acceptance version/time                                                | Phase 2                               |
| `editor_skills`          | editor, specialisation (one row each)                                                                                                                                               | Phase 2                               |
| `editor_portfolio_links` | editor, url, label                                                                                                                                                                  | Phase 2                               |
| `application_requests`   | application, requested_by, message, response, responded_at, status                                                                                                                  | Phase 2                               |
| `editor_assessments`     | application, brief/instructions link, submission link, result, notes, paid? (question G)                                                                                            | Phase 2                               |
| `editor_vetting_notes`   | admin-only notes per application                                                                                                                                                    | Phase 2                               |
| `editor_payout_details`  | decision E: account holder name, bank, branch, account number, `verification_status` (unverified/verified), verified_by/at; owner editor + admins only; change history audited      | Phase 9                               |

## Client inquiries and clients _(2026-11-11)_

| Table                                   | Purpose / key columns                                                                                                                                                                                                                                                       | Created |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| `client_inquiries`                      | contact name, company/agency, email, phone, service type, description, expected deliverables, estimated budget (+ currency, question V), expected deadline, notes, status (question N), assigned admin, consent/privacy-notice version, submitted_at, converted_project_id  | Phase 3 |
| `client_inquiry_links`                  | inquiry, url, label (one row per reference link)                                                                                                                                                                                                                            | Phase 3 |
| `inquiry_notes`                         | admin-only internal notes on an inquiry                                                                                                                                                                                                                                     | Phase 3 |
| `service_types`                         | admin-managed list used by the inquiry form and projects (KB §17.3 stays configurable)                                                                                                                                                                                      | Phase 3 |
| `clients`                               | **Built (decision T), admin-only:** name, company, email (stored `lower(btrim)`; unique among unmerged clients, archived included), phone, notes, `merged_into_id`, `archived_at`, created_by. Writes via `admin_create_client`/`admin_update_client`/`admin_merge_clients` | Phase 4 |
| `client_contacts`                       | not decided                                                                                                                                                                                                                                                                 | n/a     |
| `client_inquiries.converted_project_id` | FK to `projects` (`on delete restrict`), indexed; check: `status = 'converted'` iff set. Set only by `admin_convert_inquiry`                                                                                                                                                | Phase 4 |

## Projects and briefs _(built in Phase 4)_

All tables below: RLS on, `select` for admins only (`private.is_admin()`), no insert/update/delete
grants. Every write goes through a `public.admin_*` function (`admin_create_project`,
`admin_save_brief`, `admin_update_project`, `admin_set_project_status`, `admin_archive_project`,
`admin_convert_inquiry`). Enums: `project_status` (all ten values created now), `brief_type`
(`fully_instructed`/`reference_based`/`creative_led`), `reference_priority` (`essential`/`optional`).

| Table                  | Purpose / key columns                                                                                                                                                                                                                                                                                                                                                    | Created |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------- |
| `projects`             | **editor-safe fields only**: title, `brief_type`, `service_type_code`, `status` (default `draft`), `status_before_hold`, summary, deadline, `requires_interpretation`, `proposed_amount` + `proposed_currency` (pay offered to editors), `revision_allowance` (default 3), `current_brief_version`, `first_opened_at` (set once, never cleared), created_by, archived_at | Phase 4 |
| `project_internal`     | **admin-only, 1:1 with `projects`**: `client_id` (FK `clients`), `source_inquiry_id` (unique FK `client_inquiries`), `client_price` + `client_price_currency`, internal notes                                                                                                                                                                                            | Phase 4 |
| `brief_versions`       | project, `version` (unique per project), `change_summary`, created_by, `instructions`, `desired_outcome`, `audience`, `core_message`, `brand_constraints`, `mandatory_content`, `prohibited_content`, `requires_reacknowledgement`, `deliverables` and `"references"` (jsonb snapshots). Immutable once the project has been opened                                      | Phase 4 |
| `project_deliverables` | live rows: project, name, format/resolution/aspect_ratio/duration_seconds, notes, sort_order                                                                                                                                                                                                                                                                             | Phase 4 |
| `project_references`   | **pulled forward from Phase 5**; KB §4.2 fields as links only (`https://`): title, url, start/end seconds, observation notes, `priority`, category, access notes, sort_order. Admin-only for now                                                                                                                                                                         | Phase 4 |

Phase 6 adds editor `select` policies to `projects`, `project_deliverables`, `project_references`
(plus `early_access boolean`, Phase 5) and `brief_versions`; see below.

Constraints worth knowing: `projects_hold_state_chk` (`status_before_hold` set iff `on_hold`);
`first_opened_at` guarded by `private.guard_first_opened_at`; `brief_versions` guarded by
`private.guard_brief_versions`; project changes audited by `private.audit_projects`.

## Assets, access, offers and assignments _(Phases 5-6, implemented on branch, pending owner review)_

Spec `docs/superpowers/specs/2026-11-14-phase5-6-editor-access-design.md`; plan calls in
`docs/superpowers/plans/2026-11-14-phase5-6-database.md` (awaiting owner review). Migrations
`20261114061439` to `20261114063650`. No direct writes for anyone: admin writes via
`public.admin_*` (`require_admin()`), editor writes via `public.editor_respond_offer`
(`private.require_active_editor()`). Enums: `asset_provider`, `project_access_reason`
(`invited`/`available`), `assignment_status` (`offered`, `counteroffer_pending`, `accepted`,
`confirmed`, `in_progress` (Phase 7), `declined`, `withdrawn`, `not_selected`, `reassigned`), `negotiation_role`,
`negotiation_action` (`offer`/`counter`/`accept`/`decline`/`withdraw`).

| Table                 | Key columns / rules                                                                                                                                                                                                                           | Editor reads                         |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| `project_assets`      | project (cascade), label, https url, `provider`, `kind` (free text ≤40), notes, `early_access`, sort_order. Synced by `admin_save_assets` (never bumps the brief version)                                                                     | `assigned`, or `opportunity` + early |
| `asset_access_grants` | manual folder shares (decision K): project, editor, `shared_with_email` (normalised), provider, folder_url, shared/revoked by/at, revoke_reason. One live grant per (project, editor, email). Revoke checklist: `admin_pending_revocations()` | never                                |
| `project_access`      | project, editor, `reason`, granted/revoked by/at. One live row per (project, editor)                                                                                                                                                          | own rows (active editors)            |
| `assignments`         | project, editor, `status`, `proposed_amount` + `currency`, `agreed_amount` + `agreed_currency` (set on accept), confirmed_by/at, closed_at. One live row per (project, editor); one `confirmed` per project; transitions guarded by trigger   | own rows (active editors)            |
| `negotiation_offers`  | append-only (update/delete refused by trigger, except `created_by` set null): assignment, `from_role`, `action`, amount + currency (null for decline/withdraw), message ≤2000                                                                 | rows of own assignments              |
| `project_notes`       | admin notes log (KB6), append-only: project, author, note ≤4000                                                                                                                                                                               | never                                |

Editor stage: `private.editor_project_stage(project)` = `none` unless active editor and the project
is not cancelled/archived; `assigned` with a `confirmed` (or, from Phase 7, `in_progress`) assignment; `opportunity` with live access
or a live (`offered`/`counteroffer_pending`/`accepted`) assignment. `projects` and
`project_deliverables` visible at both stages; `brief_versions` (all versions) at `assigned`.
Assignment status changes are audited by trigger (`assignment.<status>`, ids and statuses only).

## Interpretation, brief confirmation and the in-progress gate _(Phase 7, implemented on branch, pending owner review)_

Spec `docs/superpowers/specs/2026-11-14-phase7-confirmation-gate-design.md`; plan calls in
`docs/superpowers/plans/2026-11-14-phase7-database.md` (awaiting owner review). Migrations
`20261114115858` to `20261114121138`. `assignment_status` gains `in_progress` (after `confirmed`);
new enums `interpretation_status` (`submitted`/`accepted`/`changes_requested`) and
`brief_confirmation_kind` (`confirmed`/`carried_forward`). Writes only via functions.

| Table / change           | Key columns / rules                                                                                                                                                                                                                                                                                                                                              | Editor reads              |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------- |
| `assignments` (changed)  | `started_at`, `started_by`; `in_progress` needs agreed pay, `confirmed_at` and `started_at`; one live row per (project, editor) incl. `in_progress`; `assignments_one_active_key`: one `confirmed`/`in_progress` per project; new transitions `confirmed → in_progress`, `in_progress → reassigned/withdrawn`                                                    | own rows (active editors) |
| `editor_interpretations` | append-only history, one row per submission: assignment, brief version (current at submission), `will_reproduce`/`will_adapt`/`questions_limitations` (≤4000, one of the first two required), `status`, `admin_feedback` (required for `changes_requested`), submitted/reviewed by/at. One `submitted` per assignment; content immutable, one review update only | rows of own assignments   |
| `brief_confirmations`    | immutable: assignment, project, editor, `brief_version_id` (restrict) + `brief_version`, `kind`, `carried_from_id` (iff carried), copies of deadline, deliverables, agreed amount + currency, created_by, `confirmed_at`. One carried row per (assignment, version); insert trigger checks project/editor/version                                                | own rows (active editors) |

Gate: `private.assignment_gate(assignment)` (compensation approved, interpretation required/accepted,
current vs confirmed version, deadline/amount/deliverables drift, `brief_confirmed`, `ready`) is the
only encoding of the rule. `BEFORE UPDATE` triggers refuse `assignments → in_progress` unless
`ready`, and `projects → in_progress` without an `in_progress` assignment. An `AFTER INSERT` trigger
on `brief_versions` writes `carried_forward` rows when `requires_reacknowledgement = false` and the
latest confirmation is for the previous version. Interpretations stay valid until a version with
`requires_reacknowledgement = true` (`private.material_brief_version`). Editor stage `assigned`
covers `confirmed` and `in_progress`. Read-only `public.get_assignment_gate` for admin or the owning
editor.

## Delivery, money, audit

| Table               | Purpose / key columns                                                                                                                                                                             | Created |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| `submissions`       | assignment, version number, link, notes, export details, review outcome, feedback, reviewer, timestamps                                                                                           | Phase 8 |
| `revision_requests` | type (`client_revision`/`editor_correction`/`scope_change`), counts-against-allowance (derived), round number, reason, status                                                                     | Phase 8 |
| `payments`          | assignment (nullable if question G allows test payments), editor, type, amount, currency, status (question I), due date, transfer date, transaction reference, approved_by, marked_paid_by, notes | Phase 9 |
| `activity_logs`     | actor, entity type/id, action, before/after, timestamp. No update/delete for anyone                                                                                                               | Phase 1 |

Possible later additions, pending decisions: compensation adjustments (F), project communication
log (KB §17.6), notification outbox (KB §17.10).

## Key relationships

```
auth.users 1─1 profiles 1─0..1 admin_users
                      1─1 editor_profiles 1─* editor_applications 1─* application_requests
                                                                  1─* editor_assessments
client_inquiries 1─* client_inquiry_links
client_inquiries 0..1─1 project_internal ─1 projects     (link only via admin-only table)
client_inquiries.converted_project_id ─> projects         (set by admin_convert_inquiry)
clients 1─* project_internal; clients.merged_into_id ─> clients  (merge repoints, never deletes)
projects 1─* brief_versions, project_deliverables, project_references (Phase 4); project_assets (Phase 5)
projects 1─* project_access *─1 editor_profiles
projects 1─* assignments *─1 editor_profiles   (≤1 confirmed/in_progress per project)
projects 1─* asset_access_grants *─1 editor_profiles; projects 1─* project_notes
assignments 1─* negotiation_offers (Phase 6), editor_interpretations, brief_confirmations (Phase 7), submissions, payments
brief_versions 1─* editor_interpretations, brief_confirmations (restrict); brief_confirmations.carried_from_id ─> brief_confirmations
```

## RLS summary

See SECURITY_AND_PRIVACY.md for the full model and the per-identity access matrix.
