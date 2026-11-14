# Phase 8: submissions, review and revision classification (design)

Status: implemented on branch `phase8-submissions` (uncommitted), pending owner review.
Builds on Phase 4 (projects), 6 (assignments), 7 (`private.assignment_gate`) and 9 (payments).
Sources: KB §6, §10.1, §10.3; BUSINESS_RULES "Revisions and scope", "Submissions"; WORKFLOWS.

## 1. Intent

The confirmed editor submits work (a link, never media) as numbered versions. The admin reviews
each submission against the brief with one of the KB §6.2 outcomes and feedback, and classifies
every requested change as a client revision, an editor correction or a scope change. Only client
revisions consume the project's included rounds (`projects.revision_allowance`, default 3).
History is append-only: nothing is overwritten.

Non-goals (open questions, not decided here): pay for extra rounds, scope changes or kill fees
(F); turnaround and late rules (KB5). Phase 8 only **stores facts**: round numbers, a
`beyond_allowance` flag, scope-change records and an `is_late` flag. No amounts, fees or penalties.

## 2. Schema (migration `..._phase8_schema.sql`)

Enums: `submission_outcome` (`approved`, `revision_requested`, `rejected_needs_discussion`,
`scope_change_required`); `revision_type` (`client_revision`, `editor_correction`, `scope_change`);
`revision_status` (`requested`, `acknowledged`, `in_progress`, `resubmitted`, `approved`,
`disputed`).

