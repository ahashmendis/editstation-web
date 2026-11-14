# Phase 7 design: interpretation, brief confirmation and the in-progress gate

Status: **DRAFT written under the owner's standing instruction of 2026-11-14 ("accept all
recommended options, don't ask")**. Built on a branch and not merged until the owner reviews it.
Inputs: KB §4.2, §5, §5.1, §8.1, §10.2; `WORKFLOWS.md` §3, §5, §6; `BUSINESS_RULES.md`
(compensation); `SECURITY_AND_PRIVACY.md`; Phase 4 spec §8 and §15; Phases 5–6 spec and plan
(Interfaces); decisions B, C, J (2026-11-13/14). Open questions touched but **not decided**: F
(pay changes after confirmation), KB5 (late delivery). Neither blocks this phase (§13).

## 1. Intent

Phase 7 is the last gate before editing starts. An admin-confirmed editor (assignment `confirmed`,
Phase 6) now sees the full brief (decision B). Before they may start:

- where `projects.requires_interpretation` is true, the editor submits a short **interpretation**
  (what they will reproduce, what they will adapt, questions or limitations; KB §4.2) and an admin
  accepts it or asks for changes;
- the editor **confirms the brief** (KB §5.1): the exact brief version, deadline, deliverables and
  agreed pay are copied into an immutable confirmation row;
- only then can the assignment and the project move to **`in_progress`**.

Later brief versions with `requires_reacknowledgement = true` invalidate the confirmation; versions
with `false` carry it forward, recorded as carried forward (Phase 4 spec §8). A changed deadline
or pay also invalidates it (§12 call 6, flagged).

Roadmap "done when": an assignment or project can reach `in_progress` only when the agreed amount
is admin-approved, the brief is confirmed for the current version, and the interpretation is
accepted where required, **enforced in the database** (functions and triggers, whoever calls).

## 2. Goals, non-goals, anti-goals

Goals: one gate predicate in Postgres used by every path to `in_progress` (and by Phase 8
submissions later); immutable confirmation history tied to brief versions; append-only
interpretation history with admin feedback; drift (deadline, pay, deliverables, version) visible
to admin and editor; editors write only through functions.

Non-goals (Phase 8+): submissions, revisions, review outcomes, payments, notifications, late
flags (KB5), pay adjustments after confirmation (F), in-app Q&A (KB6: email plus admin notes),
uploading interpretation files (text only), `on_hold` from `assigned`/`in_progress`.

Anti-goals: an assignment or project in `in_progress` without the gate holding; a confirmation
row that changes or disappears; a confirmation accepted for a version other than the current
one; an editor confirming a brief they cannot see; an editor reading another editor's
interpretations or confirmations; a status or money column an editor can write directly; client
data in any table this phase adds.

## 3. Constraints

All Phase 0–6 rules: RLS default deny; helpers in `private`; every `public` function executable
by `anon` and `authenticated`, authorising in its body (`private.require_admin()` /
`private.require_active_editor()`); explicit `revoke ... from public` then grants; `ES401/403/409/
422` only; `numeric(12,2)` + `char(3)` currency; audit rows with ids and enum names only; lock
order project → assignment (`private.lock_assignment`); never edit an applied migration.

Phase 4 §15 hands this phase: `brief_confirmations.brief_version_id` `on delete restrict`;
confirmation rows immutable; a confirmation accepted only for the project's current version;
carry-forward on `requires_reacknowledgement = false` recorded as such. Phase 6 hands: assignment
status `confirmed` (admin-approved agreed amount, `confirmed_at`), `in_progress` to be added, one
confirmed assignment per project, editor stage `assigned` only for `confirmed`.

Postgres: a new enum value cannot be used in the transaction that adds it, so
`assignment_status.in_progress` is added in a migration of its own.

## 4. Approaches considered

### 4.1 Order relative to admin confirmation (KB §5 steps 6–8)

The KB orders: editor interpretation (6) → editor confirms brief (7) → admin confirms assignment
(8) → editing begins (9). The caller's preferred option was to make `admin_confirm_assignment`
require a brief confirmation and accepted interpretation.

