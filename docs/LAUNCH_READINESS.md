# Launch readiness (2026-11-17)

Prepared from the repository, docs, tests and CI as of `main` at `12c4d84` (CI green). Nothing is
deployed. This report records the state, it does not decide anything for the owner, and it is not
legal advice or a compliance claim. Blocker codes: **P** = blocks the internal pilot, **L** =
blocks the limited public launch, **F** = blocks the full production launch. Who: **Owner**,
**Claude** (the assistant, local work only), **Counsel**, **Provider** (Supabase, Vercel, email
and domain providers, with the owner's approval).

"Built" means implemented and tested on the local stack (pgTAP, unit tests, local Playwright).
A hosted Supabase project and Vercel deployment were created on 2026-11-17 (first admin with MFA
works); the hosted smoke test, backups, email sender and everything else below remain open, and
nothing here is "production-ready" yet.

## 0. Three milestones

| Milestone                  | What it is                                                                                                                                         | Reaches it when                                                                                                                                         |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Internal pilot**         | Controlled real projects, a small group of vetted editors invited by the admin, admin enters clients and briefs by hand, no public forms promoted. | Every item marked **P** below is done: a hosted environment, working auth email, hosted backup proof, a basic editor agreement and privacy handling.    |
| **Limited public launch**  | Public client inquiry form and editor applications open to anyone, with the real domain.                                                           | Every **P** and **L** item is done: legal pages, Turnstile, domain and email, trademark clearance, retention rules, an independent security assessment. |
| **Full production launch** | A reliable public service: monitoring, tested restore, scheduled timed rules, notifications by email, incident handling, reviewed payout data.     | Every **P**, **L** and **F** item is done and has been exercised on the hosted stack.                                                                   |

## 1. Owner decisions still required

| Item                                      | Status                                                           | Outstanding work                                                                                              | Blocks                        | Who                  | Depends on                 |
| ----------------------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- | ----------------------------- | -------------------- | -------------------------- |
| KB1 legal entity / data controller        | Open, no recommendation                                          | Say which registered entity operates EDITSTATION and is the counterparty; names the controller in the notice  | L                             | Owner, Counsel       | Company registration facts |
| KB8 editor contract, portfolio permission | Open; app stores acceptance version + time against a placeholder | Counsel drafts terms (confidentiality, ownership, non-circumvention, portfolio use); owner approves           | P (basic agreement), L (full) | Counsel, Owner       | KB1                        |
| P retention periods and privacy notice    | Technical direction adopted 2026-11-17; periods and text pending | Counsel sets periods and drafts the notice; then a deletion job is built                                      | L                             | Counsel, then Claude | KB1                        |
| KB3 launch service list                   | Structure adopted (`service_types`); list is placeholder         | Owner lists services and deliverables per service                                                             | L                             | Owner                | —                          |
| KB4 prices                                | Adopted: quote per project; no ranges                            | Nothing to build. Owner supplies figures only if guide ranges are wanted                                      | none                          | Owner                | —                          |
| KB5 turnaround policy                     | Flags adopted; numbers and late consequences are owner policy    | Owner states standard turnaround, extension handling, what happens when late (written in client/editor terms) | P (a short written policy)    | Owner                | KB8                        |
| G practical tests paid or not             | Direction adopted; whether tests are paid is the owner's call    | Owner states yes/no; if yes, assessment-type payments are built later                                         | none                          | Owner, then Claude   | —                          |
| Open-opportunity and payout calls         | Approved 2026-11-16                                              | None                                                                                                          | none                          | —                    | —                          |
| A2 second admin permission                | Adopted: defer                                                   | Revisit when a second admin exists                                                                            | F (bus factor)                | Owner                | —                          |
| Pilot editors and projects                | Not chosen                                                       | Owner picks pilot editors and 1-3 first projects                                                              | P                             | Owner                | Hosting                    |

## 2. Legal and compliance (needs Counsel; nothing below is a compliance claim)

| Item                                 | Status                                                                                       | Outstanding work                                                                                       | Blocks           | Who             | Depends on |
| ------------------------------------ | -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | ---------------- | --------------- | ---------- |
| Sri Lankan PDPA assessment           | Not started; the KB flags it                                                                 | Counsel confirms obligations for inquiry, applicant, editor and payout data, controller duties, rights | L                | Counsel         | KB1        |
| Privacy notice                       | Placeholder page `/legal/privacy` with a version constant                                    | Counsel text, then replace the placeholder; the app already stores the version accepted                | L                | Counsel, Claude | KB1, P     |
| Editor terms                         | Placeholder `/legal/editor-terms`; acceptance stored                                         | Counsel text; version bump handling already exists                                                     | P (agreement), L | Counsel, Claude | KB8        |
| Client terms / quotation terms       | Revision, payment and cancellation terms are recorded per project (12A)                      | Counsel reviews the wording clients receive; the app does not generate client contracts                | P                | Counsel, Owner  | KB1        |
| Payout (bank) details                | Built **locked**; no bank data can be stored; interim "verified outside the app" attestation | Counsel confirms PDPA handling and encryption expectations before the switch is ever turned on         | F                | Counsel, Owner  | PDPA       |
| Incident notification duty           | Runbook step has a TODO                                                                      | Counsel states who must be told and when                                                               | L                | Counsel, Owner  | KB1        |
| Client logos and work shown publicly | Logos and client names are shown on the landing page                                         | Owner confirms permission from each client (see section 3)                                             | L                | Owner           | —          |
| Cookies / analytics notice           | None needed: no analytics or marketing cookies today                                         | Revisit only if analytics is added                                                                     | none             | Owner           | —          |

## 3. Brand, domain and website

| Item                                | Status                                                                                 | Outstanding work                                                                                       | Blocks                                              | Who                          | Depends on |
| ----------------------------------- | -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | --------------------------------------------------- | ---------------------------- | ---------- |
| Name and domain choice              | Recorded 2026-11-17: EDITSTATION, **editstation.work** (promo price EUR 2.71/yr shown) | Owner registers it (not done; no purchase, DNS or hosting configured by Claude). Confirm renewal price | P (a URL is needed; a temporary one is possible), L | Owner, Provider              | —          |
| Trademark clearance                 | Not done                                                                               | Run the KB section 2.2 checks (counsel or a search service)                                            | L                                                   | Owner, Counsel               | —          |
| Sender domain for auth/notice email | Local mail only (Mailpit)                                                              | Custom SMTP (e.g. Resend) with a verified sender on the domain                                         | P (sign-up email confirmation needs it)             | Owner, Provider, then Claude | Domain     |
| Crawler settings                    | `robots: noindex` in `src/app/layout.tsx` on purpose                                   | Flip to indexable only at public launch; add `robots.txt` and sitemap                                  | L                                                   | Claude                       | Domain     |
| Landing page                        | Built and merged (light, hero, platform, process, clients strip, reels strip)          | Copy review by the owner; permissions below                                                            | L                                                   | Owner, Claude                | —          |
| Real services copy                  | Placeholder list                                                                       | See KB3                                                                                                | L                                                   | Owner                        | KB3        |

**Landing page items that need the owner's separate permission (none assumed):**

1. Client logos: confirm each client allows its logo on the public site (10 shown; five other
   files in the Logo folder were skipped as own or duplicate marks).
2. Client names in the reel titles ("Great Ryrie Café", "Hydrant Food Hall" come from the
   Growthscape site as written there): confirm they may appear.
3. The six reel thumbnails were copied from growthscape.tech with the owner's earlier approval
   (own company): confirm that stays acceptable; they link out to Instagram.
4. Google Drive videos: **not used.** Downloading any needs the owner's explicit permission (file
   names and sizes first) and per-file share links.
