# Workflows and Lifecycles

Derived from KB §5, §6, §10 and the owner clarification of 2026-11-11. Statuses must be Postgres
enums, not free-form strings. Anything marked **PROPOSED** needs owner approval before migration.

## 1. Client inquiry workflow _(2026-11-11)_

1. Client/agency submits the public inquiry form (no account).
2. Inquiry is recorded in `client_inquiries` (never in `projects`).
3. Admin views and manages it in the admin dashboard.
4. Lenscape reviews and contacts the potential client (outside the app or by email; KB §17.6).
5. Scope, pricing and deadlines are discussed.
6. If confirmed, an admin **manually** converts it into a project. The project's internal record
   links back to the inquiry; the inquiry is marked converted.

**Inquiry statuses (decision N, 2026-11-11; implemented in Phase 3):**

| Status          | Meaning                                             |
| --------------- | --------------------------------------------------- |
| `new`           | Submitted, not yet looked at                        |
| `reviewing`     | Admin is assessing it                               |
| `contacted`     | Lenscape has reached out to the client              |
| `in_discussion` | Scope/pricing/deadline being negotiated with client |
| `converted`     | Admin created a project from it (terminal)          |
| `declined`      | Lenscape will not take the work (terminal)          |
| `closed`        | No response / client withdrew (terminal)            |
| `spam`          | Junk submission; excluded from metrics (terminal)   |

`converted` is set only by `admin_convert_inquiry` (implemented in Phase 4); admins can reopen declined/closed/spam inquiries.

**Conversion (Phase 4):** the "Convert to project" form on the inquiry page calls `admin_convert_inquiry` for inquiries in `new`/`reviewing`/`contacted`/`in_discussion`. One transaction: match the client by `lower(btrim(email))` among unmerged clients (or create one from the inquiry, or use a chosen `client_id`; an archived match fails `ES409`), create a `draft` project prefilled from the inquiry (brief type required), `project_internal` with `source_inquiry_id`, brief version 1, then set the inquiry to `converted` with `converted_project_id`. Any error rolls everything back. Client price is never copied from the budget label.

## 2. Editor registration and verification _(2026-11-11; question D resolved)_

1. Register with email + password (Supabase Auth). Email verification is required (decision R, 2026-11-11).
2. A database trigger creates the user's profile with **no access**. It never reads a role from
   sign-up metadata (that metadata is user-controlled).
3. Applicant fills in the application (draft), then submits it.
4. Admin reviews; may request more information or a practical test.
5. Admin approves and activates (sets level and specialisations), or rejects.
6. An active editor can later be suspended (temporary) or revoked (permanent) by an admin.

**DECIDED (L, 2026-11-11) and implemented in Phase 2: two separate status fields.** The application's review progress
and the person's editor access are different things: an approved editor can later be suspended
without their application becoming "un-approved".

Application status (`editor_applications.status`):

| Status           | Meaning                          | Set by             |
| ---------------- | -------------------------------- | ------------------ |
| `draft`          | Being filled in                  | applicant          |
| `submitted`      | Pending verification             | applicant (submit) |
| `under_review`   | Admin has started review         | admin              |
| `info_requested` | Admin asked for more information | admin              |
| `test_requested` | Admin asked for a practical test | admin              |
| `approved`       | Accepted (terminal)              | admin              |
| `rejected`       | Declined (terminal)              | admin              |
| `withdrawn`      | Applicant withdrew (terminal)    | applicant          |

From `info_requested`/`test_requested` the applicant's response returns it to `under_review`.

Editor access status (`editor_profiles.access_status`):

| Status      | Editor dashboard and work access | Set by                           |
| ----------- | -------------------------------- | -------------------------------- |
| `none`      | No (all applicants start here)   | system                           |
| `active`    | Yes                              | admin approval/reactivation only |
| `suspended` | No; reversible                   | admin                            |
| `revoked`   | No; permanent                    | admin                            |

How the owner's six states map onto this:

| Owner state              | Application status                                   | Access status |
| ------------------------ | ---------------------------------------------------- | ------------- |
| Registered applicant     | none yet, or `draft`                                 | `none`        |
| Application pending      | `submitted`                                          | `none`        |
| Application under review | `under_review` / `info_requested` / `test_requested` | `none`        |
| Approved editor          | `approved`                                           | `active`      |
| Rejected applicant       | `rejected`                                           | `none`        |
| Suspended editor         | `approved`                                           | `suspended`   |

Approval sets both fields in one admin-only database function, so they cannot drift apart.
Re-application after rejection (decision M): only an admin can reopen a rejected application; the applicant cannot re-apply on their own, and each attempt is a separate record.

## 3. Project workflow (KB §5)

