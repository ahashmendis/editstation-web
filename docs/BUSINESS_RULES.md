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
- **Extra work (F2, 2026-11-15):** an extra client revision round that needs additional paid work,
  or a scope change, gets extra editor compensation agreed per job. It is offered to the editor
  and explicitly accepted in the app **before** the extra work begins; a scope change's editor
  amount is agreed alongside the revised client price. The original agreed amount is never edited.
  _(Phase 12D part 2: an accepted offer is its own payment row, payable when accepted and due
  within the editor pay days; the client charge for an extra round or scope change has a due date
  the admin enters per charge, with no default, call 5.)_
- **Cancellation (F2):** a cancellation/kill-fee schedule based on how far the work got is agreed
  per project before work begins. The editor is paid for completed work plus any agreed
  cancellation compensation; a client cancellation never automatically forfeits editor pay.

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
  Editors can report a link they cannot open; every report notifies the admin.
- Access type is recorded per asset: shared with the editor's own account (preferred) or "Anyone
  with the link" (accepted, flagged, shown to the admin with a security warning). A working URL is
  never proof that access is authorised or that the editor can open it.
- When an editor leaves a project or it ends, the admin asks the client to remove the editor's
  access and records whether removal is confirmed. Ending an assignment never implies removal.

## Submissions

Keep every submission version and its feedback; never overwrite.

## Vetting (KB §7.4)

Application → portfolio review → shortlist → optional practical test/interview → review → approve
or decline → initial level (junior / professional / specialist) and specialisations. Commercially
useful tests should be paid; substantial unpaid tasks are not a default screen. Whether tests are
paid and tracked here: OPEN_QUESTIONS G.

## Payments (KB §8.2; decision KB9, 2026-11-15)

- Manual bank transfers; no payment gateway and no escrow in the MVP.
- **Client billing** (admin-only, never editor-visible): milestones are configured per project and
  agreed before production. Default 50% deposit before production, 50% balance due **7 calendar
  days** after the agreed completion/approval milestone. 100% upfront or agency invoice terms are
  allowed when agreed (KB9b).
- **Deposit gate (KB9b-4):** work cannot start until the client deposit is received and verified
  by an admin, the editor has accepted, compensation is agreed and the brief is confirmed.
- **Unpaid deposit (KB9a-2):** default 14 calendar days after the deposit invoice is issued; then
  the project goes on hold automatically and the admin extends or cancels. _(Phase 12C: due date =
  invoice date + deposit days in the business timezone, default Asia/Colombo; the hold applies from
  the next calendar day, once per due date, only when an editor is confirmed.)_
- **Editor compensation** is separate from client billing. The total is agreed before work
  starts. Default milestones: 50% at commencement (client deposit verified, assignment
  confirmed); 50% after final approval and receipt of the client balance. Lenscape pays each
  editor milestone by default **within 7 calendar days** of it becoming payable. _(Phase 12D part
  1: milestone shares come from the agreed terms; odd amounts put the rounding remainder on the
  last milestone (call 9); the due date is the business-timezone date it became payable plus the
  agreed editor pay days.)_
- **Late client balance (KB9a-1):** if the balance is still unpaid **14 calendar days after it
  became due**, the editor's second milestone becomes payable anyway and Lenscape carries the
  collection risk, unless there is a genuine delivery dispute or contractual issue. _(Phase 12D
  part 1: applies from the calendar day after due date + late-balance days, once every remaining
  balance invoice is issued and overdue, and only while no disputed part of the editor's pay on
  that assignment is on hold.)_
- **Disputes (KB9a-4):** only the disputed portion of the editor's second payment goes on hold;
  undisputed amounts are not frozen.
- **Cancellation after deposit (KB9a-3):** the client is refunded the unused portion after
  deducting agreed completed work and cancellation charges; the editor keeps pay for completed
  work and any agreed kill fee; any editor overpayment is reconciled by an audited reversal.
  _(Phase 12D part 2: the client charge is the client price (deposit + balance milestones) times
  the stage's agreed client percentage; the refund is verified deposit and balance money above
  that charge; extra-work client payments (extra rounds, scope changes) are excluded from the
  refund. Editor earned is the agreed pay times the stage's editor percentage plus accepted extra
  pay in full, changeable by the admin only with a recorded reason; paid extra pay is never
  reversed and unpaid extra pay stays payable. Amounts round to cents. No percentage is ever
  defaulted. Reassignment (not cancellation) keeps the ended editor's unpaid payments on hold for
  the admin to resolve; a later cancel does not settle them (owner to confirm).)_
- **Editor view (KB9a-5):** editors may see "Waiting for client payment", never the client's
  price, balance, payment history or other confidential financial information.
- Every milestone (client or editor) records amount, currency, due date, transfer reference and
  verification status. All day counts above are defaults the admin may change per project before
  it starts; the agreed terms are kept as an auditable record. No amounts are defaulted.
- A payment is marked paid only after an authorised admin verifies the transfer, and (E) only to a
  verified payout account.
- Only authorised admin users may mark a payment paid.
- Never store online-banking passwords, PINs or auth codes. Store only necessary payment details.
- Bank details (decision E, 2026-11-11): never collected in the application; entered by the editor
  after approval. A changed bank account must be verified by an admin out of band before any
  payment is made to it.

## Copyright (KB §5.2)

References communicate style only. Editors use project-supplied or properly licensed assets.