`submissions` (append-only; one row per version): `assignment_id`, `project_id`, `editor_id`
(must match the assignment), `version` (per project, 1..n, unique), `link` (https, ≤2048),
`notes` (≤4000), `export_details` (≤2000), `revision_request_id` (the change it answers),
`confirmed_deadline` (copied from the editor's latest brief confirmation), `is_late`
(`submitted_at` date in Asia/Colombo > `confirmed_deadline`), `submitted_by/at`, `outcome`,
`feedback` (≤4000, for the editor; required for every outcome except `approved`),
`reviewed_by/at`. One unreviewed submission per assignment. Content immutable; one review update.

`revision_requests` (status/classification mutable only through functions): `project_id`,
`assignment_id`, `submission_id` (the reviewed submission), `type`, `counts_against_allowance`
(generated: `type = 'client_revision'`), `round_number` (client revisions only; 1..n per project
by creation order), `beyond_allowance` (round number > the project's allowance at
classification), `reason` (≤4000, required, written for the editor), `status`,
`acknowledged_at`, `resubmitted_at`, `resolved_at`, `created_by`, `classified_by/at`. One open
(`requested`/`acknowledged`/`in_progress`/`disputed`) request per assignment.

Neither table holds client data or client pricing.

## 3. RLS

Select-only grants, one policy each: admin (aal2), or the owning active editor while
`private.editor_project_stage(project) <> 'none'`. No write grants. Guard triggers refuse deletes,
content changes and invalid status moves for every caller including the table owner.

## 4. Functions (all `security definer`, empty `search_path`, executable by anon+authenticated)

| Function                                                                               | Rules                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| -------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `editor_submit_work(assignment, link, notes, export_details) → uuid`                   | Own `in_progress` assignment; project `in_progress` or `revision_requested`, not archived; `gate_refusal(.., true)` must be null (Phase 7: a material brief change forces re-confirmation first); no pending submission; no `disputed` request. Links the open request (→ `resubmitted`). Project → `in_review`.                                                                                                                                                                                                                                                                 |
| `editor_acknowledge_revision(revision, start default false)`                           | Own request. `requested → acknowledged`; with `start`, `requested/acknowledged → in_progress`. `disputed` refused until classified.                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `admin_review_submission(submission, outcome, feedback, revision_type, reason) → uuid` | Pending submission on an `in_review` project with the assignment still `in_progress`. `approved`: linked request → `approved`, project → `approved`, the assignment's `not_due` payments → `pending_approval` (Phase 9 §9 note). Otherwise one revision request is created: `revision_requested` needs type `client_revision`/`editor_correction`; `scope_change_required` forces `scope_change`; `rejected_needs_discussion` takes any type as a provisional classification and starts `disputed`. Project → `revision_requested`. Returns the request id (null when approved). |
| `admin_approve_project(project, feedback default null)`                                | Shortcut: reviews the project's pending submission as `approved`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `admin_classify_revision(revision, type, reason)`                                      | Open request on an `in_progress` assignment only. Changes type/reason, records `classified_by/at`, `disputed → requested`, renumbers the project's client rounds and `beyond_allowance`.                                                                                                                                                                                                                                                                                                                                                                                         |
| `admin_complete_project(project)`                                                      | `approved → completed`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |

Phase 4/6/7 replacements: `project_transition_allowed` adds `in_review`/`revision_requested →
cancelled`; `admin_reassign` also accepts `in_review`/`revision_requested` projects (project →
`open`; history stays with the old assignment).

## 5. Transitions

Project: `in_progress → in_review` (submit) `⇄ revision_requested` (review / resubmit) `→
approved` (review approved) `→ completed` (complete). A guard trigger on `projects` refuses these
statuses unless the matching facts exist (pending submission for `in_review`; open request for
`revision_requested`; approved latest submission for `approved`; `approved` before `completed`).
Assignment stays `in_progress` throughout (KB has no assignment "completed"; call 3).

Revision: `requested → acknowledged → in_progress → resubmitted → approved`; `disputed →
requested` (classification). A resubmission that gets another non-approved outcome stays
`resubmitted` and the new request carries the next round.

## 6. Audit (ids and enum names only)

`submission.submitted` (submission/assignment/project ids, version, `is_late`),
`submission.reviewed` (+ outcome), `revision_request.created|acknowledged|in_progress|
classified|resubmitted|approved` (ids, type, status, round). Never links, notes, feedback,
reasons or dates. Project and payment status changes use the existing audit triggers.

## 7. Calls for the owner

1. Versions are numbered per project (they continue across a reassignment).
2. Approve is a review outcome; `admin_approve_project` is a shortcut over the same path.
3. The assignment stays `in_progress` after completion (no new assignment status).
4. Payment moves `not_due → pending_approval` on **work approval** (Phase 9 spec §9), not on
   completion. Amounts are never changed (F).
5. `rejected_needs_discussion` needs a provisional type and opens the request as `disputed`; the
   editor cannot resubmit until the admin classifies it.
6. Late = submission date (Asia/Colombo) after the confirmed deadline date. Display only (KB5).
7. Rounds beyond the allowance are allowed and flagged; nothing is charged (F).
8. A `rejected_needs_discussion` request with the provisional type `client_revision` takes a
   round number (and counts toward the allowance) while still `disputed`; classifying it as a
   correction or scope change drops the round and renumbers. Excluding disputed requests until
   classified would need a schema change (generated column, round constraint, UI), so it is left
   for the owner to decide.
9. Reassign and cancel leave the old assignment's open requests as they are (history); they can
   no longer be acknowledged or classified (assignment must be `in_progress`). No new status.
10. Completed and cancelled projects can be archived even though the assignment stays
    `in_progress` (call 3); other projects with a confirmed/in-progress assignment still cannot.

## 8. Tests (pgTAP 080–082)

080 schema, constraints, guards and the RLS matrix (admin aal2/aal1, editor A, editor B, pending
applicant, suspended, anon); 081 workflow (submit refusals and gate, versions, late flag, review
outcomes, rounds x/3 and the beyond flag, corrections and scope changes not counted,
reclassification, dispute, payment move, complete, cancel and reassign from review); 082 function
security catalogue, role refusals and audit hygiene. 044 updated for the two new cancel pairs.

## 9. Screens

Editor `/editor/projects/[id]`: "Submit work" form (link, notes, export details) while
submittable; submission history with outcome and feedback; revision requests with type, round,
reason, status and Acknowledge / Start buttons. Admin `/admin/projects/[id]`: review panel with
pending submission, outcome, feedback, type, reason; rounds used x/allowance with a "beyond
included rounds" warning; late badge; classify form for open requests; Complete button; history.
