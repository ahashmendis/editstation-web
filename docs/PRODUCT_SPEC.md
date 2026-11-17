# Product Spec

Derived from KB §3.2–3.3, §4, §9, §16, plus the **owner clarification of 2026-11-11** (public
website, client inquiries, editor self-registration). Where that clarification adds to the KB, it
is marked _(2026-11-11)_.

## What EDITSTATION is

An internal production and operations platform operated by Lenscape Studios, with two public entry
points _(2026-11-11)_: client/agency inquiries, and editor registration/applications. These are
separate workflows and must not be confused. It is **not** a marketplace: no open bidding, no
direct client-to-editor hiring. Lenscape owns client relationships, pricing, QC and editor pay.

## Access areas _(2026-11-11)_

| Area                | Who                               | Purpose                                |
| ------------------- | --------------------------------- | -------------------------------------- |
| Public website      | Everyone                          | Introduce EDITSTATION                  |
| Client inquiry form | Everyone (no account)             | Submit potential work                  |
| Editor registration | Prospective editors               | Create an account (email + password)   |
| Editor application  | Registered applicants             | Apply for verification                 |
| Admin dashboard     | Authorised admins                 | Manage inquiries, editors and projects |
| Editor dashboard    | **Approved, active editors only** | Manage authorised work                 |

No client portal, client accounts or client dashboard in the MVP.

## Account types

- **Admin**: everything operational. Never created through public sign-up. Future roles (team
  manager, QC reviewer, finance assistant) are not built until a real need emerges.
- **Applicant** _(2026-11-11)_: anyone who registered. Can manage only their own account and
  application. **Registering grants no editor access.**
- **Editor**: an applicant an admin has explicitly approved and activated. Sees only their own
  records and projects made available/assigned to them. Can be suspended or revoked.

Applicants must **not** be able to view projects, briefs, assets, assignments, other editors'
information, the editor dashboard, or any internal business information.

## Public website _(2026-11-11)_

Introduces EDITSTATION and the production network, with two clearly separate calls to action:
"Send us a project" (client inquiry) and "Join the editor network" (registration). Copy, service
list and brand depend on open questions (KB §17.2, §17.3). Must carry a privacy notice before
collecting personal data publicly (KB §12.3).

## Client and agency inquiries _(2026-11-11)_

**Fields:** contact name · company/agency · email · phone · service type · project description ·
expected deliverables · estimated budget · expected deadline · reference links (multiple) ·
additional notes/supporting information.

**Rules:**

- Submitting an inquiry records it; it **never** creates a project automatically.
- No client account is needed or created.
- Stored separately from projects. An admin manually converts a confirmed inquiry into a project
  after Lenscape has discussed scope, pricing and deadlines with the client.
- Clients cannot assign work to editors.
- Inquiry data, client pricing, margins and internal notes are never visible to editors.

Inquiry statuses: proposed, awaiting approval (OPEN_QUESTIONS N).

## Editor registration and application _(2026-11-11; resolves question D)_

1. Visit EDITSTATION → register with email and password.
2. Verify email (required; decision R).
3. Complete the editor application: profile, portfolio links, skills/specialisations, experience,
   software, availability, typical turnaround, optional hardware, terms/privacy acceptance
   (KB §7.3 fields; collect only what is necessary).
4. Submit → pending verification.
5. Admin reviews; may request more information or a practical test.
6. Admin approves and activates, or rejects. Only an authorised, server-side admin action grants
   editor access.

**Admin application management:** view application · review portfolio · review skills and
experience · request additional information · record vetting notes · record practical test
results · approve and activate (with initial level and specialisations) · reject · suspend or revoke
access.

Applicant/editor states: decided 2026-11-11 (decision L; see WORKFLOWS §2).

## Brief types (all required from release 1)

1. **Fully instructed**: footage, script/sequence plan, detailed instructions, supplied music/sound,
   graphics/fonts/brand guidelines, export specs, deadline, compensation.
2. **Reference-based**: footage plus one or more references. Each reference: title, URL, optional
   file/excerpt, start/end timecodes or timestamp, what to observe, priority (essential/optional),
   category (pacing, transitions, colour, typography, storytelling, framing, sound design, motion
   graphics), access/permission notes. May require an editor interpretation before work.
