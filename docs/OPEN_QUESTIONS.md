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

| ID   | Topic                                         | Status                      | Blocks                    |
| ---- | --------------------------------------------- | --------------------------- | ------------------------- |
| W    | Re-application after withdrawal               | Open (conservative default) | Nothing; confirm any time |
| G    | Practical tests: paid? tracked?               | Open                        | Phase 9 (payment)         |
| P    | Data retention and privacy notice             | Open                        | Public launch             |
| KB1  | Legal registration and entity                 | Open                        | Public launch             |
| KB2  | Final brand (trademark/domain)                | Open                        | Launch, production email  |
| KB3  | Services and deliverables at launch           | Partly (placeholder list)   | Launch content            |
| KB8  | Editor contract and portfolio permission      | Open                        | Launch of registration    |
| A2   | Narrower "mark paid" permission               | Deferred                    | Phase 9 (if second admin) |
| B    | Editor visibility before assignment           | Resolved 2026-11-14         | —                         |
| C    | Several editors accepting the same project    | Resolved 2026-11-14         | —                         |
| F    | Pay for extra rounds, scope changes, kill fee | Open                        | Phase 8                   |
| I    | Canonical payment statuses                    | Resolved 2026-11-14         | —                         |
| K    | Asset sharing: per-account vs link            | Resolved 2026-11-14         | —                         |
| KB4  | Client prices and editor pay ranges           | Open                        | Pilot                     |
| KB5  | Turnaround and late-delivery rules            | Open                        | Phase 8; policy for pilot |
| KB6  | Project communication                         | Resolved 2026-11-14 (pilot) | —                         |
| KB7  | Storage provider                              | Open (not blocking schema)  | Phase 5 go-live           |
| KB9  | Payment schedule                              | Open                        | Phase 9                   |
| KB10 | Notification events for release 1             | Open                        | Phase 10                  |

Resolved (see decisions log): A, B, C, D, E, H, I, J, K, KB6, L, M, N, O, R, S, T, U, V.

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
- 2026-11-11, **KB3** Service list: Not supplied yet: admin-managed list seeded with placeholder categories taken from KB §7.1, editable in the admin settings screen. The final list remains open.

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

### F. Pay for extra rounds, scope changes, cancellation, kill fees

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
  `paid` is final; corrections happen through an audited reversal entry. Whether `cancelled` is
  needed depends on F.
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

### KB7. Storage provider

- **Recommendation:** Whichever one Lenscape already uses with business-grade sharing controls.
  Decide together with K.
- **Blocks:** Phase 5.

### KB9. Payment schedule

- **Recommendation:** Owner decision. The data model supports both (due date per payment).
- **Blocks:** Phase 9.

### KB10. Notification events for release 1

- **Recommendation:** A minimal set:
  - **To admin:** new inquiry, new application, applicant response, counteroffer, submission.
  - **To applicant:** application decision, information or test request.
  - **To editor:** invitation, rate confirmed, revision requested, payment marked paid.
  - **Auth emails:** sign-up confirmation and password reset, from Phase 1.
- **Blocks:** Phase 10 (auth emails in Phase 1).

---

## Resolved

- **D**, **A** (A2 deferred), **L**, **R**, **M**, **E**, **N**, **O**, **S**, **U**, **V**, **H**: resolved 2026-11-11 (KB3 partly: placeholder list, final list open); **J**, **T**: resolved 2026-11-13; **B**, **C**, **K**, **KB6**: resolved 2026-11-14 (see decisions log).
