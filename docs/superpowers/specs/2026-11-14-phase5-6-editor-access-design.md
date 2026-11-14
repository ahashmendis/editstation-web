# Phases 5–6 design: assets, editor access, offers and assignments

Status: **DRAFT written under the owner's standing instruction of 2026-11-14 ("accept all
recommended options, don't ask")**. Built on a branch and not merged until the owner reviews it.
Inputs: KB §5, §8.1, §10.2; `WORKFLOWS.md` §3, §6; `BUSINESS_RULES.md`; `SECURITY_AND_PRIVACY.md`
access matrix; Phase 4 spec §15; decisions B, C, K, KB6 (2026-11-14). KB7 (storage provider) is
still open and does not block the schema.

## 1. Intent

Phases 5 and 6 are where editors first see work. They share one access model, so they share one
design and ship as two plans (5 then 6) on one branch:

- **Phase 5, assets and visibility rules:** admins attach footage/asset links to a project, mark
  which assets and references are safe to show before confirmation (decision B), and log every
  manual per-account share (decision K) with a revoke checklist.
- **Phase 6, access, offers and assignments:** admins invite active editors to an opened project,
  make a pay offer, negotiate (counteroffers), choose one editor (decision C), and confirm the
  assignment. Editors get a dashboard showing opportunities (summary only) and confirmed projects
  (full brief). A per-project admin notes log covers communication for the pilot (decision KB6).

Done when: an invited editor sees only the opportunity summary of projects they were invited to;
a confirmed editor sees the full brief, references and assets of their project; editor B sees
nothing of editor A's; client data stays invisible to every editor; only an admin can confirm an
assignment; pay is an explicit agreed amount before confirmation.

## 2. Goals, non-goals, anti-goals

Goals: tiered editor visibility enforced by RLS; append-only negotiation history; at most one
active (confirmed) assignment per project; every share of an external folder recorded and
revocable; editors write only through functions.

Non-goals (Phase 7+): brief confirmation and the "in progress" gate, interpretations,
submissions, revisions, payments, notifications, in-app chat, uploading files, provider API
integration (sharing is done manually in Drive/Dropbox and recorded here).

Anti-goals: any editor read of `project_internal`, `clients`, `asset_access_grants`,
`project_notes`, other editors' assignments or offers, or the full brief before confirmation;
any status or money column an editor can write directly; a project with two confirmed editors.

## 3. Constraints

All Phase 0–4 rules: RLS default deny, `private` helpers, `public` functions executable by `anon`
and `authenticated` and authorising inside (`private.require_admin()` for admin; a new
`private.require_active_editor()` returning the caller's uid for editor functions: `ES401` signed
out, `ES403` not an active editor), explicit `revoke ... from public` before grants, ES4xx errors,
`numeric(12,2)` + currency, links only (https), activity logs with ids only. Editor access =
`editor_profiles.access_status = 'active'` (`private.is_active_editor()`); a suspended or revoked
editor immediately loses all reads through the same helper.

## 4. Approaches considered

1. **RLS policies on the base tables with stage helpers (chosen).** Editors read `projects`,
   `project_deliverables`, `project_references`, `project_assets`, `brief_versions` directly,
   filtered by `private.editor_project_stage(project_id)` (`none` / `opportunity` / `assigned`).
   Same model as Phases 1–4; the Supabase client works unchanged.
2. Security-definer read functions returning shaped JSON for editors. Hides columns precisely but
   duplicates every query and bypasses RLS testing patterns. Rejected; column exposure is handled
   by keeping confidential data in admin-only tables (already true since Phase 4).

Order: Phase 5 database → Phase 6 database → db-security review → admin and editor screens.

## 5. Schema

### Phase 5

- `asset_provider` enum: `google_drive`, `dropbox`, `other` (KB7 open: stored per asset).
- `project_assets` — `project_id`, `label` (1–200), `url` (https), `provider`, `kind` text
  (footage, music, graphics, brand, script, other; free text 1–40), `notes`, `early_access boolean
default false` (B: visible in the opportunity summary), `sort_order`, timestamps. Writes via
  functions only.
- `project_references.early_access boolean not null default false` added by a new migration.
- `asset_access_grants` (admin-only) — `project_id`, `editor_id` (FK `editor_profiles`),
  `shared_with_email` (normalised `lower(btrim())`, the account the folder was shared with),
  `provider`, `folder_url` (https, optional), `shared_by`, `shared_at`, `revoked_by`,
  `revoked_at`, `revoke_reason`. Partial unique index: one live grant per (project, editor,
  email) where `revoked_at is null`.

### Phase 6