5. Testimonials: none shown. Add only real quotes with written permission.
6. Heading "Brands we have worked with" and the hero wording are the assistant's draft copy.

## 4. Hosting and infrastructure (none exists yet; every step needs owner approval)

| Item                                                    | Status                                                                            | Outstanding work                                                                                      | Blocks                                | Who             | Depends on    |
| ------------------------------------------------------- | --------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------- | --------------- | ------------- |
| Hosted Supabase project                                 | Created 2026-11-17; 55 migrations applied                                         | Create project; choose a plan with backups; region; apply migrations (owner approval each time)       | P                                     | Owner, Provider | —             |
| Vercel project                                          | Created and deployed 2026-11-17 (CLI)                                             | Create, set `NEXT_PUBLIC_*` vars only, production branch rules, domain                                | P                                     | Owner, Provider | Domain        |
| Auth configuration                                      | Pushed 2026-11-17 (no templates)                                                  | TOTP MFA on, email confirmations on, site URL and redirects set, password policy, auth rate limits    | P                                     | Owner, Claude   | Hosting, SMTP |
| Admin account and MFA enrolment                         | Done on hosted 2026-11-17                                                         | Create the first admin on hosted, enrol TOTP, store recovery per runbook                              | P                                     | Owner           | Hosting       |
| Hosted Postgres "permission denied" crash re-check (S4) | Mitigated by a pgTAP guardrail locally                                            | Re-check on the hosted image                                                                          | P                                     | Claude          | Hosting       |
| Timed rules schedule                                    | `private.apply_timed_rules` runs when admin screens load; `pg_cron` not scheduled | Schedule `pg_cron` on hosted (owner approval)                                                         | F                                     | Claude, Owner   | Hosting       |
| Email notifications                                     | In-app bell only; email "queued" in design (KB10)                                 | Build and send email notifications via the SMTP provider                                              | F                                     | Claude          | SMTP          |
| Monitoring, alerts, error tracking                      | None                                                                              | Choose tooling (none chosen), uptime check, error alerts                                              | F                                     | Owner, Claude   | Hosting       |
| Backups and PITR                                        | Local dump/restore drill passes                                                   | Confirm hosted backup tier; run a hosted restore test; define retention (matters for bank data later) | P (backup exists), F (restore proven) | Owner, Claude   | Hosting       |
| CI                                                      | Green (app, pgTAP, e2e) on every push                                             | Keep green; add a deploy workflow only with owner approval                                            | none                                  | —               | —             |
| Rollback                                                | Written (redeploy previous Vercel build; migrations roll forward)                 | Rehearse once after the first deploy                                                                  | F                                     | Claude          | Hosting       |
| Dependency advisories                                   | 7 moderate, dev-only lint tooling                                                 | Watch; do not force-fix                                                                               | none                                  | Claude          | —             |

