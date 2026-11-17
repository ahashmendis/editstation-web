# Open Questions

Do not invent answers. Recommendations below are **not decisions** until recorded in the decisions
log. When a question is answered, log it with the date and update the affected docs.

Contents: [Index](#index) · [Decisions log](#decisions-log) · [Tier 1: blocks Phase 1](#tier-1-blocks-phase-1) ·
[Tier 2: blocks Phases 2–3 or public launch](#tier-2-blocks-phases-23-or-public-launch) ·
[Tier 3: later phases](#tier-3-later-phases) · [Resolved](#resolved)

Question IDs: **A–K** from the architecture review, **L–V** raised by the 2026-11-11 clarification,
**KB1–KB10** = KB §17 items 1–10.

## Index

Open items first. Read a question's full section only when it becomes relevant.

| ID   | Topic                                       | Status                                                            | Blocks                        |
| ---- | ------------------------------------------- | ----------------------------------------------------------------- | ----------------------------- |
| W    | Re-application after withdrawal             | Adopted 2026-11-17 (keep)                                         | —                             |
| G    | Practical tests: paid? tracked?             | Adopted 2026-11-17 (direction)                                    | Assessment payments not built |
| P    | Data retention and privacy notice           | Partly: technical adopted; periods and notice need counsel        | Public launch                 |
| KB1  | Legal registration and entity               | Open                                                              | Public launch                 |
| KB2  | Final brand (trademark/domain)              | Name and domain chosen 2026-11-17; not registered; trademark open | Launch, production email      |
| KB3  | Services and deliverables at launch         | Structure adopted; list needed                                    | Launch content                |
| KB8  | Editor contract and portfolio permission    | Open                                                              | Launch of registration        |
| A2   | Narrower "mark paid" permission             | Adopted 2026-11-17 (defer)                                        | Second admin only             |
| B    | Editor visibility before assignment         | Resolved 2026-11-14                                               | —                             |
| C    | Several editors accepting the same project  | Resolved 2026-11-14                                               | —                             |
| F    | Client revision policy (per project)        | Resolved 2026-11-15 (owner)                                       | Phase 12 (not built)          |
| F2   | Editor pay: chargeable rounds, scope, kills | Resolved 2026-11-15 (owner)                                       | Phase 12 (not built)          |
| F3   | "No included" vs "paid from round 1"        | Resolved 2026-11-15 (same)                                        | —                             |
| I    | Canonical payment statuses                  | Resolved 2026-11-14                                               | —                             |
| K    | Asset sharing: per-account vs link          | Resolved 2026-11-14                                               | —                             |
| KB4  | Client prices and editor pay ranges         | Adopted 2026-11-17 (per project); figures needed                  | Pilot                         |
| KB5  | Turnaround and late-delivery rules          | Partly: flags adopted; policy numbers needed                      | Policy for pilot              |
| KB6  | Project communication                       | Resolved 2026-11-14 (pilot)                                       | —                             |
| KB7  | Storage provider                            | Resolved 2026-11-15 (owner)                                       | Phase 12 (not built)          |
| KB7a | Client link sharing: limits and clean-up    | Resolved 2026-11-15 (owner)                                       | Phase 12 (not built)          |
| KB9  | Payment schedule (client and editor)        | Resolved 2026-11-15 (owner)                                       | Phase 12 (not built)          |
| KB9a | Late/unpaid client balance: editor impact   | Resolved 2026-11-15 (owner)                                       | Phase 12 (not built)          |
| KB9b | 50/50 fixed or per project; payment terms   | Resolved 2026-11-15 (owner)                                       | Phase 12 (not built)          |
| KB10 | Notification events for release 1           | Resolved 2026-11-14                                               | Phase 10                      |

Resolved (see decisions log): A, B, C, D, E, F, H, I, J, K, KB6, KB7, KB9, L, M, N, O, R, S, T,
U, V.

The 2026-11-15 decisions (KB7, F, KB9) are recorded but **not built**. What the code does today
and what must change: `docs/DATABASE_SCHEMA.md` "Planned changes from the 2026-11-15 decisions".

## Decisions log

Format: date, question: decision.

- 2026-11-11, Phase 0 scope: Approved by owner.
- 2026-11-11, Public entry points: Public website with two separate entry points: client/agency inquiry form (no accounts, never auto-creates a project, admin converts manually) and editor registration. No client portal.
- 2026-11-11, **D** Editor registration flow: Editors create an account first (email + password), complete an application, and wait for admin verification. Registering grants no editor access; only an explicit admin approval activates it. The public-form-only application approach is not used.
- 2026-11-11, **A** Admin structure: One admin at launch. Architecture supports multiple admins later via `admin_users` (no schema change). Admin accounts require TOTP MFA from launch. A narrower "mark paid" permission is **deferred** to Phase 9 (still open as A2).
- 2026-11-11, **L** Status model: Adopt the split. Editor access status: `none`, `active`, `suspended`, `revoked` (only `active` grants editor access; only admin functions change it). Application status: `draft`, `submitted`, `under_review`, `info_requested`, `test_requested`, `approved`, `rejected`, `withdrawn`, which may still be adjusted before Phase 2 migrations.
- 2026-11-11, **R** Email verification: Required: applicants must verify their email before using their account. Production needs custom SMTP on a verified domain (depends on KB2).
- 2026-11-11, **M** Re-application: A rejected applicant cannot re-apply on their own. Only an admin can reopen an application; each attempt is kept as a separate `editor_applications` record (history preserved).
- 2026-11-11, **E** Bank details: Never collected in the application. Collected in the app only after approval, before the first payment, entered by the editor. Fields: account holder name, bank, branch, account number. Readable only by the owning editor and admins; account number masked by default. Every change is audited, flagged to the admin and held as unverified until the admin confirms it out of band (e.g. by phone); no payment to unverified details. Never banking passwords, PINs or codes. PDPA handling to be confirmed with counsel. Built in Phase 9.
- 2026-11-11, **N** Inquiry statuses: Full set: `new`, `reviewing`, `contacted`, `in_discussion`, `converted`, `declined`, `closed`, `spam`.
- 2026-11-11, **U** Inquiry uploads: Links only; no file uploads on the public form in the MVP.
- 2026-11-11, **V** Budget field: Preset ranges plus "Prefer to discuss", currency stored. Ranges are admin-managed; none are seeded until the owner supplies them (no invented pricing).
- 2026-11-11, **H** Currency: LKR by default; currency stored on every amount.
- 2026-11-11, **S** Website content: English only; placeholder copy until brand (KB2) and services (KB3) are settled.
- 2026-11-11, **O** Spam protection: Honeypot and rate limits now; Cloudflare Turnstile added before public launch (launch gate).
- 2026-11-13, **T** Client records: Adopt the recommendation. A minimal admin-only `clients` table, created when the first inquiry is converted, so repeat clients link across inquiries and projects. No client-facing access. `client_contacts` is not part of this decision.
- 2026-11-13, **J** Project status: Adopt the recommendation (WORKFLOWS §5). The project has a coarse status (`draft`, `open`, `assigned`, `in_progress`, `in_review`, `revision_requested`, `approved`, `completed`, plus `on_hold` and `cancelled`). Invited, Negotiation and Awaiting confirmation are **assignment** states; the project screen shows labels derived from its assignments.
- 2026-11-14, **B** Editor visibility before assignment: Adopt the recommendation (owner instruction "accept all recommended options"). Tiered access: before admin confirmation an invited/eligible editor sees an opportunity summary (title, brief type, deliverables summary, deadline, proposed pay, references the admin marks non-confidential); the full brief and assets only after admin confirmation. A per-asset/per-reference flag lets admins expose samples early.
- 2026-11-14, **K** Asset sharing: Adopt the recommendation. Per-account sharing, one folder per project, each share logged in `asset_access_grants`, with a revoke checklist on unassignment, suspension and project close. The app stores links and metadata only.
- 2026-11-14, **C** Several editors accepting: Adopt the recommendation. The admin chooses manually; the others are marked "not selected". No first-come-first-served.
- 2026-11-14, **KB6** Project communication: Adopt the recommendation for the pilot. Email or the existing channel, plus an admin-only notes log per project; no in-app chat.
- 2026-11-14, **KB7** Storage provider: still open (needs the owner's actual provider). Phase 5 stores a provider value per asset (Google Drive, Dropbox, other), so the schema does not wait on it.
- 2026-11-14, **I** Payment statuses: Adopt the recommendation (owner instruction: accept recommended). `not_due` → `pending_approval` → `approved` → `processing` → `paid`, plus `on_hold` (reachable from any state before paid, with a required reason; a dispute is a reason). The record is created at assignment confirmation so committed-but-unpaid costs show. `paid` is final; corrections happen through an audited reversal entry. No `cancelled` status (depends on F, still open). Design: `docs/superpowers/specs/2026-11-14-phase9-earnings-design.md`.
- 2026-11-14, **KB10** Notification events: Adopt the recommendation (owner instruction "accept recommended"). To admin: new inquiry, new application, applicant response, counteroffer, submission. To applicant: application decision, information or test request. To editor: invitation, rate confirmed (assignment confirmed), revision requested, payment marked paid. Delivery: in-app now; email rows are queued in an outbox but not sent until production SMTP exists (launch gate). No external services.
- 2026-11-15, **KB7** Storage provider (owner): Client-provided **Google Drive and Dropbox** links. EDITSTATION stores asset metadata and links only and never hosts large video files. Links need not be public: the client grants access to the authorised editor. Per asset: provider, link, asset/folder name, description, access instructions, access verification status; editors can report a link as inaccessible. Narrows K: sharing is done by the client, not by Lenscape, so `asset_access_grants` records what the client shared and who verified it. Open follow-ups: KB7a.
- 2026-11-15, **F** Revision policy (owner): Configurable **per project** (the new-project form pre-fills 3 included rounds; the admin changes it, e.g. to 0), replacing the universal "3 free rounds". Policy: a configurable number of included client rounds (0..n, e.g. 3), where 0 means client revisions are chargeable from round 1 (F3: "no included revisions" and "paid revisions from the first round" are the same policy), plus a configurable client charge for each additional round. Three separate categories: **editor corrections** (mistakes against the approved brief, never charged to the client), **client revisions** (requested changes to a submitted version; these use included rounds or are charged), **scope changes** (new requirements or substantial change of creative direction, quoted separately). The agreed policy is recorded against the project as an auditable agreement and is **not silently changed after work begins**. No charge amounts are set by default (owner/admin enters them per project). Open follow-ups: F2, F3.
- 2026-11-15, **KB9** Payment schedule (owner): Proposed standard. **Client:** 50% before production begins, 50% at completion under the agreed delivery and approval terms. **Editor** (separate from client billing): total compensation agreed before work starts; 50% at commencement, after the client deposit has cleared and the editor has confirmed the assignment; the remaining 50% after final approval and receipt of the corresponding client balance. Bank transfers only; no payment gateway or escrow in the MVP. Record for every milestone: amount, currency, due date, transfer reference and verification status. Open follow-ups: KB9a, KB9b; E (payout details) is now needed before the first editor milestone.
- 2026-11-15, **F2** Editor pay for extra work and cancellations (owner): (a) Extra client revision round: extra editor compensation where the round needs additional paid work, agreed per job **before the round begins**. (b) Scope change: extra editor compensation agreed per job, alongside the revised client price, **before the scope change begins**. (c) Cancellation after work starts: an amount based on how far the work got, using a cancellation/kill-fee schedule **agreed per project before work begins**; the editor is paid for completed work plus any agreed cancellation compensation; a client cancellation never automatically forfeits editor pay. (d) Any additional editor compensation is an offer the editor explicitly accepts in the app before the extra work begins.
- 2026-11-15, **KB9a** Late or unpaid client money (owner): (1) Approved work, client balance unpaid: Lenscape pays the editor's second milestone after a waiting period, default **14 calendar days after the client balance becomes due**, and carries the collection risk from then on, unless there is a genuine delivery dispute or contractual issue. (2) Client deposit not cleared: default **14 calendar days after the deposit invoice is issued**; then the project is automatically put on hold and the admin decides to extend or cancel; no editor work starts before clearance. (3) Cancellation after the deposit: refund the client's unused portion after deducting agreed completed work and applicable cancellation charges; the editor keeps pay for completed work and any agreed kill fee; any editor overpayment against the cancellation terms is reconciled (audited reversal); neither a full deposit refund nor keeping the whole first 50% is automatic. (4) Client disputes the final delivery: only the **disputed portion** of the editor's second payment goes on hold while the admin investigates; undisputed amounts are not frozen. (5) Editors may see a status such as "Waiting for client payment", never the client's price, balance, payment history or other confidential financial information.
- 2026-11-15, **KB9b** Payment terms (owner): (1) 50/50 is the **default**, not a universal rule; the admin configures client milestones per project (e.g. 100% upfront, agreed agency invoice terms); all milestones are recorded and agreed before production. (2) Client balance due by default **7 calendar days** after the agreed completion/approval milestone. (3) Lenscape pays each editor milestone by default **within 7 calendar days** after it becomes payable, alongside the KB9a-1 protection. (4) Work cannot start until the client deposit has been received **and verified by an admin**, the editor has accepted the assignment, compensation is agreed and the brief is confirmed. All day counts are defaults the admin may change per project before it starts, recorded as an auditable agreement.
- 2026-11-15, **KB7a** Client file links (owner): (1) "Anyone with the link" folders are accepted but flagged on the asset as such, with the access type and a security warning visible to the admin; access granted to the editor's own account is preferred. A working URL is never proof that access is authorised or that the editor can open it. (2) When an editor leaves a project or it ends, the admin works through an access-revocation checklist: request the client to remove the editor's access and record whether removal is confirmed; ending an assignment never implies access was removed. (3) The admin is notified whenever an editor reports an asset link as inaccessible (adds an event to KB10).
- 2026-11-15, **E** Bank details, build go-ahead (owner): Approved in principle for Phase 12 as decided on 2026-11-11 (entered after approval, masked account number, phone verification of changes, access strictly restricted and audited). A **verified** payout account is mandatory before an editor payment is marked paid. **Real bank details must not be stored until Sri Lankan PDPA requirements are reviewed with counsel**: the interface and technical design may be prepared, but live collection waits for that confirmation.
- 2026-11-15, **Phase 12 principles** (owner): Payment schedules, extra-work fees, cancellation terms and revision policies are configurable and recorded per project; the stated values are operational defaults the admin may change before a project starts. Every change and approval is audited; agreed financial terms are never silently changed after work begins; client financial data stays separate from editor-visible data; a payment is marked paid only after an authorised admin verifies the transfer; work never starts before the client-deposit, editor-acceptance and brief-confirmation gates are satisfied.
- 2026-11-15, **Phase 12 design** (owner): Approved `docs/superpowers/specs/2026-11-15-phase12-commercial-terms-design.md` with the recommended answer to all 11 calls: (1) interim per-editor "payout account verified outside the app" attestation (admin and date, no bank data) until E is live; (2) add a `cancelled` payment status (revises I); (3) allow `assigned -> on_hold` for the unpaid-deposit rule only; (4) business timezone is an admin setting, default Asia/Colombo; (5) client due date for extra-round and scope-change charges entered per charge, no default; (6) client-only terms changes after work begins need a reason, editor-affecting ones need editor acceptance; (7) timed rules run in one idempotent function (pg_cron on hosted, admin trigger as backstop); (8) add four notification events (adjustment offered, adjustment answered, project auto-held, late-balance protection); (9) rounding: the last milestone takes the remainder; (10) backfill existing local projects with terms v1 from `revision_allowance`; (11) slices in order 12A and 12B, then 12C, 12D, 12E.
- 2026-11-11, **KB3** Service list: Not supplied yet: admin-managed list seeded with placeholder categories taken from KB §7.1, editable in the admin settings screen. The final list remains open.

- 2026-11-16, **B/C amended** Open opportunities: Owner approved the concept of an "Open opportunities" page for active editors only: summary only (no client names, client pricing or files), editors register interest with an optional proposed rate, the admin chooses one editor manually (no first-come-first-served) and that becomes the existing invitation and negotiation flow; others see "not selected". This relaxes the earlier no-listing rule only to this summary-only form. Details, limits and calls are in docs/superpowers/specs/2026-11-16-open-opportunities-design.md (awaiting owner approval before any build).
- 2026-11-17, **Adopt recommendations** (owner): The owner approved adopting the assistant's existing documented or previously presented recommendations, only where no counsel input or missing information is needed. Adopted below as W, G, P (technical part only), KB2 (process), KB3 (structure), KB4, KB5 (stored deadlines and flags only) and A2. Not adopted, still open: KB1, KB8, the retention periods and privacy notice text in P, the actual KB3 service list, KB4 figures and KB5 turnaround numbers, trademark clearance, production email sender.
- 2026-11-17, **W** Re-application after withdrawal: Adopted the recommendation: keep the current behaviour. A withdrawn applicant cannot reapply on their own; an admin must reopen the application (same as rejection, decision M).
- 2026-11-17, **G** Practical tests: Adopted the recommendation: track practical tests in the app (instructions, submission link, result; assessment results exist since Phase 2). If a test is paid, record the payment with type `assessment` and no project. Not built yet: assessment-type payments. Whether tests are paid at all is an owner commercial choice still to state.
- 2026-11-17, **P** Data retention and privacy notice: Adopted only the technical recommendation: store the privacy-notice version accepted on each record (already stored) and plan a scheduled deletion/anonymisation job. Still pending counsel: the retention periods, how far audit entries must be scrubbed after account deletion, and the privacy notice text. Blocks limited public launch.
- 2026-11-17, **KB2** Brand and domain (owner): Final public brand name is EDITSTATION. Selected domain is editstation.work; the promotional price shown was EUR 2.71 per year. The domain is NOT confirmed registered; nothing was purchased and no DNS, hosting or email is configured. Adopted process recommendation: build with EDITSTATION and run the trademark checks (KB section 2.2) before launch. Still open: registration, trademark clearance, production email sender domain, Turnstile setup (all depend on the domain).
- 2026-11-17, **KB3** Services and deliverables: Adopted the structural recommendation (admin-managed `service_types` list, already built). The real launch list is still owner information to supply.
- 2026-11-17, **KB4** Client prices and editor pay ranges: Adopted the previously presented recommendation: quote per project for the pilot, no published ranges. No figures are invented; any guide ranges remain the owner's to supply.
- 2026-11-17, **KB5** Turnaround and late delivery: Adopted the recommendation: the app stores deadlines and flags late submissions; penalties are not automated. Standard turnaround per service, extension handling and the late-delivery consequences remain owner policy to state.
- 2026-11-17, **A2** Narrower mark-paid permission: Adopted the recommendation: stay deferred until there is a second admin.
- 2026-11-17, **Landing page** (owner): Use the previously recommended direction already built (light base, landing-only fonts, client strip, reels strip, no testimonials). Items needing the owner's separate permission are listed in docs/LAUNCH_READINESS.md section 3.
- 2026-11-17, **Client area** (owner, supersedes the MVP exclusion of a client portal): Clients get accounts and a `/client` area to submit projects, monitor all their projects and see payments, and message the studio. Clients contact only the studio, never editors, and never see the assigned editor, editor pay, internal notes or asset links meant for editors. Adopted recommendations: admin-invitation-only accounts (no self-signup); sign-in by emailed one-time code (no password); progress shown as admin-written updates plus a mapped client-facing status; payments page shows client milestones (amount, due date, status) and the studio's bank transfer details once the owner supplies them (never invented); several users per client company, added by an admin; a project submission form that creates an inquiry (still a lead, only an admin converts it); a message thread per project with the admin team only. Client terms and privacy notice need counsel before real clients sign in. Design: `docs/superpowers/specs/2026-11-17-client-area-design.md`.

---

## Tier 1: Phase 1 blockers (all resolved 2026-11-11)

Kept for the reasoning behind each decision. The decisions log above is authoritative.

### A. Admin structure (and admin MFA): RESOLVED

- **Question:** One admin at launch or several? Should "mark paid" be a narrower permission? Should
  admin accounts require MFA?
- **Why it matters:** Phase 1 creates the admin model and the bootstrap step, and admin is the
  account whose takeover would expose everything.
- **Recommendation:** Confirm your preference (one admin now). The proposed `admin_users` table
  supports more admins later with no schema change. Defer the narrower "mark paid" permission to
  Phase 9. Require TOTP MFA for admin accounts from day one; Supabase Auth supports it.
- **Alternatives:** Several admins now needs grant/revoke screens and per-admin audit in Phase 1.
  No MFA is simpler but leaves the most powerful account protected only by a password.
- **Blocks:** Phase 1 (bootstrap and admin gate). The MFA part could slip to Phase 2 if needed.

### L. Applicant and editor status model: RESOLVED

- **Question:** Approve the proposed split between application status (`draft`, `submitted`,
  `under_review`, `info_requested`, `test_requested`, `approved`, `rejected`, `withdrawn`) and
  editor access status (`none`, `active`, `suspended`, `revoked`)? See WORKFLOWS §2 for the
  mapping to your six states.
- **Why it matters:** Phase 1 builds `is_active_editor()`, which every editor policy depends on.
  Changing the access states later means rewriting policies and tests.
- **Recommendation:** Adopt the split. Phase 1 needs only the access status; the application
  statuses can still be adjusted before Phase 2.
- **Alternatives:** A single combined status is simpler, but "suspended" then overwrites
  "approved", which loses history and makes reactivation ambiguous. Dropping `revoked` (suspension
  only) is fine if you never need a permanent ban.
- **Blocks:** Phase 1 (access status); Phase 2 (application status).

### R. Email verification at sign-up: RESOLVED

- **Question:** Must applicants verify their email before they can use their account?
- **Why it matters:** It's a Phase 1 auth setting. Without it, anyone can register with someone
  else's email, and admin messages may go to addresses nobody controls.
- **Recommendation:** Require verification. Locally the confirmation emails are caught by the
  built-in mail catcher. Production needs custom SMTP (e.g. Resend) on a verified domain, which
  depends on KB2.
- **Alternatives:** No verification removes friction, but you would be vetting unverified
  identities and receiving more junk applications.
- **Blocks:** Phase 1.

---

## Tier 2: blocks Phases 2–3 or public launch

### M. Re-application after rejection: RESOLVED 2026-11-11 (admin reopens only)

- **Question:** Can a rejected applicant apply again? Immediately, after a waiting period, or only
  if an admin reopens it?
- **Why it matters:** It decides whether `editor_applications` allows several rows per person and
  what a rejected applicant's screen shows.
- **Recommendation:** Allow re-application only after an admin reopens it. Keep each attempt as a
  separate record.
- **Alternatives:** Free re-application invites repeated low-quality attempts. Never allowing it is
  harsh for people who improve.
- **Blocks:** Phase 2.

### N. Client inquiry statuses: RESOLVED 2026-11-11 (full set)

- **Question:** Approve the proposed set: `new`, `reviewing`, `contacted`, `in_discussion`,
  `converted`, `declined`, `closed`, `spam`. Or the shorter alternative: `new`, `in_progress`,
  `converted`, `closed` plus a reason. See WORKFLOWS §1.
- **Why it matters:** Status sets become database enums, and inquiry-to-conversion metrics
  depend on them.
- **Recommendation:** The full set. It separates "we declined" from "client went quiet" and keeps
  spam out of the metrics.
- **Alternatives:** The short set is easier to operate but gives weaker funnel data.
- **Blocks:** Phase 3.

### O. Spam and abuse protection for public forms: RESOLVED 2026-11-11 (honeypot + limits now; Turnstile before launch)

- **Question:** Which captcha (Cloudflare Turnstile, hCaptcha, or none), and what rate limits on
  the inquiry form and sign-up?
- **Why it matters:** Public, unauthenticated write paths are the main abuse surface.
- **Recommendation:** Cloudflare Turnstile on both forms (Supabase Auth supports it for sign-up),
  plus a honeypot field and per-IP rate limits. Verify current Turnstile terms before adopting it.
- **Alternatives:** A honeypot only is free and invisible but weaker against targeted bots.
  hCaptcha is equivalent but adds more friction for users.
- **Blocks:** Public launch of the forms. Development can start with a honeypot only.

### P. Data retention and privacy notice for public forms

- **Phase 2 note:** deleting an account now works and anonymises its audit-log entries (actor removed), but the entries keep their content, which can include the user id in `entity_id`/`details`. Whether that is acceptable, or entries must be scrubbed further, is part of this decision.

- **Question:** How long are unconverted inquiries, rejected applications and withdrawn accounts
  kept? Who drafts the privacy notice?
- **Why it matters:** Public forms collect personal data from people with no relationship to
  Lenscape yet. PDPA obligations (KB §12.3) need confirming with counsel.
- **Recommendation:** Owner and legal decision; no recommended period. Technically, store the
  privacy-notice version accepted on each record and plan a scheduled deletion/anonymisation job.
- **Alternatives:** Keeping everything indefinitely increases risk and may not be compliant.
- **Blocks:** Public launch, not development.

### S. Public website content: RESOLVED 2026-11-11 (English, placeholder copy)

- **Question:** Who writes the copy? Which pages (home, services, about, contact, privacy)?
  English only, or also Sinhala/Tamil?
- **Why it matters:** It drives page structure and translation setup.
- **Recommendation:** English only for the pilot. Minimal pages: home, inquiry, join, privacy.
  Placeholder copy until KB2 and KB3 are settled.
- **Alternatives:** Multilingual from day one adds translation infrastructure and maintenance.
- **Blocks:** Phase 3 content. Structure can be built with placeholders.

### T. Client records: RESOLVED 2026-11-13 (minimal admin-only clients table)

- **Question:** Track clients/agencies as their own records (so repeat clients link across
  inquiries and projects), or keep client details only on each inquiry/project?
- **Why it matters:** It affects conversion, metrics per client, and how much client personal
  data is stored.
- **Recommendation:** A minimal admin-only `clients` table, created when the first inquiry is
  converted.
- **Alternatives:** No client table is simpler, but repeat clients are duplicated and per-client
  history is lost.
- **Blocks:** Phase 4 (conversion).

### U. File uploads on the inquiry form: RESOLVED 2026-11-11 (links only)

- **Question:** May clients upload files (briefs, sample footage), or only paste links?
- **Why it matters:** Anonymous uploads mean storage costs, malware risk and abuse.
- **Recommendation:** Links only in the MVP. Request files by email or a shared folder after first
  contact.
- **Alternatives:** Uploads need a storage bucket, size limits, file-type checks and scanning.
- **Blocks:** Phase 3.

### W. Re-application after withdrawal

- **Question:** If an applicant withdraws their own application, can they submit again on their own, or (like a rejection, decision M) only after an admin reopens it?
- **Why it matters:** Decision M covers rejection only. Phase 2 had to pick a behaviour for withdrawal.
- **Current implementation (not a decision):** treated like rejection: only an admin can reopen. This is the conservative choice and is easy to relax.
- **Alternative:** let applicants re-submit after withdrawing. Friendlier, but a withdraw/resubmit loop could be used to reset a review.
- **Blocks:** nothing; confirm or change at any time.

### V. Inquiry budget field format: RESOLVED 2026-11-11 (admin-managed ranges + discuss)

- **Question:** Free text, preset ranges, or amount plus currency?
- **Why it matters:** It decides whether budgets can be compared or reported. It is linked to H.
- **Recommendation:** Preset ranges in LKR plus an "other/discuss" option, with currency stored.
  The ranges themselves are your decision (KB4).
- **Alternatives:** Free text is flexible but can't be analysed. An exact amount deters clients.
- **Blocks:** Phase 3.

### E. Bank details: RESOLVED 2026-11-11 (option 2: in-app after approval)

- **Question:** Store editor bank details in the app? When, and which fields?
- **Why it matters:** It's the most sensitive data the app would hold.
- **Recommendation:** Never in the application. Collect only after approval, when the first
  payment is approaching: account holder name, bank, branch, account number, all admin + owner
  only. For a 5–10 editor pilot, keeping them outside the app entirely is also reasonable.
- **Alternatives:** Collecting at application time stores bank data for people you may reject.
  Keeping it outside the app means manual reconciliation but the smallest breach impact.
- **Blocks:** Phase 9 only. Phase 2 just needs to confirm that applications contain no bank fields.

### G. Practical tests

- **Question:** Are practical tests paid? If so, are those payments tracked in EDITSTATION?
- **Why it matters:** It shapes `editor_assessments`, and whether `payments` can exist without a
  project.
- **Recommendation:** Track tests in-app (instructions, submission link, result). If they're paid,
  record payments with type `assessment` and no project.
- **Alternatives:** Tracking tests outside the app loses vetting history. Paid tests tracked
  elsewhere split payment records across two places.
- **Blocks:** Phase 2 (assessment record); Phase 9 (payment).

### KB1. Legal registration and entity

- **Why it matters:** It names the data controller in the privacy notice and the counterparty in
  editor terms.
- **Recommendation:** Owner and legal decision; no recommendation.
- **Blocks:** Public launch, not development.

### KB2. Final brand (trademark/domain)

- **Why it matters:** The public website, domain, email sender domain (needed for auth emails and
  Resend) and Turnstile setup all depend on it. Rebranding after launch is costly.
- **Recommendation:** Run the KB §2.2 checks before the public launch; build with the working
  name meanwhile.
- **Blocks:** Public launch and production email, not development.

### KB3. Services and deliverables at launch

- **Why it matters:** It sets the inquiry form's service options and project service types.
- **Recommendation:** Keep them as an admin-managed `service_types` list so the decision doesn't
  block code. You still need to supply the initial list.
- **Blocks:** Phase 3 content (seed values), not structure.

### KB8. Editor contract and portfolio permission

- **Why it matters:** Applicants accept terms at application time, and that acceptance (version
  plus timestamp) is stored.
- **Recommendation:** Owner and legal decision. Development uses a versioned placeholder.
- **Blocks:** Public launch of registration, not development.

---

## Tier 3: later phases

### A2. Narrower "mark paid" permission

- **Question:** When there is more than one admin, should only some of them be able to mark
  payments as paid?
- **Why it matters:** It separates who approves a payment from who records it, which is a basic
  financial control.
- **Recommendation:** Revisit in Phase 9. With one admin it changes nothing. Record
  `approved_by` and `marked_paid_by` from the start so the history is there either way.
- **Blocks:** Phase 9, and only if a second admin exists.

### B. Editor visibility before assignment

- **Why it matters:** It decides what an invited (unconfirmed) editor sees, and whether
  confidential footage leaves Lenscape's control before anyone has committed.
- **Recommendation:** Tiered access. Before confirmation: an opportunity summary (title, brief
  type, deliverables summary, deadline, proposed pay, admin-chosen non-confidential references).
  After admin confirmation: the full brief and assets. A per-asset flag lets admins expose samples
  early.
- **Alternatives:** Full access up front lets editors judge the work better, but exposes client
  footage to editors who may decline. Summary-only with no exceptions sometimes gives too little to
  quote on.
- **Blocks:** Phase 5–6.

### C. Several editors accepting the same project

- **Why it matters:** It decides the selection logic and assignment statuses.
- **Recommendation:** The admin chooses manually. Others are marked "not selected" (a new
  assignment status, to be approved). No first-come-first-served.
- **Alternatives:** First-come-first-served is faster but rewards speed over fit and acts like
  bidding. Offering to one editor at a time is slower but simplest.
- **Blocks:** Phase 6.

### F. Pay for extra rounds, scope changes, cancellation, kill fees: CLIENT SIDE RESOLVED 2026-11-15

The client revision policy is decided (decisions log, F). The editor side and cancellation remain
open as F2 (F3 resolved: "no included" = "paid from round 1"). Original reasoning kept below.

- **Why it matters:** It decides whether agreed pay can change after confirmation.
- **Recommendation:** No rule recommended; this is a commercial decision. Mechanically: a
  `compensation_adjustments` record, proposed by the admin and accepted by the editor, mirroring
  negotiation, so the original agreed amount is never edited.
- **Alternatives:** Editing the agreed amount directly loses the audit trail.
- **Blocks:** Phase 8.

### H. Currency: RESOLVED 2026-11-11 (LKR default, currency stored)

- **Why it matters:** Editor pay is LKR (manual Sri Lankan transfers), but international clients
  may pay in other currencies.
- **Recommendation:** Store currency on every money column. Editor pay stays LKR-only in the pilot.
  Client price and inquiry budget may differ. No conversion logic in the MVP.
- **Alternatives:** LKR everywhere is simplest but misstates international deals. Full
  multi-currency adds exchange-rate handling.
- **Blocks:** Phase 3 (budget field) and Phase 4 (client price).

### I. Canonical payment statuses: RESOLVED 2026-11-14 (recommendation adopted)

- **The difference:** §8.2 lists _Not due · Pending approval · Approved for payment · Processing ·
  Paid · On hold / disputed_. §10.4 lists _Pending approval · Approved · Processing · Paid · On
  hold_. §10.4 drops "Not due" (a record that exists before the work is approved), shortens
  "Approved for payment", and drops "disputed".
- **Recommendation:** `not_due` → `pending_approval` → `approved` → `processing` → `paid`, plus
  `on_hold` (reachable from any state before paid, with a required reason; a dispute is a
  reason). Create the record at assignment confirmation so committed-but-unpaid costs show up.
  `paid` is final; corrections happen through an audited reversal entry. ~~Whether `cancelled` is
  needed depends on F.~~ _Superseded 2026-11-15 (Phase 12 design call 2, owner): `cancelled` was
  added in Phase 12D part 2; it is final and set only by a cancellation settlement._
- **Alternatives:** The §10.4 set creates the record only after approval, so outstanding
  liabilities aren't visible.
- **Blocks:** Phase 9.

### J. Coarse project status, negotiation on the assignment: RESOLVED 2026-11-13 (adopted)

- **Why it matters:** With several editors (C) and reassignments, a project can have more than one
  negotiation at once. A single project-level "Negotiation" status can't represent that.
  KB §10.2 already says to keep assignment status distinct where useful.
- **Recommendation:** Adopt it (WORKFLOWS §5). Invited, Negotiation and Awaiting confirmation
  become assignment states, shown on the project as derived labels.
- **Alternatives:** The full §10.1 list on the project duplicates assignment state, and the two
  can contradict each other.
- **Blocks:** Phase 4.

### K. Asset sharing: per-account vs link-based

- **Per-account sharing** (the editor's Google/Dropbox email): access is tied to a person, can be
  revoked individually, and shows in the provider's audit. Downsides: it collects one more email
  per editor, and sharing and revoking are manual or need API work. Revoking does not undo
  downloads already made.
- **Link-based:** anyone holding the link can open it, and a forwarded link leaks. Revoking means
  disabling the link for everyone, and there's no record of who opened it. RLS hiding the link in
  the app does not protect a link that has been copied.
- **Recommendation:** Per-account sharing, one folder per project, logged in
  `asset_access_grants`, with a revoke checklist on unassignment, suspension and project close.
- **Blocks:** Phase 5.

### KB4. Client prices and editor pay ranges

- **Recommendation:** Owner decision; nothing in code depends on it beyond optional V ranges.
- **Blocks:** The pilot, not development.

### KB5. Turnaround and late-delivery rules

- **Recommendation:** Owner decision. The app will store deadlines and flag late submissions.
  Penalties aren't automated.
- **Blocks:** Phase 8 (late flag); policy before the pilot.

### KB6. Project communication

- **Recommendation:** Email or your existing channel for the pilot, plus an admin-only notes log
  per project. In-app Q&A only if the pilot shows a need (KB §9.4 excludes complex chat).
- **Blocks:** Phase 6.

### KB7. Storage provider: RESOLVED 2026-11-15 (client-provided Google Drive / Dropbox links)

- **Decision:** see the decisions log. Superseded recommendation: "whichever one Lenscape already
  uses".

### KB7a. Client link sharing: limits and clean-up RESOLVED 2026-11-15 (see decisions log)

- **Question 1:** If a client will only give an "anyone with the link" share, is that acceptable,
  or must the admin insist on sharing with the editor's account? (The decision says links need not
  be public; it does not say whether a public link is refused.)
- **Question 2:** Lenscape cannot revoke access to a client-owned folder. At unassignment or
  project close, should the admin send the client a removal request (tracked on the revoke
  checklist), or is that left to the client?
- **Recommendation:** Prefer per-account shares; accept a link share only when the client
  insists, marked as such on the asset. Track a "removal requested" step on the checklist.
- **Blocks:** The pilot, not the schema.

### KB9. Payment schedule: RESOLVED 2026-11-15 (proposed 50/50 standard, bank transfer)

- **Decision:** see the decisions log. Superseded recommendation: "owner decision".

### KB9a. Late or unpaid client balance: impact on the editor RESOLVED 2026-11-15 (see decisions log)

The editor's milestones depend on client money (deposit cleared; balance received). Risks:

- The client pays the balance late or never, after the editor has delivered and the work is
  approved. Is the editor's second 50% held indefinitely, paid after a set period regardless, or
  paid by Lenscape at its own risk?
- The client deposit does not clear after the editor was selected. Does the assignment wait
  (no start, no pay), and for how long before it is cancelled?
- The project is cancelled after the deposit: what is refunded to the client, and what does the
  editor keep of the first 50%? (overlaps F2, kill fees)
- A client disputes the final delivery: does the editor's second payment go on hold?
- Editor contracts (KB8) should state these terms; nothing here is decided by development.
- **Blocks:** The first real project. Needs owner (and possibly legal) input.

### KB9b. 50/50 fixed or per-project; payment terms RESOLVED 2026-11-15 (see decisions log)

- **Question:** Is 50/50 the fixed rule or a per-project default the admin can change (e.g. 100%
  upfront for small jobs, invoice terms for agencies)? What are the due-date terms (days after
  invoice or approval) for the client balance and for each editor payment?
- **Recommendation:** Store milestones per project with 50/50 as the default the admin can
  override before work starts, recorded in the same auditable agreement as the revision policy.
  No default day counts until the owner supplies them.
- **Blocks:** Phase 12 payment design.

### F2. Editor pay for chargeable rounds, scope changes, cancellation and kill fees RESOLVED 2026-11-15 (see decisions log)

- **Question:** When a client pays for an extra revision round or a scope change, is the editor
  paid extra for it, and how is that amount agreed? On cancellation, what does the editor receive
  (kill fee), and does it depend on how far the work got?
- **Recommendation (mechanism only):** a `compensation_adjustments` record proposed by the admin
  and accepted by the editor, mirroring negotiation, so the original agreed amount is never
  edited. Amounts are commercial decisions.
- **Blocks:** Phase 12 payments.

### F3. "No included revisions" vs "paid revisions from the first round": RESOLVED 2026-11-15

- **Question:** The F decision listed both "no included revisions: client-requested revisions are
  chargeable from the first round" and "paid revisions from the first round".
- **Decision (owner):** They are the same policy. A project has 0..n included client rounds; with
  0, every client revision is chargeable from round 1.

### KB10. Notification events for release 1: RESOLVED 2026-11-14 (recommendation adopted; in-app, email queued)

- **Recommendation:** A minimal set:
  - **To admin:** new inquiry, new application, applicant response, counteroffer, submission.
  - **To applicant:** application decision, information or test request.
  - **To editor:** invitation, rate confirmed, revision requested, payment marked paid.
  - **Auth emails:** sign-up confirmation and password reset, from Phase 1.
- **Blocks:** Phase 10 (auth emails in Phase 1).

---

## Resolved

- **D**, **A** (A2 deferred), **L**, **R**, **M**, **E**, **N**, **O**, **S**, **U**, **V**, **H**: resolved 2026-11-11 (KB3 partly: placeholder list, final list open); **J**, **T**: resolved 2026-11-13; **B**, **C**, **K**, **KB6**: resolved 2026-11-14 (see decisions log).
