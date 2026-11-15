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
- Editor pay for chargeable rounds, scope changes, cancellation or kill fees: undecided
  (OPEN_QUESTIONS F2).

## Revisions and scope (KB §6.1; decision F, 2026-11-15)

- **The revision policy is set per project**, not universally. Options: no included revisions
  (client revisions chargeable from round 1, also called "paid revisions from the first round";
  same policy, F3) or a configurable number of included rounds (e.g. 3); plus a configurable
  client charge for each additional round. The new-project form pre-fills 3 included rounds (owner, 2026-11-15); the admin changes it per project (e.g. to 0). No charge amount is ever defaulted.
- The agreed policy is recorded against the project as an **auditable agreement** before work
  begins and is not silently changed afterwards. Any later change is a new, recorded agreement.
- Three separate categories, classified by the admin:
  - **Editor correction:** fixing a mistake against the approved brief. Never charged to the
    client; never uses an included round.
  - **Client revision:** a requested change to a submitted version. Uses an included round, or is
    chargeable under the project's policy.
  - **Scope change:** new requirements or a substantial change of creative direction. Quoted
    separately; never counted as a revision.
- Record the reason for every change request and whether it uses an included round or is
  chargeable.
- Client revision charges are client pricing: admin-only, never visible to editors.

## Assets (decision KB7, 2026-11-15)

- Project assets are client-provided Google Drive or Dropbox links. EDITSTATION stores links and
  metadata only; it never hosts large video files.
- Links need not be public. The client grants access to the authorised editor.
- Each asset records name, description, access instructions and an access verification status.
  Editors can report a link they cannot open.

## Submissions

Keep every submission version and its feedback; never overwrite.

## Vetting (KB §7.4)

Application → portfolio review → shortlist → optional practical test/interview → review → approve
or decline → initial level (junior / professional / specialist) and specialisations. Commercially
useful tests should be paid; substantial unpaid tasks are not a default screen. Whether tests are
paid and tracked here: OPEN_QUESTIONS G.

## Payments (KB §8.2; decision KB9, 2026-11-15)

- Manual bank transfers; no payment gateway and no escrow in the MVP.
- **Client billing** (admin-only, never editor-visible): proposed standard 50% before production
  begins, 50% at completion under the agreed delivery and approval terms (KB9b: fixed or
  per-project default).
- **Editor compensation** is separate from client billing. The total is agreed before work
  starts. Proposed standard: 50% at commencement, after the client deposit has cleared and the
  editor has confirmed the assignment; 50% after final approval and receipt of the matching client
  balance. What happens when the client pays late or never: OPEN_QUESTIONS KB9a.
- Every milestone (client or editor) records amount, currency, due date, transfer reference and
  verification status. No amounts or day counts are defaulted.
- Only authorised admin users may mark a payment paid.
- Never store online-banking passwords, PINs or auth codes. Store only necessary payment details.
- Bank details (decision E, 2026-11-11): never collected in the application; entered by the editor
  after approval. A changed bank account must be verified by an admin out of band before any
  payment is made to it.

## Copyright (KB §5.2)

References communicate style only. Editors use project-supplied or properly licensed assets.