## 5. Security and privacy

| Item                                                 | Status                                                                                                     | Outstanding work                                                          | Blocks                           | Who             | Depends on |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- | -------------------------------- | --------------- | ---------- |
| RLS, function authorisation, MFA for admin           | Built; every table has RLS; every `public` function authorises in its body; pgTAP guardrails (2,297 tests) | Keep tests current                                                        | —                                | Claude          | —          |
| Turnstile on `/inquire` (S5, decision O)             | Honeypot and rate limit only                                                                               | Add Turnstile (needs a Cloudflare key and the domain)                     | L                                | Claude, Owner   | Domain     |
| Independent security assessment                      | Not started; owner will run it with tools they provide; S1-S10 recorded as scope                           | Owner runs it; fix confirmed findings                                     | L (initial), F (findings closed) | Owner, Claude   | Hosting    |
| S1 PUBLIC execute on some Phase 1-3 functions        | Known, low-medium                                                                                          | Owner-approved migration, carefully tested (policies use these helpers)   | L                                | Claude, Owner   | —          |
| S3 script CSP (nonces)                               | Only `frame-ancestors` set                                                                                 | Add a script CSP; needs care with `cacheComponents`                       | F                                | Claude          | —          |
| S2 session stays until next request after suspension | Accepted                                                                                                   | Revisit after assessment                                                  | none                             | —               | —          |
| S9 asset links are client-owned                      | Process controls built (verification, reports, removal checklist)                                          | Train the admin on the checklist                                          | P                                | Owner           | —          |
| S10 payout data                                      | Locked; no rows; no field-level encryption                                                                 | Counsel review; decide encryption before enabling; restrict backup access | F                                | Counsel, Claude | PDPA       |
| Secrets handling                                     | Env files blocked from agents; service key used only by local e2e                                          | Set hosted secrets in the providers; rotate procedure exists              | P                                | Owner           | Hosting    |

## 6. Testing and verification

