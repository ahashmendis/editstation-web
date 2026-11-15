# Database Schema (proposed)

Status: **Phase 1 to 4 tables migrated; Phases 5-9 on branch** (Phase 8: `20261114154439_phase8_schema.sql`, `..154444_phase8_functions.sql`, `..154448_phase8_earlier_phase_changes.sql`: `submissions`, `revision_requests`, uncommitted). Phase 4 (`20261114050211_phase4_schema.sql`, `..050359_phase4_inquiry_link.sql`, `..050658_phase4_brief_helpers_and_create.sql`, `..051059_phase4_brief_versioning.sql`, `..051417_phase4_project_status.sql`, `..051655_phase4_clients_and_conversion.sql`; on branch `phase4-projects`, uncommitted): `clients`, `projects`, `project_internal`, `brief_versions`, `project_deliverables`, `project_references`, `client_inquiries.converted_project_id`; read-only for admins through RLS, all writes through `public.admin_*` functions (see the Projects and briefs section). Phase 3 (`20261111140306_phase3_public_inquiries.sql`): `service_types`, `budget_ranges`, `client_inquiries`, `client_inquiry_links`, `inquiry_notes`, `private.inquiry_throttle` (see the inquiries section below for columns as built: labels copied at submission, `budget_label`/`budget_currency`, `client_notes`, `privacy_notice_version`; no assigned-admin column yet; `converted_project_id` added in Phase 4). Phase 1 (`20261111122133_phase1_auth_access.sql`): `profiles`, `admin_users`, `editor_profiles` access columns, `activity_logs`. Phase 2 (`20261111133128_phase2_editor_applications.sql`): editor profile fields + `level`, `profile_options` (admin-managed list, seeded from KB §7.1/§7.3), `editor_profile_options`, `editor_portfolio_links`, `editor_applications` (with frozen `submitted_snapshot`), `application_requests` (info requests and practical tests, incl. assessment result), `editor_vetting_notes`. All workflow writes go through `public.*` functions (see SECURITY_AND_PRIVACY). **Everything not listed above is proposed, not yet migrated.** Helper functions live in the `private` schema. Derived from KB §11.4, the Phase 0 architecture review and
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

| Table               | Purpose / key columns                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | Created |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| `submissions`       | **Built (Phase 8).** Append-only, one row per version: assignment, project, editor (must match), `version` (per project, unique), `link` (https ≤2048), notes ≤4000, `export_details` ≤2000, `revision_request_id` (answered request), `confirmed_deadline` (from the latest brief confirmation), `is_late` (Asia/Colombo date > confirmed deadline; display only, KB5), submitted_by/at, `outcome` (`submission_outcome`), `feedback` (required unless approved), reviewed_by/at. One unreviewed per assignment; one review update                                         | Phase 8 |
| `revision_requests` | **Built (Phase 8).** project, assignment, `submission_id`, `type` (`client_revision`/`editor_correction`/`scope_change`), `counts_against_allowance` (generated), `round_number` (client revisions only, 1..n per project), `beyond_allowance` (round > `projects.revision_allowance`; no pay computed, F), `reason` (for the editor), `status` (`requested`/`acknowledged`/`in_progress`/`resubmitted`/`approved`/`disputed`), acknowledged/resubmitted/resolved at, created_by, classified_by/at. One open per assignment; no deletes                                     | Phase 8 |
| `payments`          | **Built (Phase 9).** assignment (not null; G may relax), project, editor, `kind` (`assignment`/`reversal`), amount (negative for reversals), currency, `payment_status` (I: `not_due`→`pending_approval`→`approved`→`processing`→`paid`, `on_hold` + reason + `held_from_status`), due date, transfer date, transaction reference, reversal link/reason, approved_by/at, marked_paid_by/at. Created by trigger at assignment confirmation; held by trigger when the assignment is reassigned/withdrawn. Paid rows immutable; corrections are reversal rows. No notes column | Phase 9 |
| `payment_notes`     | **Built (Phase 9).** Admin-only, append-only internal notes per payment (author, note 1..4000)                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | Phase 9 |
| `activity_logs`     | actor, entity type/id, action, details, timestamp. No update/delete for anyone. Phase 10: an insert trigger writes notifications                                                                                                                                                                                                                                                                                                                                                                                                                                            | Phase 1 |