1. **Admin confirmation first, then interpretation and brief confirmation, then a gated start
   (chosen).** Decision B (owner, 2026-11-14) says the full brief and assets are visible **only
   after admin confirmation**; before it an editor sees only the opportunity summary. An editor
   cannot meaningfully interpret references or confirm a brief they cannot read, and the owner's
   decision log outranks the KB (CLAUDE.md precedence). So Phase 6's confirmation stays the
   "selection and pay approval" step that unlocks the brief; interpretation (6) and brief
   confirmation (7) follow it; the KB's intent for step 8, "nothing starts until the admin has
   approved", is kept by the gate: start is impossible without admin-approved pay and (where
   required) an admin-accepted interpretation. KB §5 steps are effectively 8 → 6 → 7 → 9.
2. Gate `admin_confirm_assignment` on a prior brief confirmation (caller's preference). Rejected:
   it requires accepted editors to read the full brief before confirmation, which contradicts
   decision B and would expose the full brief to every accepted candidate (decision C allows
   several).
3. A new "selected" stage between `accepted` and `confirmed` that shows the full brief. Rejected:
   same exposure problem in a different name, and a second admin approval step for no added
   safety.

Flagged for the owner (§12 call 1). If the owner prefers the KB order literally, decision B must
be revisited first.

### 4.2 Where the gate lives

1. **One `private.assignment_gate(assignment_id)` predicate, called by the start functions and
   by `BEFORE UPDATE` triggers on `assignments` and `projects` (chosen).** Every path to
   `in_progress` (a function today, a future function, a manual SQL update by the table owner)
   passes the same check.
2. Checks only inside the start functions. Rejected: the roadmap requires DB enforcement, and
   Phase 8 needs the same predicate.

### 4.3 Carry-forward

1. **Recorded rows (chosen):** an `AFTER INSERT` trigger on `brief_versions` writes a
   `carried_forward` confirmation for the new version, pointing at the confirmation it carries,
   when the new version has `requires_reacknowledgement = false`. History shows exactly what each
   editor was bound to per version.
2. Computed on read. Rejected: Phase 4 §8 requires carry-forward to be recorded.

## 5. Schema

### Enum changes

- `assignment_status` gains `in_progress` (after `confirmed`).
- New `interpretation_status`: `submitted`, `accepted`, `changes_requested`.
- New `brief_confirmation_kind`: `confirmed` (the editor's own action), `carried_forward`.

### `assignments` (changed)

- New columns `started_at timestamptz`, `started_by uuid` FK `profiles` set null.
- Constraints widened: `in_progress` needs `agreed_amount` and `confirmed_at`, and
  `(status = 'in_progress') <= (started_at is not null)`.
- `assignments_live_key` (one live row per project/editor) includes `in_progress`.
- `assignments_one_confirmed_key` is replaced by `assignments_one_active_key on (project_id)
where status in ('confirmed','in_progress')`: one active editor per project.
- Transitions add `confirmed → in_progress`, `in_progress → reassigned | withdrawn`.

### `editor_interpretations` (append-only history; one row per submission)

`assignment_id` FK restrict, `brief_version_id` FK `brief_versions` restrict (the current version
when submitted), `will_reproduce`, `will_adapt`, `questions_limitations` (each text 1–4000,
nullable; at least one of the first two required), `status interpretation_status` default
`submitted`, `admin_feedback` (1–4000; required when `changes_requested`), `submitted_by`,
`submitted_at`, `reviewed_by`, `reviewed_at`. At most one `submitted` row per assignment (partial
unique index). Content is immutable; the only update is one review (`submitted →
accepted | changes_requested` with review fields), plus clearing actor columns on account deletion.
A new submission after `changes_requested` (or after a material brief change) is a new row.

### `brief_confirmations` (immutable)

KB §5.1 fields: `assignment_id` FK restrict, `project_id` FK restrict, `editor_id` FK
`editor_profiles` restrict, `brief_version_id` FK `brief_versions` **on delete restrict**,
`brief_version int` (copy), `kind brief_confirmation_kind`, `carried_from_id` self FK restrict
(set iff `carried_forward`), `confirmed_deadline date not null`, `confirmed_deliverables jsonb not
null` (copy of the version's `deliverables` snapshot), `confirmed_amount numeric(12,2) > 0` +
`confirmed_currency char(3)` (copies of the agreed pay), `created_by` (editor for `confirmed`, the
admin who saved the brief for `carried_forward`), `confirmed_at timestamptz default now()`.
Insert trigger: `project_id`/`editor_id` match the assignment, the version belongs to that
project. Update and delete refused (only clearing `created_by` on account deletion, the
Phase 6 append-only pattern). Partial unique index: one `carried_forward` row per
(assignment, brief version).

KB "confirmation status" is represented by the stored `kind` plus a **derived** state (current,
superseded, re-confirmation required) from the gate, because a stored mutable status would break
immutability (§12 call 4).

### Relationships

```
assignments 1─* editor_interpretations *─1 brief_versions
assignments 1─* brief_confirmations   *─1 brief_versions (restrict)
brief_confirmations.carried_from_id ─> brief_confirmations
```

## 6. Visibility and RLS

| Table                    | anon | applicant / suspended / other editor | owning active editor | admin (aal2) |
| ------------------------ | ---- | ------------------------------------ | -------------------- | ------------ |
| `editor_interpretations` | none | none                                 | own (via assignment) | all          |
| `brief_confirmations`    | none | none                                 | own                  | all          |

One combined `for select to authenticated` policy per table (admin, or own row and
`private.is_active_editor()`), as in the Phase 6 visibility migration. No write grants or
policies. `admin_feedback` is meant for the editor; admin-only remarks go to `project_notes`.
`private.editor_project_stage` returns `assigned` for `confirmed` **and** `in_progress`, so the
editor keeps the full brief while working.

## 7. The gate

`private.material_brief_version(project_id)`: the highest version that is `1` or has
`requires_reacknowledgement = true`.

`private.assignment_gate(assignment_id)` returns one row:

| Field                        | Meaning                                                                                                  |
| ---------------------------- | -------------------------------------------------------------------------------------------------------- |
| `compensation_approved`      | status `confirmed`/`in_progress`, `agreed_amount` set, `confirmed_at` set                                |
| `interpretation_required`    | `projects.requires_interpretation`                                                                       |
| `interpretation_accepted`    | an `accepted` interpretation whose version ≥ the material version                                        |
| `current_brief_version`      | `projects.current_brief_version`                                                                         |
| `confirmed_brief_version`    | version of the latest confirmation row (any kind), null if none                                          |
| `reacknowledgement_required` | no confirmation row, or latest row's version < current                                                   |
| `deadline_changed`           | latest row's `confirmed_deadline` is distinct from `projects.deadline`                                   |
| `amount_changed`             | latest row's amount/currency distinct from `agreed_amount`/`agreed_currency`                             |
| `deliverables_changed`       | latest row's `confirmed_deliverables` differ from the current version's `deliverables` (display only)    |
| `brief_confirmed`            | a latest row exists and none of the three drift flags above (version, deadline, amount) is set           |
| `ready`                      | `compensation_approved and brief_confirmed and (not interpretation_required or interpretation_accepted)` |

`public.get_assignment_gate(assignment_id)` exposes it to an admin or the owning active editor
(others: `ES422` "Assignment not found."), for the screens' drift banners.

DB enforcement: a `BEFORE UPDATE` trigger on `assignments` refuses any change into `in_progress`
unless the gate is `ready` (`ES409`); a `BEFORE UPDATE OF status` trigger on `projects` refuses
`in_progress` unless the project has an `in_progress` assignment. Both are `BEFORE UPDATE` only,
like the Phase 6 guards, so tests may seed rows; no role has insert grants and no function inserts
`in_progress` rows (§12 call 9).

Phase 8 constraint: submissions must require `ready` (so a material brief change after start
forces re-confirmation before the next submission, KB §5.1 "before work continues").

## 8. Functions

Editor (`require_active_editor()` first; another editor's or an unknown assignment id is the same
`ES422` "Assignment not found."; then `lock_assignment`):

- `editor_submit_interpretation(p_assignment_id, p_brief_version, p_will_reproduce, p_will_adapt,
p_questions) → uuid`: assignment `confirmed`/`in_progress`; project `assigned`/`in_progress`
  and not archived; interpretation required (`ES409` otherwise); `p_brief_version` = current
  (`ES409` "The brief changed; review it again."); no `submitted` row pending (`ES409`); no
  accepted row still valid (`ES409`).
- `editor_confirm_brief(p_assignment_id, p_brief_version, p_deadline, p_amount, p_currency) →
uuid`: same state checks; the four values must equal the current version, deadline and agreed
  pay (`ES409`: optimistic check that the editor confirms what they saw); deadline set (`ES409`);
  interpretation accepted when required (`ES409`, KB order 6 before 7); refused if the gate already
  shows `brief_confirmed` (`ES409`). Inserts a `confirmed` row with copies.
- `editor_start_work(p_assignment_id)`: assignment `confirmed`, project `assigned`, not archived,
  gate `ready` (`ES409` naming the first unmet condition); sets assignment `in_progress`,
  `started_at`, `started_by`, then project `in_progress`.

Admin (`require_admin()` first):

- `admin_review_interpretation(p_interpretation_id, p_decision, p_feedback)`: `p_decision` in
  (`accept`, `request_changes`); only `submitted` rows (`ES409`); `request_changes` needs feedback
  (`ES422`); `accept` refused when the brief has changed materially since submission (`ES409`).
- `admin_start_work(p_assignment_id)`: same rules as `editor_start_work`, editor must still be
  active (`ES409`); `started_by` = admin.
- Phase 6 replacements: `close_live_assignments` (withdraw includes `in_progress`),
  `admin_reassign` (from `confirmed` or `in_progress`, project `assigned` or `in_progress` → `open`),
  `admin_revoke_project_access` and `admin_withdraw_offer` (`in_progress` → "use reassign"),
  `admin_make_offer` (live set includes `in_progress`), `admin_pending_revocations` (active set
  includes `in_progress`), `project_transition_allowed` (adds `in_progress → cancelled`; cancelling
  closes the assignment `withdrawn`; pay consequences stay F).
- Unchanged: `admin_confirm_assignment` (§4.1), `admin_save_brief`, `admin_update_project`
  (deadline and `requires_interpretation` edits are allowed and show up through the gate).

Trigger: `private.carry_forward_confirmations()` `AFTER INSERT ON brief_versions`: when
`new.version > 1` and `requires_reacknowledgement = false`, for each assignment on the project in
`confirmed`/`in_progress` whose latest confirmation is for `new.version - 1`, insert a
`carried_forward` row for the new version copying that row's confirmed deadline, deliverables
(from the new version's snapshot, identical because deliverable changes force re-acknowledgement)
and amount; `carried_from_id` = that row. Audit `brief_confirmation.carried_forward`.

Audit actions: `interpretation.submitted|accepted|changes_requested`,
`brief_confirmation.confirmed|carried_forward` (ids, version numbers, kind only);
`assignment.in_progress` and `project.in_progress` come from the existing audit triggers.

## 9. Transition table (assignment; project in brackets)

| From                       | Action (who)                          | To                                           |
| -------------------------- | ------------------------------------- | -------------------------------------------- |
| `accepted`                 | confirm (admin, Phase 6)              | `confirmed` [`open → assigned`]              |
| `confirmed`                | submit interpretation (editor)        | unchanged; interpretation `submitted`        |
| interpretation `submitted` | accept / request changes (admin)      | `accepted` / `changes_requested`             |
| `confirmed`/`in_progress`  | confirm brief (editor)                | unchanged; confirmation row                  |
| `confirmed`                | start (editor or admin), gate `ready` | `in_progress` [`assigned → in_progress`]     |
| `confirmed`/`in_progress`  | reassign (admin)                      | `reassigned` [`assigned/in_progress → open`] |
| `confirmed`/`in_progress`  | cancel project (admin)                | `withdrawn` [`→ cancelled`]                  |
| brief vN+1, re-ack `false` | save brief (admin)                    | carried-forward row for vN+1                 |
| brief vN+1, re-ack `true`  | save brief (admin)                    | gate: re-confirmation required               |
| deadline edited            | update project (admin)                | gate: re-confirmation required               |

Refused: start without the gate; start from any status but `confirmed`; start on `on_hold`,
cancelled or archived projects; `admin_set_project_status(.., 'in_progress')`; any direct write.

## 10. Tests

pgTAP per migration, identities admin (aal2), admin aal1, editor A (confirmed), editor B (another
project), suspended S, applicant, anon: schema constraints and immutability (update/delete refused,
actor clearing allowed); visibility of both tables per identity and immediate loss on suspension;
editor stage `assigned` for `in_progress`; every gate field under each condition; every function
transition and refusal; carry-forward rows (false) vs none (true); deadline and amount drift;
optimistic-check refusals; trigger enforcement with direct updates as the table owner; reassign
and cancel from `in_progress`; Phase 6 matrix (052) and Phase 4 matrix (044) updated; function
catalogue and data hygiene (no client columns; audit details without text, amounts or URLs).
Vitest for form schemas; Playwright signed-out gates for any new route.

## 11. Screens outline (after the database is reviewed)

Editor `/editor/projects/[id]` (assigned stage): steps panel "Interpretation → Confirm brief →
Start"; interpretation form (three fields, history with admin feedback); confirmation card showing
version, deadline, deliverables and agreed pay with one "I confirm" action (sends the displayed
values); "Start work" when ready; banners for re-confirmation (brief changed / deadline changed).
Admin project page: per-assignment gate panel (`get_assignment_gate`), interpretation review
(accept / request changes with feedback), confirmation history (confirmed vs carried forward), drift
warnings, "Start work" on the editor's behalf. Derived labels (decision J): Awaiting interpretation,
Interpretation to review, Awaiting brief confirmation, Ready to start, In progress, Re-confirmation
needed.

## 12. Calls made (owner may override)

1. **Order (flagged):** admin confirmation (Phase 6) stays first because decision B shows the full
   brief only after it; interpretation and brief confirmation follow; `in_progress` is the gated
   step. `admin_confirm_assignment` is unchanged (§4.1).
2. **Two start paths**, `editor_start_work` and `admin_start_work`, with the identical gate; the
   row records who started. The owner may drop either.
3. **Interpretation before brief confirmation** when required (KB order 6 before 7).
4. **No mutable confirmation status:** `kind` + derived gate state.
5. **Material baseline:** an accepted interpretation stays valid until a version with
   `requires_reacknowledgement = true`; a newer such version requires a new interpretation.
6. **Drift (flagged):** any change of deadline (later, earlier or cleared) or agreed pay after
   confirmation requires re-confirmation; deliverables changes already force a new version with
   re-acknowledgement. Phase 7 has no path that changes the agreed pay (F stays open), so the pay
   check is defensive. This is a workflow rule, not a late-delivery rule (KB5 stays open).
7. **After start,** a material change does not move the assignment back; the gate turns not ready,
   the editor re-confirms (and re-interprets if required), and Phase 8 submission requires `ready`.
8. **Optimistic confirmation:** the editor's confirmation carries the version, deadline and pay
   they were shown; a mismatch is refused.
9. **Gate triggers are `BEFORE UPDATE` only** (seedable in tests, consistent with Phase 6); no
   role can insert rows directly.
10. **Interpretations only when required;** text only (no uploads); one pending per assignment.
11. **Cancellation allowed from `in_progress`** (assignment `withdrawn`); `on_hold` from `assigned`
    and `in_progress` stays refused. Pay consequences stay F.
12. **`requires_interpretation` turned on after confirmation** applies through the gate (start or
    the next submission needs an accepted interpretation).

## 13. Open questions touched

F (pay after confirmation, cancellation pay) and KB5 (late delivery) remain open; this design
stores and compares values only and adds no pay or penalty rule. Nothing in this phase is blocked.