1. Admin creates project (from scratch, or by converting an inquiry), selects brief type.
2. Adds deliverables, footage, instructions, references.
3. Sets proposed compensation and deadline.
4. Invites an editor, or makes the project available only to eligible active editors.
5. Editor reviews (what they can see before assignment: OPEN_QUESTIONS B); may ask questions or
   counteroffer.
6. Complex reference/creative jobs: editor submits an interpretation.
7. Editor confirms brief, deliverables, deadline, agreed compensation.
8. Admin confirms the assignment (selection between several editors: OPEN_QUESTIONS C).
9. Editing begins → submission → admin review against brief and references.
10. Approve, or request revision → completed → payment recorded.

**Phase 4 statuses (admin-driven):** `draft` to `open` (needs a ready brief; sets `first_opened_at` once), `open` to `draft`, `draft`/`open` to `cancelled`, `draft`/`open` to `on_hold` and back only to the status held (`status_before_hold`). Cancelled and archived projects refuse edits (`ES409`). `assigned` is set by Phase 6 confirmation and `in_progress` only by the Phase 7 start functions; `in_review`, `revision_requested`, `approved` and `completed` are set only by the Phase 8 functions. `on_hold` from `assigned`/`in_progress`/`in_review`/`revision_requested` stays refused; cancellation is allowed from all four.