3. **Creative-led**: outcome and audience, core message, brand/visual constraints, mandatory
   content, prohibited content, deliverables/specs, deadline, compensation.

Brief type may affect complexity but must not automatically set the rate.

## Admin dashboard

Overview · **Client inquiries** _(2026-11-11)_ · Projects · Editors & applications · Assignments ·
Negotiations · Submissions · Revisions · Payments · Basic analytics · Settings & audit history.

Capabilities: manage inquiries and convert confirmed ones into projects; create/edit/archive
projects; choose brief type; add instructions, assets, references; set proposed pay and deadline;
manage applications (above); invite/assign/reassign; review counteroffers; confirm agreed pay;
review submissions; request revisions or approve; track and mark payment status; view activity
history.

## Applicant area _(2026-11-11)_

Account · application form (draft → submit) · application status · respond to admin information
requests · practical test instructions/submission if requested. Nothing else.

## Editor dashboard (active editors only)

Profile · Eligible projects · Invitations · Active assignments · Brief & assets · Reference
library · Interpretation / brief confirmation · Submission history · Revision feedback · Earnings &
payment history.

Capabilities: update permitted profile fields; view only eligible projects and own assignments;
accept/decline/counteroffer; ask questions via the project's communication mechanism (KB §17.6);
confirm brief and pay; submit work and revisions; view own payments.

**Editor workspace (Phase 1 of the workspace expansion, 2026-11-17, uncommitted):** navigation is
grouped as Workspace (Dashboard, My projects, Opportunities), Production (Feedback & revisions),
Financials (Earnings) and Account (Profile, Notifications); the logo in the signed-in shell links
to the user's own dashboard (`/admin`, `/editor`, `/apply`), not the public site.

- `/editor/projects`: every project the editor holds an assignment on (offers included; plain
  opportunities stay on Opportunities). Filters map onto real states: awaiting acceptance (offer,
  counteroffer or accepted, not yet confirmed), active (confirmed, in progress, in review,
  revision requested), in progress, submitted/in review (one state: submitting sets the project
  `in_review`), revision requested, approved or completed, on hold, cancelled. Search by title,
  sort by last activity, deadline or title, 20 per page. Each row shows a short reference (first
  8 characters of the project id; there is no separate reference column), stage, deadline (the
  confirmed one once the brief is confirmed, otherwise the planned one marked "not confirmed"),
  last activity, the pending action and who owns it, latest submission and outcome, change-request
  count and the editor's own next pay milestone status (label only).
- `/editor/projects/[id]?tab=`: Overview (offer or assignment, terms, start checklist, extra pay
  offers, summary and deliverables), Brief (full brief once confirmed, references), Submissions,
  Feedback & revisions, Files (assets) and Activity (offers and replies without amounts,
  confirmation, brief confirmations, submissions, reviews and change-request steps). A link
  without `tab` opens Overview.
- `/editor/feedback`: the editor's change requests across projects (type, round, status, version,
  reason) filtered as open (requested or under discussion), acknowledged/in progress, resubmitted,
  resolved; each links to the project's Feedback tab.
- Dashboard: quick actions, offers (unchanged), active projects, confirmed deadlines (overdue in
  Asia/Colombo time), awaiting review, open change requests, recent submissions, outstanding own
  pay milestones and recent notifications.

All of it reads existing tables through the editor's RLS and `editor_list_payments`; no schema
change, no client data, client prices, billing or internal notes.

## Excluded from MVP

Client portal/accounts/dashboard · public marketplace · open bidding · automatic inquiry-to-project
conversion · automated matching · payment gateway · live collaborative editing · AI video editing ·
complex chat · automated tax/accounting · multi-editor teams on one project (unless the pilot
proves it necessary).

## Acceptance criteria

KB §16 is the MVP readiness checklist, plus _(2026-11-11)_: anonymous users can submit an inquiry
but read nothing; applicants cannot reach any editor-only resource; only admin actions activate,
suspend or revoke editor access.
