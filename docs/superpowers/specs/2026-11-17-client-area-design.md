# Client area: design

**Status: approved by the owner 2026-11-17 with every recommended call (decisions log, "Client area").
Phase C1 is built first, locally only. Hosted migrations, hosted auth configuration, commits and
pushes each need the owner's explicit approval.**

## Goal and anti-goals

Goal: clients submit projects, monitor every project they have with the studio, see payments, and
message the studio. Anti-goals: the client never sees the assigned editor (name, email, profile,
picture), editor pay, internal notes, admin discussions, raw internal statuses, or asset links
meant for editors; clients never contact editors; no self-signup; no payment gateway; an inquiry is
still a lead and only an admin converts it.

## Accounts and sign-in

- New account kind **client**: an auth user linked to a `clients` row through `client_users`
  (user_id, client_id, created_by, revoked_at). Several users per client; only an admin creates or
  revokes them (admin screen on the client record: invite by email).
- Sign-in by an **emailed one-time code** (Supabase email OTP, `shouldCreateUser` false, so only
  invited emails can sign in). Needs a magic-link/OTP email template (branded, like the auth
  templates) pushed to hosted later with approval. Optional two-step verification is a later add.
- Routing: `homePathFor` sends a client user to `/client` before any editor logic (every account
  also has an `editor_profiles` row from the sign-up trigger with status none; that must never send
  a client to /apply). A client account is never an admin or an editor.

## Data and access rules

- Clients get **no table grants**. All reads and writes go through narrow `public` functions
  (anon + authenticated executable, authorise in the body that the caller is an active
  `client_users` member of the project's client, `search_path ''`, revoke from public, ES errors
  only) that return client-safe projections. This keeps editor and internal data out of client
  reach by construction (RLS is row-level, not column-level).
- Visibility of progress is **admin-curated**: new `client_project_updates` (project_id, body,
  created_by, created_at, published) written by admins; the client sees published ones plus a
  mapped status (Received, Planning, In production, Ready for your review, Revisions in progress,
  Completed, On hold, Cancelled) derived from the real project status by one pure mapping.
- Payments for the client: the project's `client_milestones` (kind, amount, currency, due date,
  invoice issued, received, verification status as a client-facing label) and the studio bank
  transfer details from an admin-editable setting that stays empty (and hidden) until the owner
  supplies them. Never editor pay, never margins, never adjustments or settlements.
- Submit a project: a client function creates a `client_inquiries` row linked to the client
  (lead only; existing admin conversion flow unchanged; spam and rate limiting as the public form).
- Messages (C2): `client_messages` per project between the client and the admin team only; admin
  replies; email notification through the existing worker (C4).
- Audit: invitation, revocation, sign-ins that matter, published updates and submissions go
  through `activity_logs` with ids and field names only.

## Phases

- **C1 (now):** accounts, invitation and revocation by admin, routing, `/client` (projects list,
  project page with status, updates, deliverables summary, milestones and payment status),
  admin screens (invite/revoke client users, write and publish updates, bank details setting),
  full pgTAP matrix, unit tests, e2e.
- **C2:** [x] submit-a-project form (C2a, built 2026-11-18, pending review: `/client/projects/new`,
  `/client/requests`, `client_submit_project`, `client_list_requests`); [ ] messages. **C3:** client use of the video review (shared with
  Editor Workspace Phase 2). **C4:** client emails; WhatsApp later.

## Tests (C1)

pgTAP as: anon, applicant, editor A, editor B, client user of client X, client user of client Y,
revoked client user, admin (with and without MFA). Prove: a client sees only their client's
projects; cannot read editor, assignment, payment (editor), note, offer or opportunity data by any
function or table; revoked users lose access at once; the client projection never contains an
editor identifier; an invited-only sign-in cannot create new users. Browser: invite, sign in by
code (Mailpit), see projects and payments, isolation between two clients, 375px.

## Owner decisions still open

Studio bank details (to be supplied), client terms and privacy notice (counsel), the OTP email
wording, and how long a client may stay signed in.