| Item                           | Status                                                                                                                                     | Outstanding work                                                                                       | Blocks | Who           |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------ | ------ | ------------- |
| Database tests                 | 2,297 pgTAP tests pass locally and in CI                                                                                                   | One date-boundary test bug was fixed 2026-11-17; keep tests time-independent                           | —      | Claude        |
| Unit tests and `npm run check` | Pass                                                                                                                                       | —                                                                                                      | —      | Claude        |
| Browser e2e                    | 30 tests; last full local run 27 passed, 3 flaky passing on retry, 0 failed; billing test failed in earlier parallel runs and passes alone | Cover offer, submission, review and payment screens; reduce flakiness                                  | F      | Claude        |
| Two-session race tests         | Not done; locks are tested one step at a time only                                                                                         | Real concurrent tests for selection, payout switch, payments                                           | F      | Claude        |
| Hosted smoke test              | Never run                                                                                                                                  | After first deploy: sign in as admin (MFA), inquiry, spam mark, applicant flow                         | P      | Claude, Owner |
| Real-workflow rehearsal        | Not done                                                                                                                                   | Walk one project end to end with test data on hosted, including deposit, milestones and a cancellation | P      | Claude, Owner |
| Light theme on all screens     | Checked on main signed-in screens and public pages                                                                                         | Check admin pages not yet viewed (inquiries, applications, access review, activity, clients)           | L      | Claude        |
| Accessibility and mobile       | Designed for 375px and keyboard use; no formal audit                                                                                       | Run an accessibility pass before public launch                                                         | L      | Claude        |
| Performance                    | Not measured against a target                                                                                                              | Lighthouse and basic load check on the landing page and key forms                                      | L      | Claude        |

## 7. Operational readiness

| Item                                 | Status                                                                                                 | Outstanding work                                                   | Blocks | Who             |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------ | ------ | --------------- |
| Runbooks                             | `docs/RUNBOOKS.md` covers backup, MFA reset, incidents, cancellation, deploy checklist, payouts        | TODOs: incident log location, who is notified (needs counsel)      | P      | Owner, Counsel  |
| Payout process (no bank data in app) | Interim: verify the editor's account by phone, record "verified outside the app", pay by bank transfer | Owner agrees the routine; admin trained                            | P      | Owner           |
| Client billing process               | Deposit/balance milestones recorded in the app; invoices and transfers are manual                      | Owner defines invoice templates and the bank account clients pay   | P      | Owner           |
| Support and contact                  | None defined                                                                                           | A support address, response expectations, who answers inquiries    | L      | Owner           |
| Admin training and bus factor        | One admin                                                                                              | Document admin daily routine; second admin before full launch (A2) | F      | Owner           |
| Data requests (access, deletion)     | Account deletion works and anonymises audit actors; no request procedure                               | Counsel defines the procedure; Claude can build tooling            | L      | Counsel, Claude |
| Pilot success criteria               | Not defined                                                                                            | Owner defines what the pilot must show before opening up           | P      | Owner           |

## 8. What genuinely blocks each milestone

**Internal pilot (small group, controlled):**

1. ~~A hosted Supabase project and a Vercel deployment~~ Done 2026-11-17 (project
   `jatxlruwgopzoetqegmo`, https://editstation.vercel.app). Still to do: hosted smoke test, GitHub
   auto-deploy, confirm the Vercel plan allows this use.
2. A way to send auth emails (SMTP) so editors can confirm their email; this needs a sender domain
   or at least a provider account.
3. ~~First admin with MFA on hosted~~ Done 2026-11-17. Still to do: a hosted backup tier and a
   restore drill.
4. A basic written agreement with pilot editors and handling of their data, with counsel input.
5. The routine for paying editors and invoicing clients (process, not code), a short turnaround
   policy, and a hosted smoke test.

**Limited public launch (adds):** domain registered and verified for email; Turnstile; real legal
pages (privacy notice, editor terms, client terms) from counsel; KB1 entity; retention rules;
trademark clearance; the service list; an independent security assessment and the S1 fix; the
`noindex` flip; support contact.

**Full production launch (adds):** monitoring and alerts, a hosted restore test, scheduled timed
rules, email notifications, script CSP, closed assessment findings, extended browser and race
tests, incident procedure, a second admin, and a counsel-reviewed decision on payout data.

## 9. Next actions in priority order

1. **Owner:** register editstation.work (or confirm another), confirm the real price, and tell me
   when it is done. Nothing else on the web side can finish without it.
2. **Owner, with Counsel:** answer KB1 (entity), start the PDPA review, and commission the editor
   terms and privacy notice. These take the longest.
3. **Owner:** approve creating the hosted Supabase and Vercel projects (a step-by-step checklist
   is in `docs/RUNBOOKS.md` section 6); then I run the hosted configuration and smoke test.
4. **Owner:** supply the launch service list, the pilot editors and first projects, and your
   turnaround and late-delivery policy.
5. **Claude, after 1 and 3:** add Turnstile, set up SMTP-based email, schedule the timed rules,
   and build email notifications; then you run the independent security assessment.