**Phase 8 (submissions and review, on branch):** submit (`in_progress`/`revision_requested` → `in_review`; needs the Phase 7 gate) → review: `approved` (project → `approved`, the editor's `not_due` payment → `pending_approval`), `revision_requested` (client revision or editor correction), `scope_change_required` (scope change) or `rejected_needs_discussion` (request opens `disputed` until the admin classifies it); all non-approved outcomes → `revision_requested`. Admin then completes (`approved` → `completed`). Assignment stays `in_progress`. Revision: `requested` → `acknowledged` → `in_progress` → `resubmitted` → `approved`; `disputed` → `requested`. Only client revisions take a round (`beyond_allowance` past `revision_allowance`); no extra pay or late penalty is computed (F, KB5). **Superseded by decision F (2026-11-15):** the single `revision_allowance` integer (default 3, editable until cancel/archive) becomes a per-project policy agreement; see §3a. Reassignment is allowed from `in_review`/`revision_requested` (project → `open`).

**Brief versioning (Phase 4):** before first opening, version 1 is edited in place. After it, any content change (brief text, deliverables, references) creates version n+1 with a snapshot and a required change summary; versions are never overwritten. A new version carries `requires_reacknowledgement` (set by the admin; forced `true` when deliverables change). Deadline and proposed-pay changes do not bump the version in Phase 4.

**Phase 6 assignment lifecycle (as built, pending owner review):** the admin invites active
editors to an open project (`admin_grant_project_access`) and makes a pay offer
(`admin_make_offer`, amount required, one currency per assignment). From `offered` the editor
accepts (agreed amount = offer), declines or counters (`counteroffer_pending`); the admin answers a
counter with accept, a new amount (back to `offered`) or decline. The admin may withdraw from
`offered`/`counteroffer_pending`/`accepted`. `admin_confirm_assignment` needs `accepted`, an open
project and an active editor: it sets `confirmed`, the project `assigned`, every other live
assignment `not_selected`, and revokes every other editor's access. `admin_reassign` sets the
confirmed row `reassigned`, the project back to `open`, and revokes that editor's access.
Terminal states: `declined`, `withdrawn`, `not_selected`, `reassigned`; a new offer afterwards
creates a new row. Offers and responses are refused while the project is `on_hold`. Phase 7 adds
`confirmed → in_progress` (gated start) and `in_progress → reassigned | withdrawn`; reassign,
withdraw/revoke ("use reassign") and the revoke checklist treat `in_progress` like `confirmed`.

### Brief confirmation (KB §5.1)

Store editor, project, timestamp, confirmed brief version, deadline, deliverables, compensation,
status. A material brief change increments the version and may require re-acknowledgement.

**Phase 7 order and gate (as built, pending owner review; spec call 1 flagged).** Decision B shows
the full brief only after admin confirmation, so the KB's steps run 8 → 6 → 7 → 9: the admin
confirms the assignment (Phase 6, selection and pay approval); then, where
`requires_interpretation`, the editor submits an interpretation and the admin accepts it or asks
for changes (new submission per round); then the editor confirms the brief, sending the version,
deadline and pay they saw (copied into an immutable `brief_confirmations` row; a mismatch is
refused); then the editor (or an admin on their behalf) starts work: assignment `confirmed →
in_progress`, project `assigned → in_progress`. The KB's step-8 intent ("nothing starts until the
admin approved") is kept by the gate: start needs admin-approved pay, an accepted interpretation
where required, and a confirmation of the current version without drift. Database triggers enforce
it for every path.

Re-acknowledgement and drift: a new brief version with `requires_reacknowledgement = false` carries
the latest confirmation forward (recorded as a `carried_forward` row) when it was for the previous
version; with `true` the editor must confirm again, and an accepted interpretation from before that
version is no longer valid. A changed (or cleared) deadline or agreed pay after confirmation also
requires re-confirmation (spec call 6, flagged). After start, a material change does not move the
assignment back; the gate turns not ready and Phase 8 submissions must require `ready`.

## 3a. Target workflows from the 2026-11-15 decisions (KB7, F, KB9; not built)

These describe the agreed target. The built behaviour above differs where noted; the list of
changes is in `docs/DATABASE_SCHEMA.md` ("Planned changes from the 2026-11-15 decisions").

**Assets (KB7).**

1. The admin records each client-provided Google Drive or Dropbox link: name, description,
   provider, access instructions. Status starts `awaiting_access`.
2. When an editor is confirmed, the admin asks the client to share the folder with that editor's
   Google/Dropbox account and records the share (`asset_access_grants`: shared by the client,
   recorded by the admin).
3. The editor opens the link and marks it accessible, or reports it inaccessible with a short
   note. A report notifies the admin and sets the asset to `inaccessible` until resolved.
4. The admin follows up with the client and marks it `verified` once the editor confirms access.
5. At unassignment or close, the revoke checklist lists every client share; Lenscape cannot revoke
   them itself (KB7a: removal request to the client).

**Revision policy (F).**

1. Before the project opens to editors, the admin sets the policy (the form pre-fills 3 included rounds): included rounds (0..n) or
   chargeable from round 1 (0 included rounds; F3 confirmed these are the same), plus the client charge per additional round when known.
2. The policy is recorded as a versioned agreement on the project. Once work begins (assignment
   `in_progress`), changing it requires a new recorded agreement version with a reason; the old
   version stays.
3. Review classifies each request as editor correction, client revision or scope change. Client
   revisions count against included rounds; past them, each is flagged chargeable at the agreed
   charge. Scope changes create a separate quote record, never a revision round.

**Payments (KB9).**

1. Client: deposit milestone (50% proposed) due before production; balance milestone (50%) at
   completion. The admin records each transfer and verifies receipt.
2. Editor: total agreed before work (as today). Milestone 1 (50%) becomes payable once the client
   deposit is verified and the editor has confirmed the assignment; milestone 2 (50%) once the
   project is approved and the client balance is verified.
3. Every milestone keeps amount, currency, due date, transfer reference and verification status.
4. Open risks: KB9a (late or unpaid client money), F2 (kill fees, pay for extra rounds).

## 4. Status sets as written in the knowledge base

**Project (§10.1):** Draft · Open/Available · Invited · Negotiation · Awaiting editor confirmation ·
Assigned · In progress · Submitted for review · Revision requested · Approved · Completed ·
Cancelled/On hold.

**Assignment (§10.2):** Offered · Counteroffer pending · Accepted · Confirmed by admin · In progress ·
Declined · Withdrawn · Reassigned.

**Revision (§10.3):** Requested · Acknowledged · In progress · Resubmitted · Approved ·
Disputed/scope clarification.

**Submission review outcome (§6.2):** Approved · Revision requested · Rejected/needs discussion ·
Scope change required.

**Payment:** §8.2 and §10.4 differ; see OPEN_QUESTIONS I for the comparison and recommendation.

## 5. Coarse project status, negotiation on the assignment (decision J, adopted 2026-11-13)

Project: `draft` → `open` → `assigned` → `in_progress` → `in_review` ⇄ `revision_requested` →
`approved` → `completed`, plus `on_hold` and `cancelled`. The KB's Invited / Negotiation /
Awaiting editor confirmation become **assignment** states, shown on the project screen as labels
derived from its assignments. Reasoning is in OPEN_QUESTIONS J.

## 6. Reassignment / cancellation

A reassignment closes the current assignment (`reassigned`/`withdrawn`) and creates a new one;
history is never overwritten. As built (Phase 6, pending owner review): cancelling a project is
allowed from `draft`, `open`, `assigned` and (Phase 7) `in_progress`; it closes every live assignment as `withdrawn` (with
an admin withdraw history row) and revokes every live access row. `open → draft` is refused once
any access row or assignment exists. Folder shares are not revoked automatically: they appear on
the revoke checklist. Pay consequences: OPEN_QUESTIONS F2 (kill fees) and KB9a (client deposit refunds and editor milestones). Suspending or revoking an
editor with live assignments needs an admin decision per assignment (reassign or keep); the app
should list them rather than act silently.
