# Database Schema (proposed)

Status: **proposed, not yet migrated.** Derived from KB §11.4 plus the approved architecture review.
Each table is created in the phase that needs it (see DEVELOPMENT_ROADMAP). Update this file in
the same change as the migration.

Conventions: `uuid` PKs, `created_at`/`updated_at` timestamptz, FKs indexed, enums for statuses,
`archived_at` for soft-archive, money as `numeric(12,2)` + `currency` (default LKR, OPEN_QUESTIONS H).

## Identity and editors

| Table                    | Purpose / key columns                                                                                                                         |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `profiles`               | id = `auth.users.id`; role (`admin`/`editor`); full name, email, phone                                                                        |
| `editor_profiles`        | application status, level, region, experience, software, availability, turnaround, optional hardware, terms/privacy acceptance version + time |
| `editor_skills`          | editor, specialisation (one row each)                                                                                                         |
| `editor_portfolio_links` | editor, url, label                                                                                                                            |
| `editor_vetting_notes`   | admin-only notes, test outcome                                                                                                                |
| `editor_payout_details`  | admin + owning editor only; fields pending OPEN_QUESTIONS E                                                                                   |

## Projects and briefs

| Table                  | Purpose / key columns                                                                                                                                                    |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `projects`             | **editor-safe fields only**: title, brief type, status, summary, deadline, `requires_interpretation`, current brief version, revision allowance (default 3), archived_at |
| `project_internal`     | **admin-only**: client name, client price, currency, internal notes                                                                                                      |
| `brief_versions`       | project, version, instructions, creative-led fields, `requires_reacknowledgement`                                                                                        |
| `project_deliverables` | project, name, format/resolution/aspect/duration, notes                                                                                                                  |
| `project_assets`       | project, label, url, provider, visibility stage (`opportunity`/`assigned`)                                                                                               |
| `project_references`   | KB §4.2 fields: title, url/file ref, start/end timecode, observation notes, priority, category, access notes                                                             |

## Assignment and agreement

| Table                    | Purpose / key columns                                                                                                               |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| `project_access`         | project, editor, granted_by, reason (invited/available). Drives editor visibility                                                   |
| `assignments`            | project, editor, status, proposed/agreed amount, currency, confirmed_by/at. Partial unique index: one active assignment per project |
| `negotiation_offers`     | append-only: assignment, from role, amount, message, outcome                                                                        |
| `editor_interpretations` | assignment, brief version, content, status, admin feedback                                                                          |
| `brief_confirmations`    | KB §5.1 fields, storing a copy of deadline, deliverables, amount at confirmation time                                               |

## Delivery, money, audit

| Table               | Purpose / key columns                                                                                                            |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `submissions`       | assignment, version number, link, notes, export details, review outcome, feedback, reviewer, timestamps                          |
| `revision_requests` | type (`client_revision`/`editor_correction`/`scope_change`), counts-against-allowance (derived), round number, reason, status    |
| `payments`          | assignment, editor, amount, currency, status, due date, transfer date, transaction reference, approved_by, marked_paid_by, notes |
| `activity_logs`     | actor, entity type/id, action, before/after, timestamp. No update/delete for anyone                                              |

Pending owner decisions that may add tables: project communication (C6 in KB §17), compensation
adjustments for scope changes (F), non-project payments for paid tests (G).

## RLS summary

See SECURITY_AND_PRIVACY.md for the full model.