- `project_access_reason` enum: `invited`, `available` (the KB's "invite one editor" vs "publish
  to eligible editors"; both are explicit rows created by the admin, so visibility is always a
  named list).
- `project_access` — `project_id`, `editor_id`, `reason`, `granted_by`, `granted_at`,
  `revoked_by`, `revoked_at`. Partial unique index (project, editor) where `revoked_at is null`.
- `assignment_status` enum: `offered`, `counteroffer_pending`, `accepted`, `confirmed`,
  `declined`, `withdrawn`, `not_selected`, `reassigned` (decision C adds `not_selected`;
  `in_progress` arrives with Phase 7's gate).
- `assignments` — `project_id`, `editor_id`, `status`, `proposed_amount` + `currency` (current
  offer on the table), `agreed_amount` + `agreed_currency` (set only when accepted),
  `confirmed_by`, `confirmed_at`, `closed_at`, timestamps. Partial unique indexes: one **live**
  assignment per (project, editor) where status in (`offered`, `counteroffer_pending`,
  `accepted`, `confirmed`); one **confirmed** assignment per project.
- `negotiation_offers` (append-only; update/delete blocked by trigger) — `assignment_id`,
  `from_role` (`admin`/`editor`), `action` (`offer`, `counter`, `accept`, `decline`, `withdraw`),
  `amount` + `currency` (null for decline/withdraw), `message` (≤2000), `created_by`,
  `created_at`.
- `project_notes` (admin-only, KB6) — `project_id`, `author_id`, `note` (1–4000), `created_at`;
  append-only.

## 6. Editor visibility (decision B)

`private.editor_project_stage(p_project_id) returns text`, security definer, stable:

- `none` unless `private.is_active_editor()`.
- `assigned` if the caller has an assignment on the project with status `confirmed`.
- `opportunity` if the caller has a live `project_access` row and the project is not `cancelled`
  or archived, or a live assignment (`offered`, `counteroffer_pending`, `accepted`).
- otherwise `none`.

Policies (`for select to authenticated`, added alongside the existing admin policies):

| Table                  | Editor sees when                                                                        |
| ---------------------- | --------------------------------------------------------------------------------------- |
| `projects`             | stage in (`opportunity`, `assigned`)                                                    |
| `project_deliverables` | stage in (`opportunity`, `assigned`) (deliverable specs are the summary)                |
| `project_references`   | stage = `assigned`, or stage = `opportunity` and `early_access`                         |
| `project_assets`       | stage = `assigned`, or stage = `opportunity` and `early_access`                         |
| `brief_versions`       | stage = `assigned`                                                                      |
| `assignments`          | own rows (`editor_id = auth.uid()`) and `private.is_active_editor()`                    |
| `negotiation_offers`   | rows of own assignments                                                                 |
| `project_access`       | own rows                                                                                |
| others in this design  | never (`asset_access_grants`, `project_notes`); `project_internal`, `clients` unchanged |

`projects.proposed_amount` is the baseline offer and is visible to invited editors; per-editor
amounts live on each editor's own `assignments` row. Admin UI warns that `title` and `summary`
are editor-visible (no client names).

## 7. Functions

Admin (`require_admin()` first):

- Phase 5: `admin_save_assets(p_project_id, p_items jsonb)` (id-matching sync like
  deliverables; refuses cancelled/archived; after first opening, asset changes are audited but do
  not create brief versions: assets are links to material, not brief text — my call);
  `admin_set_reference_early_access(p_reference_id, p_value)` and
  `admin_set_asset_early_access(p_asset_id, p_value)`; `admin_record_asset_grant(p_project_id,
p_editor_id, p_email, p_provider, p_folder_url)`; `admin_revoke_asset_grant(p_grant_id,
p_reason)`; `admin_pending_revocations() returns table(...)` listing live grants whose editor is
  no longer active, or has no live/confirmed assignment on the project, or whose project is
  `cancelled`/`completed`/archived (the revoke checklist).
- Phase 6: `admin_grant_project_access(p_project_id, p_editor_ids uuid[], p_reason)` (project
  must have `first_opened_at`, status `open`; every editor active; idempotent for live rows);
  `admin_revoke_project_access(p_project_id, p_editor_id)` (also withdraws a live unconfirmed
  assignment); `admin_make_offer(p_project_id, p_editor_id, p_amount, p_currency, p_message) →
uuid` (creates access if missing and the assignment `offered`, or re-offers on
  `counteroffer_pending`); `admin_respond_counter(p_assignment_id, p_action, p_amount,
p_currency, p_message)` with `p_action` in (`accept`, `counter`, `decline`);
  `admin_withdraw_offer(p_assignment_id, p_message)`; `admin_confirm_assignment(p_assignment_id)`
  (status `accepted` with `agreed_amount`; project `open`; sets assignment `confirmed`, project
  `assigned`, every other live assignment on the project `not_selected`, revokes their access);
  `admin_reassign(p_assignment_id, p_message)` (confirmed → `reassigned`, project back to `open`,
  the editor's access revoked; history kept); `admin_add_project_note(p_project_id, p_note)`.
- Phase 4 change: `admin_set_project_status` refuses `open → draft` once any `project_access` row
  or assignment exists (Phase 4 spec §15); `assigned` stays refused there (only confirmation sets
  it). `admin_set_project_status(..., 'cancelled')` becomes allowed from `assigned` too, closing
  live assignments as `withdrawn` (cancellation path; WORKFLOWS §6). Pay consequences remain
  question F.

Editor (`require_active_editor()` first; may act only on own rows):

- `editor_respond_offer(p_assignment_id, p_action, p_amount, p_currency, p_message)` with
  `p_action` in (`accept`, `decline`, `counter`); only from `offered`. Accept sets
  `agreed_amount = proposed_amount`. Counter sets `counteroffer_pending` and records the amount.
- Editors cannot confirm, withdraw others, or change amounts outside a counter.

Every transition appends a `negotiation_offers` row (for money/offer actions) and an
`activity_logs` row (ids, statuses, no amounts or messages). Transition table:

| From                                        | Action (who)              | To                                    |
| ------------------------------------------- | ------------------------- | ------------------------------------- |
| —                                           | offer (admin)             | `offered`                             |
| `offered`                                   | accept (editor)           | `accepted`                            |
| `offered`                                   | decline (editor)          | `declined`                            |
| `offered`                                   | counter (editor)          | `counteroffer_pending`                |
| `counteroffer_pending`                      | accept (admin)            | `accepted`                            |
| `counteroffer_pending`                      | counter (admin, re-offer) | `offered`                             |
| `counteroffer_pending`                      | decline (admin)           | `declined`                            |
| `offered`/`counteroffer_pending`/`accepted` | withdraw (admin)          | `withdrawn`                           |
| `accepted`                                  | confirm (admin)           | `confirmed` (+ others `not_selected`) |
| `confirmed`                                 | reassign (admin)          | `reassigned`                          |

Terminal: `declined`, `withdrawn`, `not_selected`, `reassigned`. A new offer to the same editor
after a terminal state creates a new assignment row (history never overwritten).

## 8. Derived labels

The admin project page shows, per editor: Invited (access, no assignment), Offer sent
(`offered`), Counteroffer (`counteroffer_pending`), Accepted, Confirmed, and closed states, plus
a project-level summary ("2 invited · 1 counteroffer") computed in the app (decision J).

## 9. Screens (after the database is reviewed)

Admin: project page gains Assets (with early-access toggles), reference early-access toggles,
Editors panel (invite active editors, offer, respond to counter, withdraw, confirm, reassign,
revoke access, negotiation history), Folder shares (record/revoke), Notes log; a new
`/admin/access-review` page listing `admin_pending_revocations()`.

Editor: `/editor` dashboard with Opportunities (stage `opportunity`) and My projects (stage
`assigned`); `/editor/projects/[id]` shows the summary (title, brief type, service, deadline,
summary, deliverables, early-access references/assets, own offer and history, accept/decline/
counter forms) or, when assigned, the full current brief version, references and assets.
Copy reminds editors that references don't grant permission to copy third-party material (KB
§5.2).

## 10. Tests

pgTAP per migration with identities admin (aal2), editor A, editor B, pending applicant,
suspended editor, anon: every visibility cell in §6 (opportunity vs assigned vs none, early-access
on/off, cancelled/archived project, suspended editor loses access immediately, editor B sees
nothing of A's); every transition in §7 and every refused one; one confirmed per project under
two offers; append-only offers and notes; editors cannot call admin functions and vice versa;
`open → draft` refused with access; revoke checklist contents for each trigger condition;
function-security catalogue (046) extended to new functions; no client data columns on
editor-readable tables. Vitest for form schemas; Playwright signed-out gates for new routes.

## 11. Calls made (owner may override)

Both access reasons are explicit admin-created rows; deliverables visible at opportunity stage;
asset changes don't bump brief versions; `projects.proposed_amount` visible to invited editors;
cancellation allowed from `assigned` (closes live assignments as `withdrawn`); confirmation
revokes non-selected editors' access; no provider API (manual sharing, recorded); `project_notes`
append-only.
