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

**Phase 12A (2026-11-15, branch `phase12a-terms`, uncommitted, pending owner review):**
`projects.revision_allowance` is now a **cache** of the agreed terms' `included_rounds`. The
`projects_guard_revision_allowance` trigger refuses any change that does not match the project's
agreed terms; only `admin_agree_terms` writes it. `admin_update_project` refuses the
`revision_allowance` key (ES422). `admin_create_project` / `admin_convert_inquiry` still accept it
on create (form pre-fills 3); the `projects_create_initial_terms` trigger then creates draft terms
v1 from it. See "Project terms" below.

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

## Project terms _(Phase 12A, implemented on branch, pending owner review)_

Spec `docs/superpowers/specs/2026-11-15-phase12-commercial-terms-design.md` section 4.1, section 5
(confirm gate), calls 6, 9, 10. Migrations `20261115032846_phase12a_terms_schema.sql`,
`20261115032849_phase12a_terms_functions.sql`. Both tables: RLS on, `select` for admins only, no
write grants; writes only through the functions below.

| Table                  | Purpose / key columns                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Created   |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| `project_terms`        | **admin-only, versioned, append-only**: project, `version` (unique per project, next version only), `status` (`project_terms_status`: `draft`/`agreed`/`superseded`; at most one draft and one agreed per project), `included_rounds` (0..20; 0 = chargeable from round 1), `extra_round_charge` + `charge_currency` (nullable together, never defaulted), `deposit_days` 14, `balance_days` 7, `editor_pay_days` 7, `late_balance_days` 14 (0..365), `editor_milestone_shares smallint[]` (default `{50,50}`; agreed rows must hold 1..10 shares of 1..100 summing to 100), `change_reason` (max 2000), created_by, agreed_by/at, superseded_at. Guard: never deleted (except by cascade when the project itself is deleted); an agreed row may only become superseded; superseded rows are frozen | Phase 12A |
| `project_terms_stages` | **admin-only** cancellation schedule per terms version: `stage` (`terms_stage`: `assigned`/`in_progress`/`in_review`/`revision_requested`, the project status at cancellation; unique per terms), `editor_earned_percent`, `client_charge_percent` (0..100, 2 decimals). **No defaults.** Rows change only while their terms are a draft                                                                                                                                                                                                                                                                                                                                                                                                                                                            | Phase 12A |

Functions (all security definer, empty `search_path`, executable by `anon` and `authenticated`,
authorise in the body; ES401/ES403/ES409/ES422):

- `admin_save_terms_draft(project_id, input jsonb)` returns the draft id: edits the draft, or
  starts version n+1 as a copy of the latest version (stages included). Keys: `included_rounds`,
  `extra_round_charge`, `charge_currency`, the four `*_days`, `editor_milestone_shares`, `stages`
  (replaces the schedule), `change_reason`. Refused on cancelled/archived projects.
- `admin_agree_terms(project_id, version, change_reason default null)`: locks the project row;
  only the current draft can be agreed (a second agree of the same version is ES409, so two racing
  admins cannot both agree). Shares must sum to 100. Once work has begun (an assignment is or was
  `in_progress`, or work was submitted), version 2+ needs a reason (argument or stored on the
  draft) and the day counts cannot change. While an editor is confirmed or working, editor pay
  terms (milestone shares, editor kill-fee shares) cannot change (call 6: that needs the editor's
  acceptance through adjustments, 12D). Supersedes the previous version, writes
  `projects.revision_allowance` and re-runs `private.renumber_client_rounds`.
- `editor_get_terms(project_id)`: for an active editor at the `opportunity` or `assigned` stage
  (otherwise ES422 not found): version, agreed_at, `included_rounds`, `editor_milestone_shares`
  and `editor_kill_fee` (stage + editor percent). Never client charges, client percentages,
  currency or reasons. No row until terms are agreed.
- `admin_confirm_assignment` (replaced): additionally requires agreed terms with a valid editor
  milestone split (ES409).

Audit (`activity_logs`, entity `project`): `project_terms.draft_saved` and
`project_terms.agreed` with project/terms ids, version, superseded id and **field names only**.
Backfill (call 10, local data only): every existing project got terms v1 from its
`revision_allowance`, agreed (no `agreed_by`) where an editor had been confirmed, otherwise draft;
no stages.

