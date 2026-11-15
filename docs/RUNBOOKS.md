# Runbooks

Operational procedures for EDITSTATION (Phase 11). Items marked **TODO (owner)** need a decision
or a fact only the owner can supply; do not fill them in from guesses. Hosted operations (anything
touching a hosted Supabase project or Vercel) need owner approval every time.

As of 2026-11-15 there is **no hosted environment**: no Supabase project, no Vercel project, no
GitHub remote. Procedures below are written for local use now and list what changes once hosting
exists.

## 1. Backup and restore

### Local restore drill (tested)

`npm run db:restore-test` (script: `scripts/db-restore-test.mjs`) with local Supabase running:

1. `pg_dump` (custom format) of the local `postgres` database inside the `supabase_db_editstation`
   container.
2. `pg_restore --exit-on-error` into a scratch database `restore_check` in the same container.
3. Compares row counts of every table in `public`, `private` and `auth`, the applied migration
   list, function counts in `public`/`private`, and checks every restored `public` table has RLS.
4. Drops the scratch database and the dump. `--keep` keeps both for inspection
   (`docker exec -it supabase_db_editstation psql -U supabase_admin -d restore_check`).

Exit code 0 means the restore matched. If it reports that the source changed during the drill,
stop `npm run dev` and run it again. Last run: 2026-11-15, passed (63 tables, 32 migrations).

The script never links a project or connects to a hosted database.

### Hosted backups

- **TODO (owner):** Supabase plan and backup tier (daily backups vs point-in-time recovery),
  retention period, and who may trigger a restore.
- **TODO (owner):** where off-platform copies (if any) are kept and who holds access.
- Before launch, repeat the drill against a hosted backup restored into a separate, non-production
  project (owner-approved), and record the date here.
- Media is never stored in Postgres (links only): a database restore does not restore files. The
  storage provider's own retention applies (open question KB7).

## 2. Admin MFA reset (lost authenticator)

Admin access requires an `aal2` session (`private.is_admin()`); without the factor the admin sees
only `/mfa`.

1. Confirm the request out of band with the admin (in person or a known phone number). Never act on
   an email or chat message alone.
2. As `postgres` (local: `docker exec -it supabase_db_editstation psql -U postgres`; hosted: SQL
   editor, owner approval), find the factors:
   `select id, factor_type, status, created_at from auth.mfa_factors where user_id = (select id from auth.users where email = '<admin email>');`
3. Delete the lost factor: `delete from auth.mfa_factors where id = '<factor id>';`
   (Supabase's dashboard user view or the Auth admin API `mfa.deleteFactor` do the same.)
4. The admin signs in again; `/mfa` offers a new enrollment. Admin data stays hidden until they
   verify the new factor.
5. Record what was done and why in the incident log (section 5). Note: `activity_logs` does not
   record factor deletions; the record is manual.

If the account itself is compromised, revoke admin rights first (section 3b), then reset.

## 3. Revoking access

### 3a. Editor (suspend or revoke)

1. `/admin/applications/<application id>`: in the editor access form choose **Suspend**
   (reversible) or **Revoke** (permanent), with a reason. This calls `admin_set_editor_access` (audited in
   `activity_logs`).
2. Effect: access is checked on every request; the editor loses `/editor` on their next request.
   Their session cookie is not killed immediately (known issue in `CURRENT_STATUS.md`).
3. Live assignments are **not** closed automatically (WORKFLOWS §6). For each project where the
   admin project page shows a "Suspended"/"Access revoked" badge, decide per assignment: reassign,
   or keep it on hold. Pay consequences: open question F (not decided).
4. Work through the revoke checklist on the project page: folder shares outside the app
   (asset access grants) must be removed at the storage provider by hand, then marked revoked.

### 3b. Admin

There is no admin UI for this by design. As `postgres`:
`update public.admin_users set revoked_at = now(), note = '<reason>' where user_id = (select id from public.profiles where email = '<email>');`
Audited by `audit_admin_users`. The
person keeps their account and is routed like any other non-admin account. Granting is
`select private.grant_admin_by_email('<email>', '<note>');`.

## 4. Project cancellation, editor withdrawal, reassignment

Defined in `docs/WORKFLOWS.md` §3 and §6; summary of the as-built process:

- **Cancel a project:** admin project page, Status → Cancelled (allowed from draft, open,
  assigned, in progress). Every live assignment closes as `withdrawn` with a history row; every live
  access row is revoked. Folder shares stay on the revoke checklist until handled by hand.
- **Editor withdraws before confirmation:** the editor declines the offer on
  `/editor/projects/<id>`; the admin can also use **Withdraw offer**.
- **Editor withdraws after confirmation, or the studio replaces them:** admin uses **Reassign** on
  the project page with a reason. The assignment becomes `reassigned`, the project returns to
  `open`, that editor's access is revoked, and a new invite/offer can follow. History is kept.
- Payment consequences of any of these (kill fees, partial pay): open question F, **TODO (owner)**.
  Ended assignments put unpaid payments on hold automatically (Phase 9).

## 5. Incident response

For a suspected data exposure, compromised account, or leaked key.

1. **Contain.** Revoke the affected admin (3b) or editor (3a). For a leaked Supabase secret/service
   key or a leaked Vercel token: rotate it in the provider dashboard (owner approval), then update
   the hosted environment variables. The browser only ever holds the publishable key.
2. **Preserve evidence.** Do not delete rows. Export the relevant `activity_logs` range
   (`/admin/activity`, or SQL as `postgres`) and the hosted auth/API logs before they expire.
3. **Assess.** Which tables and which people were affected? RLS policies and the pgTAP suite
   (`npm run db:test`) describe what each identity can read.
4. **Fix and verify.** New migration with pgTAP tests for any database cause (never edit applied
   migrations); `npm run check`, `npm run db:test`, `npm run test:e2e`.
5. **Notify.** **TODO (owner):** who must be told (clients, editors, any authority) and within
   what time. This depends on the legal entity and applicable law (open questions KB1, P) and is
   not decided here.
6. **Record.** Date, what happened, who was affected, what was changed. **TODO (owner):** where the
   incident log lives.

## 6. Deploy checklist

Nothing is deployed yet. Before the first production deploy and before each later one:

- [ ] Branch reviewed (code-reviewer; db-security for anything under `supabase/`), owner approved.
- [ ] `npm run check`, `npm run build`, `npm run db:test`, `npm run test:e2e` green locally and in
      CI.
- [ ] `npm run db:advisors` shows no warnings.
- [ ] `npm run db:restore-test` passes; a recent hosted backup exists (section 1).
- [ ] New migrations reviewed; applied to hosted Supabase only with owner approval (`supabase db
push` is never run by an agent).
- [ ] Hosted env vars set in Vercel: `NEXT_PUBLIC_SUPABASE_URL`,
      `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` only in the browser bundle; no secret key in any
      `NEXT_PUBLIC_*` variable.
- [ ] Hosted Supabase: MFA (TOTP) enabled, email confirmations on, SMTP configured, site URL and
      redirect URLs set to the production domain. **TODO (owner):** production domain (KB2).
- [ ] Re-check the "permission denied for function" crash on the hosted Postgres image
      (`CURRENT_STATUS.md` known issues).
- [ ] Launch gates from `CURRENT_STATUS.md`: Turnstile (O), legal pages (KB1, KB8, P), real
      service list and budget ranges.
- [ ] After deploy: sign in as admin (MFA), open `/admin` and `/admin/activity`; submit a test
      inquiry and mark it spam.
- [ ] Rollback plan: redeploy the previous Vercel deployment; database changes roll forward with a
      new migration, never by editing an applied one.