**Notifications (Phase 10, implemented on branch, pending owner review).** `notifications`:
recipient (profile), `kind` (`notification_kind`: 5 admin, 2 applicant, 4 editor kinds; KB10),
`entity_type` (`client_inquiry`/`editor_application`/`project`/`payment`) + `entity_id`, `title`,
`body` (no client data), `created_at`, `read_at`. Written only by `private.notify_from_activity()`
(after insert on `activity_logs`); admin kinds fan out to every non-revoked admin.
`private.notification_outbox`: one `queued` email row per notification (not sent until production
SMTP). Functions: `mark_notification_read(uuid)`, `mark_all_notifications_read()`,
`admin_dashboard_metrics()` (jsonb, KB §14, computed live).

Possible later additions, pending decisions: compensation adjustments (F), project communication
log (KB §17.6).

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

## Planned changes from the 2026-11-15 decisions (KB7, F, KB9; not built)

Nothing below exists yet. Each item needs a design, owner approval, a **new** migration (never an
edit to a committed one), pgTAP tests as admin, editor A, editor B, applicant and anon, and
`npm run db:types`. Amounts, charges and day counts are never defaulted.

**Assets (KB7).** Today: `project_assets` (label, https url, provider `google_drive | dropbox |
other`, kind, notes, early_access); `asset_access_grants` records shares made by Lenscape
(`shared_by` = admin); editors can only read assets.

- `project_assets`: add `description`, `access_instructions`, `access_status`
  (`awaiting_access | verified | inaccessible`), `verified_by`, `verified_at`. Decide whether
  `other` stays as a provider value (decision names only Drive and Dropbox).
- New `asset_access_reports` (append-only): asset, editor, note, created_at, resolved_by,
  resolved_at. Insert only through a `public.editor_report_asset_inaccessible` function (assigned
  editor of that project only), resolution through an `admin_*` function; both audited.
- `asset_access_grants`: record that the client shared (`shared_by_client` / source) and add a
  `removal_requested_at` step for the revoke checklist (KB7a).
- New notification event (extends KB10, needs owner OK): "asset reported inaccessible" to admins.

**Revision policy (F).** Today: `projects.revision_allowance smallint default 3` (0..20),
editable by `admin_update_project` in any status except cancelled/archived, audited only as a
field name; `revision_requests.beyond_allowance` flags client rounds past it; no charges; not part
of `brief_confirmations`.

- New `revision_policy_agreements` (append-only, versioned per project): policy type, included
  rounds, charge per additional round + currency (nullable until known), reason for change,
  agreed_by, agreed_at. Client charge columns are client pricing, so the table is **admin-only**;
  editors see only what they need (included-rounds count) through a function or a separate
  editor-safe column.
- Lock: once any assignment is `in_progress`, a policy change requires a new agreement version
  with a reason (trigger), never an in-place update. Keep 3 as the pre-filled number of included rounds on the new-project form (owner, 2026-11-15); the admin may change it, and the saved value is what the agreement records.
- `revision_requests`: add `chargeable boolean` (client revisions past included rounds, or all
  client revisions when none are included) linked to the agreement version in force.
- Scope changes: new admin-only `scope_change_quotes` (request, description, quoted amount +
  currency, status) rather than a revision round.
- Editor pay for chargeable work: `compensation_adjustments` (F2, open).

**Payments (KB9).** Today: one open `payments` row per assignment (`payments_open_key`), created
at assignment confirmation as `not_due`, moved to `pending_approval` on approval; statuses per
decision I; no client billing records beyond `project_internal.client_price`.

- New admin-only `client_payment_milestones`: project, label (deposit/balance), share or amount,
  currency, due date, received date, transfer reference, `verification_status`
  (`expected | received_unverified | verified`), verified_by/at. Never editor-visible.
- Editor `payments`: allow two milestone rows per assignment (replace the single-open-row index
  with one per milestone), each with its own due date, transfer reference and verification status.
  Milestone 1 becomes payable when the client deposit is verified and the assignment is confirmed;
  milestone 2 when the project is approved and the client balance is verified.
- Gate: decide whether `private.assignment_gate` also requires a verified client deposit before
  `in_progress` (decision says "50% upfront before production begins"; today the gate does not
  check client money).