## Asset access _(Phase 12B, implemented on branch, pending owner review)_

Spec section 4.7 and section 6; decisions KB7, KB7a. Migrations
`20261115042630_phase12b_notification_kind.sql` (adds `notification_kind.asset_inaccessible`, alone
in its migration), `20261115042633_phase12b_assets_schema.sql`,
`20261115042637_phase12b_assets_functions.sql`. Enums: `asset_access_status` (`awaiting_access`,
`verified`, `inaccessible`), `asset_access_type` (`editor_account`, `anyone_with_link`). The
`asset_provider` value `other` is kept.

| Table / change           | Key columns / rules                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | Editor reads                     |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| `project_assets` (+)     | `description`, `access_instructions` (≤2000 each, saved by `admin_save_assets`), `access_status` default `awaiting_access`, `verified_by/at` (set together with `verified`, check), `editor_confirmed_at` (the confirmed editor says they can open it; a hint, never a verification; no editor id stored; stale when older than the current assignment's `confirmed_at`). A changed link or provider resets verification and editor confirmation, and status to `awaiting_access` unless a report is open (then it stays `inaccessible`) | as before (`assigned`, or early) |
| `asset_access_grants`(+) | `access_type` default `editor_account`; `removal_requested_at/by`, `removal_confirmed_at/by` (check: confirmed needs requested; `by` only with `at`)                                                                                                                                                                                                                                                                                                                                                                                     | never                            |
| `asset_access_reports`   | **append-only**: project (restrict), asset (set null when the asset is removed), editor, note (1..1000), created_at, resolved_by/at. Trigger refuses delete and every change except resolving once and foreign keys going null. RLS: admins all, an active editor only their own; no write grants                                                                                                                                                                                                                                        | own rows (active editors)        |

Functions (security definer, empty `search_path`, executable by `anon` and `authenticated`,
authorise in the body; ES401/ES403/ES409/ES422):

- `editor_report_asset_inaccessible(asset_id, note)` returns the report id: only the editor at the
  `assigned` stage of the asset's project, re-checked after the project row lock (an unknown or foreign asset is ES403); note required;
  one open report per editor and asset (ES409). Sets the asset `inaccessible` (clears verification),
  audits `asset.reported_inaccessible` and notifies every active admin (`asset_inaccessible`,
  entity `project`; the note is not copied into the notification).
- `editor_confirm_asset_access(asset_id)`: same caller rule; records `editor_confirmed_at` (no-op if already set during the current assignment) and
  audits `asset.editor_can_open`. Never changes `access_status`. Refused (ES409) while the editor's
  own report is open.
- `admin_verify_asset(asset_id)`: the only way to `verified`; refused on cancelled/archived
  projects, when already verified, or while a report is open (ES409). Audits `asset.verified`.
- `admin_resolve_asset_report(report_id)`: resolves once (ES409 after); when no report stays open
  on an `inaccessible` asset it returns to `awaiting_access` (the admin still verifies). Audits
  `asset_report.resolved`. Allowed on closed projects.
- `admin_record_asset_grant(..., folder_url, access_type default 'editor_account')` (replaced; the
  old five-argument version was dropped, calls with four or five arguments still work).
- `admin_request_access_removal(grant_id)` / `admin_confirm_access_removal(grant_id)`: the revoke
  checklist for client-owned folders. Confirm needs a prior request; confirming also closes the
  share (`revoked_at/by`). Audits `asset_grant.removal_requested` / `asset_grant.removal_confirmed`.
  Allowed on closed projects. Ending an assignment never sets either.
- `admin_pending_revocations()` (replaced): adds `access_type` and `removal_requested_at`; rules
  unchanged.

Audit rows hold ids only (project, asset, report, grant, editor), never notes, links or emails.

## Client billing, deposit gate and timed rules _(Phase 12C, implemented on branch, pending owner review)_

Spec sections 4.2 and 5, calls 3, 4, 7, 9; decisions KB9, KB9a-2, KB9b. Migrations
`20261115050654_phase12c_notification_kind.sql` (`notification_kind.project_auto_held`, alone),
`20261115050658_phase12c_billing_schema.sql`, `20261115050702_phase12c_billing_functions.sql`,
`20261115050706_phase12c_gate_and_timed_rules.sql`. Enums `client_milestone_kind` (`deposit`,
`balance`, `extra_work`, `refund`), `client_verification_status` (`expected`,
`received_unverified`, `verified`).

- `client_milestones` (admin only, never editor-visible): project, terms (the agreed version
  used), `seq`, `kind`, `share_percent` (deposit/balance), `amount` (>0; refunds <0 with
  `reverses_id`), `currency`, `invoice_issued_at`, `due_date`, `received_at`,
  `transfer_reference`, `verification_status`, `verified_by/at`, `auto_held_at`,
  `due_change_reason`, `correction_reason`, `voided_at/by` (replaced before invoicing). One live
  deposit and one live row per `seq` per project. Guard trigger: see SECURITY_AND_PRIVACY.
- `app_settings` (admin only): `key` (only `business_timezone` so far), `value` jsonb,
  `updated_by/at`. Seeded `Asia/Colombo` (call 4, owner to confirm).

Functions (security definer, empty `search_path`, executable by `anon` and `authenticated`,
authorise in the body; lock the project row first):

- `admin_create_client_milestones(project, shares int[] default {50,50})`: needs agreed terms and
  a client price > 0 (no invented amounts); the first share is the deposit, the rest balance rows;
  amounts computed once, the last row takes the rounding remainder (call 9). `{100}` = 100%
  upfront. Only before work starts; earlier rows are voided (kept) if none was invoiced or paid.
- `admin_issue_client_invoice(milestone)` returns the due date: business-timezone date + agreed
  `deposit_days` / `balance_days` (defaults 14 / 7). Deposit and balance only; once.
- `admin_record_client_payment(milestone, reference, received_on default today)`: reference
  required, no future date; may be re-recorded while unverified. Allowed on cancelled projects.
- `admin_verify_client_payment(milestone)`: received -> verified (final).
- `admin_correct_client_payment(milestone, reason)`: audited correction back to unverified.
- `admin_extend_deposit_due(milestone, due_date, reason)`: later, not past; releases the hold only
  when it is the deposit-unpaid hold (`auto_held_at` set, held from `assigned`) and lets the rule
  act again after the new date. A manual resume also ends the hold (`auto_held_at` cleared).
- `admin_set_business_timezone(tz)`: an IANA name known to Postgres.
- Gate: `private.assignment_gate` (dropped and recreated) adds `client_deposit_verified`;
  `ready` requires it. `get_assignment_gate` recreated with the new column; `gate_refusal` adds
  the deposit message last ("Waiting for the client deposit..." for the editor).
- `private.project_transition_allowed`: `assigned -> on_hold` and, for that hold,
  `on_hold -> cancelled`; `admin_set_project_status` refuses a manual `assigned -> on_hold`.
- `private.apply_timed_rules(p_now)` (idempotent; returns actions): an invoiced deposit still
  unverified after its due date (business calendar day, so from the day after), on a project
  `assigned` with a `confirmed` editor (never `open`) -> project `on_hold` from `assigned`,
  `auto_held_at` and `auto_held_for_due` set (once per due date), audit `project.auto_held` (`reason: deposit_unpaid`),
  notify admins (`project_auto_held`). `admin_run_timed_rules()` runs it as the admin (dashboard
  and `/admin/earnings` call it on load) and audits `timed_rules.run` only when it acted.
  `pg_cron` on hosted Supabase is not scheduled yet (hosted work needs owner approval).

## Editor pay milestones and partial disputes _(Phase 12D part 1, implemented on branch, pending owner review)_

Spec sections 4.2 (note), 4.3, 4.5, 5 and call 9; decisions KB9, KB9a-1, KB9a-4, KB9a-5, KB9b-3.
Migrations `20261115071328_phase12d_notification_kind.sql` (`notification_kind.late_balance_payable`,
alone), `20261115071331_phase12d_editor_pay_schema.sql`, `20261115071334_phase12d_editor_pay_functions.sql`.
Enums `payment_payable_reason` (`client_deposit_verified`, `client_balance_verified`,
`late_balance_protection`, `adjustment_accepted`, `cancellation_settlement`; the last two are used
from 12D part 2) and `payment_hold_label` (`under_review`, `assignment_ended`,
`waiting_for_client_payment`).

- `payments` gains `milestone_seq` (1..10, default 1; existing rows backfilled to 1; reversals copy
  it), `payable_reason` + `payable_at` (set together, fixed once set), `split_from_payment_id`
  (disputed child row), `amount_before_split` (the parent's original amount) and
  `waiting_on_client` (only while `not_due`; cleared by any move out of `not_due`).
- `payments_open_key` is now one unpaid row per `(assignment_id, milestone_seq)` (split children
  excluded); `payments_split_from_key`: one split per milestone row.
- Insert guard: milestone rows (net of reversals) never add up to more than the agreed amount, in
  the agreed currency; a split child matches its unpaid parent (same assignment, milestone and
  currency) and starts `on_hold`. Update guard: milestone and split identity fixed; the amount
  changes once, only inside the split function. Constraint trigger `payments_split_sum`
  (deferrable, checked per statement): parent amount + child = `amount_before_split`.
- Confirmation (`private.create_assignment_payment`, replaced): one `not_due` row per agreed terms
  `editor_milestone_shares` (default 50/50) of the agreed amount; the last row takes the rounding
  remainder (call 9).
- `private.sync_editor_milestones(project, p_now)` (idempotent; locks project, assignments,
  payments): for live assignments, milestone 1 becomes payable when the client deposit is
  verified; milestones 2..n when the project is `approved`/`completed` and the client balance is
  verified. Payable = `pending_approval`, `payable_at = p_now`, `due_date` = business date of
  `p_now` + terms `editor_pay_days` (default 7). It also keeps `waiting_on_client` current. Run by
  the confirmation trigger, triggers on `client_milestones` (verification change, refund insert)
  and on `projects` (status -> `approved`), and by hold release. Phase 8 `review_submission` no
  longer moves payments itself.
- `private.client_deposit_verified` (replaced): a verified deposit counts only while its amount
  plus its refund rows is above 0. `private.client_balance_verified`: the deposit counts and every
  live balance row is verified (net of refunds); none means the deposit suffices (100% upfront).
- `private.apply_timed_rules(p_now)` (replaced) adds late-balance protection (KB9a-1): project
  approved/completed, every unverified balance row invoiced and past due + terms
  `late_balance_days` (default 14, business calendar day), no payment row on hold on the assignment (any hold; conservative, owner to confirm) ->
  the not_due later milestones become payable with `late_balance_protection`; audit
  `payment.late_balance_payable` (ids and the enum reason) and notify admins
  (`late_balance_payable`), once per milestone.
- `admin_split_payment_for_dispute(payment, disputed_amount, reason)` returns the child id: an
  unsplit, unpaid milestone not on hold; amount > 0, below the row, whole cents; reason required.
  Parent keeps the rest and its status; the child is `on_hold` from the parent's status with the
  reason (and the parent's approval/payable facts). Audit `payment.dispute_split` (ids, field
  names). Release returns the child to that status (`admin_release_payment_hold`, which now locks
  project, assignment, payment in order and re-runs the payable rules).
- `admin_reverse_payment` (replaced): locks project, assignment, payment in order; reversal and
  re-opened row keep the milestone; the open check is per milestone.
- `admin_set_payment_status` (replaced): refuses `not_due -> pending_approval` by hand (ES409); a
  milestone becomes payable only through the rules above.
- `editor_list_payments()` (dropped and recreated, new return type): adds `milestone_seq`,
  `hold_label` (enum), `waiting_on_client`, `split_from_payment_id`; drops `on_hold_reason` and `reversal_reason`;
  never returns `payable_reason`, admin ids or client money.
- Unchanged: the Phase 9 hold-on-close trigger (12D part 2 settlement replaces it).

## Extra pay, scope quotes and cancellation settlement _(Phase 12D part 2, implemented on branch, pending owner review)_

Spec sections 4.3 (`cancelled`), 4.4, 4.6, 6 and calls 2, 5, 6, 8; decisions F, F2 (a-d), KB9a-3,
Phase 12 principles. Migrations `20261115093806_phase12d2_payment_cancelled.sql`
(`payment_status.cancelled`, alone), `20261115093810_phase12d2_notification_kinds.sql`
(`adjustment_offered`, `adjustment_answered`, alone), `20261115093814_phase12d2_schema.sql`,
`20261115093818_phase12d2_adjustments.sql`, `20261115093821_phase12d2_settlement.sql`. Enums
`adjustment_kind` (`extra_round`, `scope_change`, `cancellation`), `adjustment_status` (`offered`,
`accepted`, `declined`, `withdrawn`), `scope_quote_status` (`drafted`, `sent`, `accepted`,
`declined`).

- `compensation_adjustments` (admin select only; no write grants): `assignment_id`, `project_id`,
  `editor_id`, `kind`, `amount` (> 0) and `currency` (the assignment's agreed currency),
  `revision_request_id` (extra round) or `scope_quote_id` (scope change) or neither
  (cancellation), `status`, `note` (for the editor), offered/answered/withdrawn by and at. One live
  (offered or accepted) offer per round and per quote; one open cancellation offer per
  assignment. Guard: no delete, identity and amount fixed, one answering move. Editor pay only.
- `scope_change_quotes` (admin-only client money): `revision_request_id` (a `scope_change`
  request), `description`, `amount`, `currency`, `status`, `sent_at`, answered by/at (the client's
  answer, recorded by an admin). One live (not declined) quote per request; amount fixed.
- `cancellation_settlements` (admin-only, append-only, one per project): stage, schedule
  percentages, agreed amount, computed and final editor earned (+ reason when they differ),
  accepted extra pay (earned in full), milestones paid before, settlement amount (milestone
  shortfall), milestone overpayment, cancelled row count, client base (deposit +
  balance milestones), verified received, charge, refund and amount still owed.
- `revision_requests.adjustment_required` (client revisions only; cleared on reclassification).
- `client_milestones` gains `scope_quote_id` / `revision_request_id` (an `extra_work` row's source;
  one live row each) and `settlement_id` (refund rows); fixed once written.
- `payments` gains `adjustment_id` and `settlement_id`; `milestone_seq` is null on those extra
  lines (`payments_line_chk`: an extra-pay row has `payable_reason = adjustment_accepted`, a
  settlement row `cancellation_settlement`). `cancelled` is final like `paid` and is set only by a
  settlement (transaction-local flag); open-row keys exclude cancelled rows; one open row per
  offer and per settlement. Insert guard: milestones (net, cancelled excluded) within the agreed
  amount; an extra-pay row within its accepted offer; a settlement row within the shortfall; a
  settlement may reverse part of a paid row (overpayment), other reversals are whole. Audit
  action `payment.cancelled`.
- A request the editor has begun (acknowledged, in progress) cannot be reclassified as a scope
  change (ES409; raise a new change request). A scope-change offer needs the accepted quote, so
  an accepted offer never outlives a declined quote.
- Gate (`private.revision_gate`, enforced in the replaced `guard_revision_requests`, so every
  acknowledge/start/submit path): a marked client revision needs an accepted extra-round offer; a
  scope change needs an accepted scope offer **and** an accepted quote. Codes `ok`,
  `needs_extra_pay`, `waiting_for_scope_approval` (`editor_revision_gate` for the editor's own
  request).
- Functions: `admin_set_revision_adjustment_required`, `admin_offer_adjustment` (notifies the
  editor, `adjustment_offered`), `admin_withdraw_adjustment` (offered only),
  `editor_respond_adjustment` (accept creates its own `pending_approval` payment, payable now, due
  business date + `editor_pay_days`; notifies admins, `adjustment_answered`),
  `editor_list_adjustments` (own offers; no admin ids, quotes or client money),
  `admin_create_scope_quote`, `admin_send_scope_quote`, `admin_record_scope_quote_answer`
  (acceptance needs an admin due date and creates an invoiced `extra_work` client milestone; call
  5), `admin_charge_extra_round` (a beyond-allowance client revision, terms `extra_round_charge`,
  admin due date, once), `admin_preview_cancellation_settlement`, `admin_settle_cancellation`.
  Replaced: `admin_reverse_payment` (keeps the line), `editor_list_payments` (adds `line_kind`:
  `milestone`, `extra_round`, `scope_change`, `cancellation_extra`, `cancellation_settlement`,
  `cancellation_reconciliation`), `admin_set_project_status` (settle-instead rule),
  `check_payment_row`, `guard_payments`, `audit_payments`, `require_unpaid`.
- Settlement (`admin_settle_cancellation(project, adjusted_editor_earned?, reason?)`, one
  transaction, locks project, assignments, payments, client milestones): stage = project status
  (on hold from assigned counts as assigned); refused cleanly when the agreed terms have no
  schedule row for the stage, when no editor is confirmed, when a client payment is recorded but
  unverified, or when already settled. Editor earned = round(agreed amount x
  `editor_earned_percent`, 2) + accepted extra pay (extra rounds, scope changes) in full, or the
  admin's figure (between the accepted extra pay and agreed + extra pay, reason required). It
  cancels the project (assignment withdrawn, access revoked, open offers withdrawn); extra pay
  rows are untouched (paid stays paid, unpaid stays payable); unpaid milestone rows are cancelled;
  a settlement row pays the milestone shortfall, or settlement reversals of the newest paid
  milestone rows record a milestone overpayment; and it
  records refund rows (newest verified receipt first) for verified deposit + balance money above
  the client charge (round(client base x `client_charge_percent`, 2)). Extra-work client charges
  are not part of the client calculation.
- When the settlement is required: the project has a confirmed or in-progress assignment and the
  agreed terms have a schedule row for its stage; then `admin_set_project_status(..., cancelled)`
  is refused (ES409). Otherwise the plain cancel keeps the Phase 9 hold-on-close behaviour
  (unpaid rows on hold for the admin), e.g. backfilled terms without a schedule.

## Payout details, locked _(Phase 12E, implemented on branch, pending owner review)_

Decision E, spec 4.8 and call 1. **Locked:** `app_settings.payout_details_enabled` (jsonb boolean,
default `false`, changed only by `admin_set_payout_enabled`, audited as `app_settings.changed`).
While it is false every payout write function raises ES409 and guard triggers refuse inserts into
`editor_payout_details` and `editor_payout_detail_versions` (also for the table owner), so no bank
data can exist. It must stay off until counsel confirms PDPA handling.

- **`editor_payout_details`** (one row per editor, pk `editor_id` -> `editor_profiles`, cascade):
  `account_holder`, `bank`, `branch` (1-120 chars), `account_number` (6-34 letters, digits, spaces,
  hyphens; at least 6 letters or digits), `version`, `verification_status` (`payout_verification_status`: `unverified |
verified`), `verified_by/at`, `verified_method` (`phone | in_person | other`),
  `verification_note`, `last_changed_at`. A check keeps the verification columns consistent with
  the status. The guard trigger (owner too) makes any content change exactly the next version and
  `unverified`, and refuses any other version change.
- **`editor_payout_detail_versions`** (append-only): every saved version in full with
  `changed_by/at`; `(editor_id, version)` unique; next version only; no update or delete except the
  actor `on delete set null` and the cascade from deleting the editor.
- **`editor_payout_attestations`** (append-only, call 1): `editor_id`, `note` (no bank data),
  `attested_by`, `attested_at`. Counts only while the flag is off; once it is on it is retired and a
  verified payout account is required.
- **Access:** RLS on, **no grants to anon or authenticated and no policies** on all three tables.
  Functions: `editor_save_payout_details`, `editor_get_payout_details` (own, number masked to the
  last 4), `admin_get_payout_details_masked` (also the attestation and `mark_paid_block`),
  `admin_reveal_payout_details` (refused while locked; reason required, no 6+ digit runs; always writes `payout_details.revealed` with
  admin, editor and reason), `admin_verify_payout_details` (editor, version shown, method, note),
  `admin_set_payout_enabled`, `admin_attest_payout_outside_app`. Helpers in `private`:
  `payout_details_enabled`, `require_payout_enabled`, `mask_account_number`,
  `payout_attestation_current`, `payout_block_reason`, `require_editor_exists`,
  `admin_display_name`, the guard triggers.
- **Audit and notifications:** `payout_details.changed` (editor id, version, changed field names),
  `payout_details.verified`, `payout_details.revealed`, `payout_attestation.recorded`; never bank
  values. Notification kind `payout_details_changed` to admins (entity type `editor_profile`, new
  in the notifications check).
- **Mark-paid gate:** `admin_mark_payment_paid` (replaced in place) keeps every Phase 9 check and
  the payments audit, then holds the flag row and the editor's payout row `for share` (lock order:
  payment, settings, payout row) and refuses with ES409 and a how-to-fix message unless the editor has a current
  attestation (flag off) or verified details (flag on).

## Open opportunities _(B/C amended 2026-11-16, implemented on branch, pending owner review)_

Spec `docs/superpowers/specs/2026-11-16-open-opportunities-design.md`. Migrations
`20261116152005` (notification kinds `interest_registered`, `opportunity_selected`,
`opportunity_not_selected`), `20261116152008` (schema), `20261116152010` (functions).

- **`project_opportunities`** (editor-visible, one per project, `project_id` unique, cascade):
  admin-written `title` (1-120), `service_type_code` (-> `service_types`), `deliverables_summary`
  (1-1000), `deadline`, `format_notes` (1-1000), `shown_pay_amount` + `shown_pay_currency` (both
  or neither; null = pay hidden, so RLS never exposes a hidden amount), `closes_at` (stops new
  interest only), `status` (`opportunity_status`: `open | closed | filled`), `close_reason`
  (`selected | admin | project_closed`), `published_by/at`, `closed_by/at`, `updated_at`. A check
  ties `closed_at` and `close_reason` to the status. **No client column** (pgTAP `112` pins the
  column list). Guard: never deleted (except the project cascade), never moves project.
- **`opportunity_interests`**: `opportunity_id` (cascade), `editor_id` (-> `editor_profiles`,
  cascade), `proposed_amount` + `proposed_currency` (both or neither; a signal only),
  `note` (1-500), `status` (`opportunity_interest_status`: `interested | withdrawn | selected |
not_selected`), `created_at`, `decided_at` (set iff not `interested`). Partial unique index: one
  live (`interested`/`selected`) row per editor per opportunity. Guard: inserts start
  `interested`; only `status`/`decided_at` change, once, from `interested`; never deleted except by
  cascade.
- **Access:** RLS on; no write grants. Authenticated has a **column-level** `select` on
  `project_opportunities` that omits `project_id`, `published_by` and `closed_by` (admins get those
  through `admin_get_opportunity`, one round trip with the interests) and `select` on
  `opportunity_interests`. Admin (MFA) reads
  all; an active editor reads an opportunity that takes interest now (open, before `closes_at`,
  project open and unarchived) or one they have an interest on
  (`private.editor_can_see_opportunity`, executable by authenticated for the policy), and only
  their own interest rows. Functions: `admin_publish_opportunity` (also reopens),
  `admin_update_opportunity`, `admin_close_opportunity`, `editor_list_opportunities` (allow-list
  projection with the caller's latest interest; the project id only once selected),
  `editor_register_interest`, `editor_withdraw_interest`, `admin_list_interests`,
  `admin_get_opportunity`, `admin_select_editor` (calls `admin_make_offer`). Helpers in `private`: `lock_opportunity`,
  `opportunity_accepting`, `clean_opportunity`, `close_opportunity`, the guard triggers and the
  `projects_close_opportunity` trigger (closes an open opportunity when the project leaves the
  open stage for good). Notifications entity type `project_opportunity` added.
- **Locks:** project, then the opportunity, then the chosen interest, then assignments (inside
  `admin_make_offer`), then the other interest rows. The limit of 10 counts only `interested` rows
  on opportunities still taking interest (closed, past the closing date, or a project in draft or
  on hold do not count). Editors never lock projects: registering holds the opportunity row `for share` and
  a per-editor advisory lock (the 10-interest limit); withdrawing locks only the editor's own row.
- **Audit:** `opportunity.published|updated|closed`, `opportunity_interest.registered|withdrawn|
selected|not_selected`; ids, field names, reason and counts only (never amounts, notes or
  summary text).

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
`private.notification_outbox`: one email row per notification: `status` (`queued`/`sent`/`failed`),
`attempts` (0..3, counted at claim), `last_error` (≤200, short machine reason, no PII),
`claimed_at` (15-minute lease; rows of one admin summary share it), `digest` (set on insert by
`private.email_is_digest(kind)`: admin kinds true, editor/applicant kinds false; mapping documented
in migration `20261117143615`). Worker functions (service_role only, ES403 for every other caller,
including admins): `worker_claim_emails(p_limit int default 25)` (individual rows, oldest first,
`for update skip locked`, confirmed recipients only; returns id, email, title, kind,
claimed_at, never the body), `worker_claim_admin_digest(p_now timestamptz)` (one row per active
confirmed admin per Asia/Colombo day, judged by the Colombo date of a sent summary's `claimed_at`:
handle id, email, per-kind `counts`, `total`, claimed_at; one non-blocking transaction advisory
lock), `worker_mark_email(p_id bigint, p_ok boolean, p_error text, p_claimed_at timestamptz)`
(sent, retry, or failed after 3 attempts; ES409 not claimed or `p_claimed_at` differs, ES422
unknown). Caller check `private.require_service_role()`: database role and JWT role claim must
both be `service_role`. Housekeeping before each claim fails exhausted leases and rows queued
over 14 days with no confirmed address or an inactive admin recipient. The migration failed the
pre-launch queue (`pre-launch backlog`, `private.fail_prelaunch_backlog()`). Functions: `mark_notification_read(uuid)`, `mark_all_notifications_read()`,
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

**Assets (KB7, KB7a).** _Built in Phase 12B (see "Asset access"); `other` stays as a provider
value._

**Revision policy (F).** _Phase 12A builds the versioned agreement as `project_terms` (see
"Project terms"); the `revision_requests.chargeable` link, scope quotes and adjustments below are
still planned (12C/12D)._ Before 12A: `projects.revision_allowance smallint default 3` (0..20),
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
- Payout details (E): _built locked in Phase 12E_ (see "Payout details, locked").

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
- **Assets** (KB7a): _built in Phase 12B_ (`access_type` on `asset_access_grants` with the admin
  warning, removal requested/confirmed states, notification kind `asset_inaccessible`).
- **Payout details** (E): _built in Phase 12E behind the disabled flag_ (see "Payout details,
  locked"). **No real bank data may be stored until counsel confirms PDPA handling.**

**Conflicts with what Phases 0-11 built** (to resolve in Phase 12 design):

1. _(Resolved in Phase 12C: `assigned -> on_hold` for the unpaid-deposit rule only.)_ Project `on_hold` is refused from `assigned`/`in_progress` (Phase 4 rule), but KB9a-2 puts a
   project on hold when the deposit does not clear, which can happen after an editor is assigned.
2. _(Resolved in Phase 12C: deposit gate.)_ The start gate does not check client money; KB9b-4 requires a verified deposit.
3. _(Resolved in Phase 12D: milestones in part 1; extra-pay and settlement lines in part 2.)_ One open editor payment per assignment (`payments_open_key`), created whole at confirmation;
   the decisions need milestones, adjustments and settlements as separate rows.
4. _(Resolved in Phase 12D part 2: cancellation settlement where a schedule applies; the hold stays for reassignment and unscheduled cancels.)_ Ending an assignment puts unpaid payments on hold automatically (Phase 9, flagged under F);
   F2/KB9a-3 say cancellation must settle completed work and kill fees instead of freezing pay.
5. _(Resolved in Phase 12D part 1: dispute split rows.)_ Holds are whole-row; KB9a-4 needs partial holds.
6. `revision_allowance` is editable until cancel/archive and is not an agreement; F requires a
   locked, versioned agreement (default 3 kept on the form).
7. _(Resolved in Phase 12D part 1: enum `hold_label`.)_ `editor_list_payments` returns `on_hold_reason` text to editors; with client-payment waits,
   reasons must never contain client financial details (use the `waiting_on_client` flag).
8. ~~The revoke checklist treats shares as something Lenscape revokes~~: resolved in Phase 12B
   (request/confirm states for client-owned folders).
9. _(Resolved: `private.apply_timed_rules`, deposit rule in 12C, late-balance protection in 12D part 1.)_ No scheduler exists for the 14-day rules.
