# Database Schema (proposed)

Status: **Phase 1, 2 and 3 tables migrated.** Phase 3 (`20261111140306_phase3_public_inquiries.sql`): `service_types`, `budget_ranges`, `client_inquiries`, `client_inquiry_links`, `inquiry_notes`, `private.inquiry_throttle` (see the inquiries section below for columns as built: labels copied at submission, `budget_label`/`budget_currency`, `client_notes`, `privacy_notice_version`; no assigned-admin column yet; `converted_project_id` arrives with Phase 4). Phase 1 (`20261111122133_phase1_auth_access.sql`): `profiles`, `admin_users`, `editor_profiles` access columns, `activity_logs`. Phase 2 (`20261111133128_phase2_editor_applications.sql`): editor profile fields + `level`, `profile_options` (admin-managed list, seeded from KB §7.1/§7.3), `editor_profile_options`, `editor_portfolio_links`, `editor_applications` (with frozen `submitted_snapshot`), `application_requests` (info requests and practical tests, incl. assessment result), `editor_vetting_notes`. All workflow writes go through `public.*` functions (see SECURITY_AND_PRIVACY). **Everything else is proposed, not yet migrated.** Helper functions live in the `private` schema. Derived from KB §11.4, the Phase 0 architecture review and
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
| **Added** `clients` (+ `client_contacts`)                   | Optional, question T: repeat clients/agencies across inquiries and projects.                                                                                                                                                                             |
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

| Table                        | Purpose / key columns                                                                                                                                                                                                                                                      | Created |
| ---------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| `client_inquiries`           | contact name, company/agency, email, phone, service type, description, expected deliverables, estimated budget (+ currency, question V), expected deadline, notes, status (question N), assigned admin, consent/privacy-notice version, submitted_at, converted_project_id | Phase 3 |
| `client_inquiry_links`       | inquiry, url, label (one row per reference link)                                                                                                                                                                                                                           | Phase 3 |
| `inquiry_notes`              | admin-only internal notes on an inquiry                                                                                                                                                                                                                                    | Phase 3 |
| `service_types`              | admin-managed list used by the inquiry form and projects (KB §17.3 stays configurable)                                                                                                                                                                                     | Phase 3 |
| `clients`, `client_contacts` | optional (question T)                                                                                                                                                                                                                                                      | Phase 4 |

## Projects and briefs

| Table                  | Purpose / key columns                                                                                                                                                                  | Created                      |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------- |
| `projects`             | **editor-safe fields only**: title, brief type, service type, status, summary, deadline, `requires_interpretation`, current brief version, revision allowance (default 3), archived_at | Phase 4                      |
| `project_internal`     | **admin-only**: client_id / client name, source_inquiry_id, client price, currency, internal notes                                                                                     | Phase 4                      |
| `brief_versions`       | project, version, instructions, creative-led fields, `requires_reacknowledgement`                                                                                                      | Phase 4                      |
| `project_deliverables` | project, name, format/resolution/aspect/duration, notes                                                                                                                                | Phase 4                      |
| `project_assets`       | project, label, url, provider, visibility stage (`opportunity`/`assigned`, question B)                                                                                                 | Phase 5                      |
| `project_references`   | KB §4.2 fields: title, url/file ref, start/end timecode, observation notes, priority, category, access notes                                                                           | Phase 5                      |
| `asset_access_grants`  | asset or project folder, editor, shared-with account email, shared_by/at, revoked_by/at                                                                                                | Phase 5 (if K = per-account) |

## Assignment and agreement

| Table                    | Purpose / key columns                                                                                                               | Created |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- | ------- |
| `project_access`         | project, editor, granted_by, reason (invited/available). Drives editor visibility                                                   | Phase 6 |
| `assignments`            | project, editor, status, proposed/agreed amount, currency, confirmed_by/at. Partial unique index: one active assignment per project | Phase 6 |
| `negotiation_offers`     | append-only: assignment, from role, amount, message, outcome                                                                        | Phase 6 |
| `editor_interpretations` | assignment, brief version, content, status, admin feedback                                                                          | Phase 7 |
| `brief_confirmations`    | KB §5.1 fields, storing a copy of deadline, deliverables, amount at confirmation time                                               | Phase 7 |

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
projects 1─* brief_versions, project_deliverables, project_assets, project_references
projects 1─* project_access *─1 editor_profiles
projects 1─* assignments *─1 editor_profiles   (≤1 active per project)
assignments 1─* negotiation_offers, brief_confirmations, submissions, payments
```

## RLS summary

See SECURITY_AND_PRIVACY.md for the full model and the per-identity access matrix.
