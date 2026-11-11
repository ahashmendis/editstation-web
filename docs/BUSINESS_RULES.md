# Business Rules

Derived from KB §3.3, §4.4, §6, §7.4, §8 and the owner clarification of 2026-11-11. These are
requirements; enforce them in the database.

## Access

- Registering an account grants **no** editor access _(2026-11-11)_. Editor access exists only
  after an explicit, server-side admin approval and activation, and ends on suspension/revocation.
- Editors must be vetted and approved before accessing restricted work.
- No public project listing, no open bidding, no direct client-to-editor hiring.
- One primary editor per project (initial release).
- Do not expose client-sensitive details to editors unnecessarily.

## Client inquiries _(2026-11-11)_

- An inquiry is a lead, not a project. It never creates a project automatically.
- Only an admin converts an inquiry into a project, after Lenscape has agreed the work with the
  client.
- Client pricing, margins and internal notes are admin-only.

## Compensation (KB §8.1)

- Admin sets a proposed rate. Editor may accept, decline or counteroffer. Admin may accept, reject
  or propose another amount. Invitations to a specific editor use the same process.
- Final compensation is stored as an explicit agreed amount and admin-approved before assignment.
- **An editor cannot begin work while compensation is unresolved.**
- Rate is set by workload, skill, turnaround, complexity and client budget, not by brief type.
- Pay changes for extra rounds, scope changes, cancellation or kill fees: undecided (OPEN_QUESTIONS F).

## Revisions and scope (KB §6.1)

- 3 free client revision rounds by default; additional client rounds may be charged (to the client).
- Editor-caused errors or failure to follow the approved brief are corrected without consuming the
  client allowance.
- New direction, new deliverable, materially changed brief or added scope is a **scope change** or
  new paid task, not a revision.
- Admin decides whether a request is a revision, correction or scope change.
- Record the reason for every change request and whether it consumes a client round.

## Submissions

Keep every submission version and its feedback; never overwrite.

## Vetting (KB §7.4)

Application → portfolio review → shortlist → optional practical test/interview → review → approve
or decline → initial level (junior / professional / specialist) and specialisations. Commercially
useful tests should be paid; substantial unpaid tasks are not a default screen. Whether tests are
paid and tracked here: OPEN_QUESTIONS G.

## Payments (KB §8.2)

- Manual bank transfers in Sri Lanka; no gateway.
- Only authorised admin users may mark a payment paid.
- Never store online-banking passwords, PINs or auth codes. Store only necessary payment details.

## Copyright (KB §5.2)

References communicate style only. Editors use project-supplied or properly licensed assets.
