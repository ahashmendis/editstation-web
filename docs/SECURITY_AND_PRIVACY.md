# Security and Privacy

Derived from KB §7.3, §8.2, §11.3, §12.3 and the owner clarification of 2026-11-11. Not legal advice.

## Owner security requirements (2026-11-11)

1. Default-deny RLS. 2. Never rely on frontend visibility. 3. Pending applicants cannot access
   editor-only resources. 4. Only authorised admins approve/reject applications. 5. Only authorised
   admins change editor roles or activation status. 6. Editors cannot directly modify assignments,
   agreed compensation, payment status or admin review fields. 7. Internal client information is kept
   apart from editor-visible project information. 8. Secrets and service-role credentials stay
   server-side. 9. RLS tested as anonymous, pending applicant, approved editor A, approved editor B,
   admin. 10. Important admin actions are audit-logged.

The public registration flow must not weaken any of these.

## Threat model additions from public entry points

| Threat                                                                     | Mitigation                                                                                                                                                                                                    |
| -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Self-registered user tries to become editor/admin                          | No role in sign-up metadata is trusted; trigger always creates `access_status = 'none'`; `admin_users` and `access_status` are writable only through admin-only functions; pgTAP tests attempt the escalation |
| Applicant reads projects or other editors                                  | Every editor-facing policy requires `is_active_editor()`, not just "signed in"                                                                                                                                |
| Applicant edits their own application after submission, or sets its status | Column-level grants plus policies limit applicant edits to non-status fields while `draft` / `info_requested`; status changes only via functions                                                              |
| Inquiry form spam / bot sign-ups                                           | Captcha (Supabase Auth supports captcha on sign-up) and rate limits (question O); honeypot field                                                                                                              |
| Anonymous user reads inquiries                                             | `anon` has execute on `submit_client_inquiry()` only; no SELECT on any table                                                                                                                                  |
| Suspended editor keeps working                                             | Access helpers read the table on every query; optional forced sign-out                                                                                                                                        |
| Admin account takeover                                                     | TOTP MFA required for admins (decision A), enforced in admin policies and the admin gate via the session assurance level (`aal2`)                                                                             |
| Malicious links in inquiries/applications                                  | Store and display as plain text/escaped links; never fetch or embed them server-side                                                                                                                          |

## Access helpers (implemented in Phase 1)

`private.is_admin()` (admin row **and** `aal2` MFA session), `private.is_admin_account()` (routing
only, never for authorisation), `private.is_active_editor()`; `current_editor_id()` to follow when
needed. `security definer`, `stable`, `set search_path = ''`, in the non-exposed `private` schema,
called as `(select private.is_admin())` in policies so they run once per statement.

## Function placement rule (Phase 1 finding)

In the local Supabase Postgres image (17.6.1.106), a "permission denied for function" raised for
`anon`/`authenticated` crashes the database (supautils permission-hint bug). Therefore:

- Internal functions go in `private` (not reachable through the API).
- Every function in `public` must be executable by both `anon` and `authenticated` and enforce
  authorisation inside its body. A pgTAP guardrail (`000_rls_guardrail.test.sql`) enforces this.
- Tests check function privileges with `has_function_privilege`, never by calling a forbidden
  function as an API role.
- Re-check on hosted Supabase before launch.

## Admin bootstrap

`private.grant_admin_by_email(email, note)`: executable only by `postgres` (SQL editor or psql).
Audited. The first admin must then enrol TOTP before any admin data becomes visible.

## Access matrix (target; each cell becomes pgTAP tests)

| Data                               | Anonymous              | Applicant (own)                                                     | Active editor                                                                 | Admin                                |
| ---------------------------------- | ---------------------- | ------------------------------------------------------------------- | ----------------------------------------------------------------------------- | ------------------------------------ |
| Client inquiry                     | submit only (function) | —                                                                   | —                                                                             | full                                 |
| Own profile                        | —                      | read/update permitted fields                                        | read/update permitted fields                                                  | full                                 |
| Own application                    | —                      | read; edit while draft/info requested; submit/withdraw via function | read                                                                          | full; decide via function            |
| Vetting notes, assessments results | —                      | — (own test instructions only)                                      | —                                                                             | full                                 |
| `admin_users`, `access_status`     | —                      | read own status only                                                | read own status only                                                          | change via audited function          |
| Projects, briefs, references       | —                      | —                                                                   | only projects in `project_access` / assigned                                  | full                                 |
| Assets                             | —                      | —                                                                   | `opportunity` for accessible projects; `assigned` once confirmed (question B) | full                                 |
| `project_internal`, clients        | —                      | —                                                                   | —                                                                             | full                                 |
| Assignments, offers, confirmations | —                      | —                                                                   | own; write via functions                                                      | full                                 |
| Submissions, revisions             | —                      | —                                                                   | own; submit via function; no review fields                                    | full                                 |
| Payments, payout details           | —                      | —                                                                   | own (read); payout details own                                                | full; mark paid via function         |
| Activity logs                      | —                      | —                                                                   | —                                                                             | read only (no one can update/delete) |

`—` = no access. Editors B cannot see anything belonging to editor A.

## Access-control model (general)

- RLS enabled on **every** `public` table (pgTAP guardrail enforces this). Default deny.
- Editors' workflow writes go through Postgres functions that check the caller, current state and
  allowed transition. No direct UPDATE grants on `assignments`, `payments`, `submissions` review
  fields, `revision_requests`, `editor_applications.status` or `editor_profiles.access_status`.
- RLS filters rows, not columns: client data and pricing live in separate admin-only tables.
- `security definer` functions: fixed `search_path`, explicit caller checks, no dynamic SQL from input.
- Supabase's automatically exposed API: revoke default privileges from `anon` on new tables; grant
  only what each policy needs.

## Data handling

- Collect only operationally necessary data. Inquiries come from people without accounts, so the
  form must show a privacy notice and record which version they saw.
- No ID documents without a documented reason (KB §7.3).
- Bank details: not collected in the application; timing and fields per question E. Never store
  banking passwords, PINs or auth codes.
- Retention: unconverted inquiries and rejected applications need a retention period (question P).
- Secrets in environment variables. Public keys are not authorisation; RLS is.
- Asset links: no permanent public links to confidential footage; review access on assign,
  unassign, suspension and close (question K).
- Plan for: privacy notice, data-subject requests, incident response, vendor review (KB §12.3).
  Confirm PDPA obligations with local counsel.

## Operational

Rate limits and Supabase Auth protections on sign-up/sign-in/inquiry. Production auth emails via
custom SMTP on a verified domain. Backups and a **tested** restore before the pilot. Audit log for
sensitive actions.