- Editor visibility: editors may need to see that a milestone is waiting on client payment
  without seeing client amounts (KB9a).
- Payout details (E): `editor_payout_details` + verification, needed before the first editor
  milestone is marked paid.

### Additions from the second 2026-11-15 decisions (F2, KB9a, KB9b, KB7a, E go-ahead)

These refine the plan above; still nothing is built.

- **Project terms agreement** (admin-only, append-only, versioned): one record per agreed version
  holding client milestones (default 50/50), revision policy, cancellation/kill-fee schedule
  (stages and amounts or shares, entered per project), and the day counts with their defaults:
  deposit 14 days after invoice, balance 7 days after completion/approval, editor payment within
  7 days of payable, late-balance protection 14 days after the balance is due. A trigger refuses
  in-place edits; once work begins a change needs a new version with a reason.
- **`compensation_adjustments`** (F2): kind (`extra_round | scope_change | cancellation`), amount,
  currency, linked revision request or scope quote, status (`offered | accepted | declined |
withdrawn`), offered/answered by and at. Created by `admin_*`, answered by
  `editor_respond_adjustment`; work on the linked request is blocked until `accepted`. Accepted
  adjustments create their own editor payment rows. The original agreed amount is never edited.
- **Editor payment rows**: one per milestone and per accepted adjustment; add `milestone`,
  `payable_at`, `payable_reason` (`client_deposit_verified | client_balance_verified |
late_balance_protection | adjustment_accepted | cancellation_settlement`), and a client-safe
  `waiting_on_client boolean` that editors may see. Replace `payments_open_key`.
- **Partial dispute holds** (KB9a-4): today a hold covers a whole payment row. Support holding only
  the disputed portion, e.g. by splitting the row into disputed and undisputed parts with an
  audited split, so undisputed money is not frozen.
- **Cancellation settlement** (KB9a-3): compute what the editor earned under the agreed schedule
  at the stage reached; create the settlement row, or an audited reversal for any overpayment;
  record the client refund on the client milestones (admin-only).
- **Deposit gate** (KB9b-4): `private.assignment_gate` also requires a verified client deposit
  milestone; `in_progress` is refused without it.
- **Timed rules** (KB9a-1, KB9a-2): auto-hold after an unpaid deposit and late-balance protection
  need a scheduled job. The project uses no scheduler today. Options: `pg_cron` (hosted) calling a
  `private` function, or a check that runs when an admin opens the dashboard. Design call for
  Phase 12; both must be audited.
- **Assets** (KB7a): `access_type` (`editor_account | anyone_with_link`) on `asset_access_grants`
  (or the asset), with the warning shown to admins; revocation checklist states
  `removal_requested_at` and `removal_confirmed_at` (+ by); new notification kind
  `asset_inaccessible` to admins.
- **Payout details** (E): design `editor_payout_details` (masked account number, verification
  state, audited reads of the full number, admin phone-verification step) and the mark-paid check
  for a verified account. **No real bank data may be stored until counsel confirms PDPA
  handling**; build behind a disabled flag or with local test data only.

**Conflicts with what Phases 0-11 built** (to resolve in Phase 12 design):

1. Project `on_hold` is refused from `assigned`/`in_progress` (Phase 4 rule), but KB9a-2 puts a
   project on hold when the deposit does not clear, which can happen after an editor is assigned.
2. The start gate does not check client money; KB9b-4 requires a verified deposit.
3. One open editor payment per assignment (`payments_open_key`), created whole at confirmation;
   the decisions need milestones, adjustments and settlements as separate rows.
4. Ending an assignment puts unpaid payments on hold automatically (Phase 9, flagged under F);
   F2/KB9a-3 say cancellation must settle completed work and kill fees instead of freezing pay.
5. Holds are whole-row; KB9a-4 needs partial holds.
6. `revision_allowance` is editable until cancel/archive and is not an agreement; F requires a
   locked, versioned agreement (default 3 kept on the form).
7. `editor_list_payments` returns `on_hold_reason` text to editors; with client-payment waits,
   reasons must never contain client financial details (use the `waiting_on_client` flag).
8. The revoke checklist treats shares as something Lenscape revokes; KB7a needs request/confirm
   states for client-owned folders.
9. No scheduler exists for the 14-day rules.
