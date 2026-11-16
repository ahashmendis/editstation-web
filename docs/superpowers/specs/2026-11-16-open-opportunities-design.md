# Open opportunities: design (for owner approval, nothing built)

Date: 2026-11-16. Concept approved by the owner the same day (decisions log "B/C amended").
This document turns it into a buildable design and lists the calls that still need an answer.

## 1. What it is

An admin can publish a project as an **opportunity**. Active editors see a short list of open
opportunities (summary only) and can **register interest**, optionally proposing a rate. The admin
reviews the interested editors and **chooses one manually**. Choosing one creates the existing
invitation and negotiation (the same offer flow as today); every other interested editor sees
"Not selected". Nothing else about assignment, pay, terms, deposit gate or confirmation changes.

## 2. Goals, non-goals, anti-goals

- Goal: editors can discover work and signal interest without the admin inviting each one by hand.
- Non-goal: bidding, auctions, first-come-first-served, client-to-editor contact, any change to
  agreed-pay, terms or payment rules.
- Anti-goal: leaking client identity, client pricing, brief detail, files or links before an
  editor is chosen and confirmed. Editors who are not active never see opportunities.

## 3. What an editor sees (summary only, an allow-list)

Title (admin-written, neutral), service type, short deliverables summary, deadline, language or
format notes the admin chooses to expose, and the **editor pay the admin is offering, if the admin
chooses to show one**. Never: client or company name, inquiry text, client price or budget, assets,
links, reference files, notes. The admin writes the public summary separately from the project
brief, so nothing is exposed by accident (not a filtered copy of brief columns).

## 4. Data model (sketch)

- `project_opportunities` (one per published project): project id, summary fields above, optional
  shown pay amount + currency, status `open | closed | filled`, published_by/at, closed_at.
  Editor-readable by RLS only when the editor is active and status is `open` (or the editor has
  interest on it). Contains no client data (editor-visible table rule).
- `opportunity_interests`: opportunity id, editor id, optional proposed rate + currency, optional
  short note, status `interested | withdrawn | selected | not_selected`, timestamps. One live row
  per editor per opportunity. Append-style history; admin-only reads of all rows; an editor reads
  only their own row.
- All writes through `public` functions (anon + authenticated executable, authorise in body,
  ES-errors only): `admin_publish_opportunity`, `admin_close_opportunity`, `editor_list_opportunities`,
  `editor_register_interest`, `editor_withdraw_interest`, `admin_list_interests`,
  `admin_select_editor` (creates the existing assignment/invitation via the existing offer
  function, marks others `not_selected`, closes the opportunity). Locks follow the existing order
  (project, assignment, then the new tables). New activity-log events; notification kinds
  `opportunity_selected` (to the chosen editor, via the existing offer notification) and
  `opportunity_not_selected` (to the others); admin gets `interest_registered`.

## 5. Screens

- Editor: `/editor/opportunities` (list, empty and error states, register or withdraw interest,
  proposed-rate field optional, shows status Interested / Selected / Not selected). Works at 375px.
- Admin: "Publish as opportunity" card on `/admin/projects/[id]` (summary form, shown pay
  optional), interested-editors list with proposed rates, editor profile link, "Choose this
  editor" (opens the existing offer form prefilled), "Close opportunity".

## 6. Approaches considered

1. **Summary-only opportunities + manual choice (recommended, approved concept).** Keeps vetting,
   privacy and the existing offer flow; smallest new surface.
2. Open the existing project list to editors with column hiding: rejected, row-level security
   cannot hide columns and it risks exposing client data.
3. First-come-first-served claiming: rejected by the owner (acts like bidding, rewards speed).

## 7. Calls I need from you (my recommendation first)

1. **Does the editor see the offered pay?** Recommend: the admin chooses per opportunity (default
   hidden; if hidden the editor may propose a rate).
2. **Who can see it?** Recommend: all active editors; no level or specialisation filtering in the
   first version (later option).
3. **Limits.** Recommend: an editor has at most 10 live interests at once, and cannot register on
   a project they were previously not selected for or declined.
4. **Proposed rate is only a signal.** Recommend: it never sets pay; pay is still agreed through
   the offer flow and admin approval.
5. **Auto-close.** Recommend: an opportunity closes when an editor is chosen, when the admin
   closes it, or at an admin-set closing date (optional).
6. **Notifications.** Recommend: editors get a bell notification when selected or not selected;
   admins get one per new interest (batched in the activity feed, not email).
7. **Confidentiality reminder.** Recommend: a one-line notice on the page that the summary is
   confidential and may not be shared.
8. **Existing invitations stay.** Recommend: the admin can still invite a specific editor directly
   without publishing an opportunity.

## 8. Plan and verification

One branch `open-opportunities`. Steps: migrations (schema, functions, notification kinds) with
pgTAP as admin, editor A, editor B, pending applicant and anon (including: editors cannot read
other editors' interests; non-active editors see nothing; no client column can ever appear in the
editor projection); app screens; db-security and code-reviewer reviews; e2e for publish, interest,
select and not-selected; docs updated (WORKFLOWS, DATABASE_SCHEMA, SECURITY_AND_PRIVACY, CURRENT
STATUS, CHANGELOG). Local database only.
