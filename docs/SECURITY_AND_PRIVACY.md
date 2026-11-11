# Security and Privacy

Derived from KB §7.3, §8.2, §11.3, §12.3. Not legal advice.

## Access-control model

- RLS enabled on **every** `public` table (pgTAP guardrail enforces this). Default deny. `anon` gets
  no table access.
- Helper functions `is_admin()`, `is_approved_editor()`: `security definer`, `stable`,
  `set search_path = ''`, called as `(select is_admin())` in policies for per-statement caching.
- **Editors read:** own profile/payout details; projects present in `project_access` (and only while
  approved); `opportunity` assets for those projects; `assigned` assets only after their assignment
  is confirmed; own assignments, offers, confirmations, submissions, revisions, payments.
- **Editors write:** own permitted profile fields and application only. Every workflow write
  (accept, counter, confirm, submit) goes through a Postgres function that checks the caller,
  the current state, and the allowed transition. No direct UPDATE grants on `assignments`,
  `payments`, `submissions` review fields, or `revision_requests`.
- **Admin-only tables:** `project_internal`, `editor_vetting_notes`, `activity_logs` (read).
- RLS filters rows, not columns: client data and pricing live in separate admin-only tables.
- `security definer` functions: fixed `search_path`, explicit caller checks, no dynamic SQL from input.

## Testing requirement

Every policy/function change ships pgTAP tests as five identities: admin, approved editor A, approved
editor B, pending applicant, anon. Include negative tests (A cannot read B's payments, applicant
cannot read projects, editor cannot set `agreed_amount`).

## Data handling

- Collect only operationally necessary applicant data (KB §7.3). No ID documents without a
  documented reason.
- Bank details only when needed, strict access (OPEN_QUESTIONS E). Never store banking passwords,
  PINs or auth codes.
- Secrets in environment variables. Public keys are not authorisation; RLS is.
- Asset links: no permanent public links to confidential footage; review access on assign,
  unassign and close.
- Plan for: privacy notice, retention/deletion rules, data-subject requests, incident response,
  vendor review (KB §12.3). Confirm PDPA obligations with local counsel.

## Operational

Rate limits and Supabase Auth protections on sign-up/sign-in. Backups and a **tested** restore
before the pilot. Audit log for sensitive actions.
