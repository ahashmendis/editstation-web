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

**Phase 4 statuses (admin-driven):** `draft` to `open` (needs a ready brief; sets `first_opened_at` once), `open` to `draft`, `draft`/`open` to `cancelled`, `draft`/`open` to `on_hold` and back only to the status held (`status_before_hold`). Cancelled and archived projects refuse edits (`ES409`). `assigned`, `in_progress`, `in_review`, `revision_requested`, `approved` and `completed` exist in the enum but are pending (set by Phases 6-8).

**Brief versioning (Phase 4):** before first opening, version 1 is edited in place. After it, any content change (brief text, deliverables, references) creates version n+1 with a snapshot and a required change summary; versions are never overwritten. A new version carries `requires_reacknowledgement` (set by the admin; forced `true` when deliverables change). Deadline and proposed-pay changes do not bump the version in Phase 4.

### Brief confirmation (KB §5.1)

Store editor, project, timestamp, confirmed brief version, deadline, deliverables, compensation,
status. A material brief change increments the version and may require re-acknowledgement.

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
history is never overwritten. Pay consequences: OPEN_QUESTIONS F. Suspending or revoking an
editor with live assignments needs an admin decision per assignment (reassign or keep); the app
should list them rather than act silently.
