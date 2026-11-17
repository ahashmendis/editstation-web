# Editor workspace expansion: Phase 0 architecture and plan

**Status: Phase 0 (audit and plan) written 2026-11-17. Nothing is built, committed, pushed or deployed
for this expansion. Each phase needs the owner's approval before code, and hosted migrations need
explicit approval.** Source request: the owner's "Editor Workspace Expansion" brief. Where it
conflicts with the standing "push after every commit" rule, the brief wins for this work: no
commit, push, merge or deploy without explicit approval.

## 1. Current state (verified in the repo)

- **Editor routes:** `/editor` (dashboard: opportunities and "My projects" cards),
  `/editor/opportunities`, `/editor/earnings`, `/editor/profile`, `/editor/projects/[id]` (one long
  page: assignment or offer, summary, brief, references, assets, submissions, revision requests,
  pay). Navigation has four items. `/notifications` already exists (shared, in-app).
- **Data (reusable as is):** `projects` (has `deadline`), `assignments`, `brief_versions`,
  `brief_confirmations`, `project_terms` and stages, `payments`, `submissions`,
  `revision_requests`, `notifications` plus `private.notification_outbox` (email worker live),
  `project_assets` (links), `project_opportunities`, `activity_logs`, `editor_profiles`.
- **Submissions:** numbered per project (`version`), hold an **https link** and notes, a
  confirmed deadline and `is_late`, an admin outcome and written feedback. **No media is stored:
  links only** (rule KB7).
- **Revisions:** one `revision_requests` row per **round**, typed (editor correction, client
  revision, scope change, rejected-needs-discussion), with free-text `reason`, status flow
  requested, acknowledged, in progress, resubmitted, approved, and a unique open request per
  assignment. Round counting and allowance are enforced in SQL and must not be bypassed.
- **Feedback today:** the admin writes it. There is **no client input, no timecodes, no player**.
- **Notifications:** in-app list plus email outbox with a Brevo worker (daily admin summary,
  individual emails for editors). No preferences, no WhatsApp, no calendar, no support tickets, no
  AI. `PRODUCT_SPEC` lists AI video editing as out of scope; the AI workspace here is advisory only.

## 2. Reuse and proposed navigation

Keep every existing route. Add routes only where a page is a real destination; project detail
becomes tabs inside the existing `/editor/projects/[id]` (overview, brief, review, submissions,
feedback, files, activity), not new top-level routes.

| Group      | Items (route)                                                                                              |
| ---------- | ---------------------------------------------------------------------------------------------------------- |
| Workspace  | Dashboard (`/editor`, improved), My projects (`/editor/projects`, new list), Opportunities, Calendar       |
| Production | Feedback and revisions (`/editor/feedback`, new cross-project list)                                        |
| Financials | Earnings (existing) with Payment history (`/editor/earnings/history`)                                      |
| Account    | Profile (existing), Notification settings (`/editor/settings/notifications`), Connected apps, WhatsApp, AI |
| Help       | Help and support (`/editor/support`)                                                                       |

Phase 1 needs no schema change for My projects, the dashboard improvements and the project tabs: they
read existing tables through existing RLS.

## 3. Video review architecture (provider-independent)

Separate five concerns, each swappable:

1. **Review session and access:** `review_sessions` (project, submission/version, status, optional
   review deadline) and `review_links` (token **hash** only, expiry, revoked_at, created_by, use
   counters). The client opens `/review/<token>`; a server route validates the hash, expiry,
   revocation and rate limit, then reads **only through narrow `SECURITY DEFINER` functions that
   take the token** (no client account, no table grants to `anon`). The page exposes the approved
   display title, the video, version info, instructions, comments the admin marked client-visible,
   and a comment form. Nothing else.
2. **Video source:** a `video_source` per version: `{provider, url or embed id}`. The player is an
   adapter (direct file URL with `<video>`, or a provider embed API) so a provider can change
   without schema changes.
3. **Versions:** a review version **is a submission** (existing `submissions.version`); comments
   reference `submission_id`, are immutable once made, and never move between versions. Old
   versions stay readable by admins.
4. **Timecoded comments:** `review_comments` (submission_id, parent id, author kind client|admin|
   editor, `position_ms` integer, `fps` numerator and denominator copied from the version,
   body, status, visibility). Original client text is immutable (trigger); admin edits go in a
   separate `approved_instruction` field.
5. **Moderation and editor workflow:** every client comment starts `awaiting_admin`. The admin
   approves or rejects each item and writes the editor-facing instruction. **Classification stays
   per round, not per comment:** approved items are sent as one `revision_requests` round (existing
   type and allowance logic unchanged), with the items linked to it. This preserves the allowance
   rules; item-level classification would double count rounds.

Annotations (draw, rectangle, screenshots) are left as a nullable `annotation jsonb` column and not
built; attachments are out of scope until file handling is approved.

## 4. Database changes (conceptual, per phase)

- **Phase 1:** none, or read-only views and indexes.
- **Phase 2/3:** `review_sessions`, `review_links` (hashed), `review_comments`,
  `review_comment_actions` (audit), plus a `review_visit_log` (counts, no IPs stored raw), links to
  `submissions` and `revision_requests`. All writes through `public` functions (anon and
  authenticated executable, authorise in the body, ES errors only, `search_path ''`); the token
  functions authorise by hash, not by role. RLS on every table, default deny.
- **Phase 4:** `calendar_feed_tokens` (hashed, revocable) and a read function; no external OAuth.
- **Phase 5:** `editor_notification_preferences`, `whatsapp_consents` (timestamp, policy version),
  `message_delivery_log`, `support_tickets`, `support_messages`.
- **Phase 6:** `ai_usage_log` and a provider settings row, all disabled by default.

## 5. Security considerations

- The review-link visitor is a new principal: no auth user, authority is the token. pgTAP must
  cover anon, applicant, editor A, editor B, admin and a link visitor (valid, expired, revoked,
  wrong project).
- Editors see only comments the admin released; client text, internal notes and the original
  wording are never selectable by editors (column and policy level, plus pgTAP).
- Tokens: 256-bit random, stored as SHA-256, shown once at creation, constant-time compare, short
  default expiry, revoke at any time, per-token and per-IP rate limits (needs a store; see
  decisions).
- No private asset or storage URLs reach a client reviewer. Playback uses only the approved review
  video source.
- Calendar feeds carry titles and dates only, no client data; WhatsApp messages are fixed
  templates with no client names, links or amounts; AI never receives client data by default and
  never changes status, pay, allowance or messages.

## 6. External integrations and what each needs

| Item         | Needs                                                                                    | Cost / risk                               |
| ------------ | ---------------------------------------------------------------------------------------- | ----------------------------------------- |
| Review video | A provider decision (section 7, decision 1)                                              | Storage and bandwidth if hosted           |
| Calendar     | Private revocable ICS feed (standards-based); no Google/Microsoft OAuth                  | Free                                      |
| WhatsApp     | Meta WhatsApp Business account, verified business, approved templates, per-editor opt-in | Per-conversation fees; counsel on consent |
| AI           | Provider, budget, data-handling approval; consent screen                                 | Per-token cost; confidentiality           |

## 7. Owner decisions required (recommendation first)

1. **Review video source.** (a) Recommended for the first release: editors submit a link that the
   admin approves as the review video, played through a provider player (an unlisted or privacy
   restricted Vimeo or YouTube link, or a direct file URL), no hosting cost. Risk: unlisted is
   obscurity, not security; Drive and Dropbox previews cannot seek or report time. (b) Supabase
   Storage proxies (about 100 to 500 MB each): privacy and signed URLs, but storage and egress
   cost, and it relaxes "links only". (c) Dedicated host (Mux, Cloudflare Stream): best player and
   security, recurring cost. Nothing paid is chosen without approval.
2. **Classification per round, not per comment** (section 3.5). Recommended.
3. **Review link expiry default** (recommend 14 days, revocable) and whether a link may accept
   comments after the review deadline (recommend no).
4. **Rate limiting store** for token endpoints (recommend a small Postgres counter table, no new
   service).
5. **WhatsApp:** Meta business verification, template wording, who pays, and counsel review of
   consent text. Build foundations only until these exist.
6. **AI:** provider, monthly budget, and which fields may be sent. Build the interface and
   adapter, keep disabled.
7. **Support tickets** are admin-handled; confirm the response expectations you want to promise.

## 8. Phases

0. This document. 1. Workspace foundation: My projects, project tabs, Feedback and revisions list
   (from existing revision requests), dashboard, notification settings shell. 2. Review foundation:
   sessions, hashed links, player adapter, timecoded comments, markers, versions. 3. Admin moderation
   and the revision bridge, audit. 4. Calendar feed, payment history. 5. WhatsApp foundations,
   preferences, support. 6. AI workspace (disabled). 7. Final validation and report. Each phase:
   design check, TDD, db-security and code-reviewer review, `npm run check`, `db:test`, my own
   verification, then owner approval before commit and again before any hosted migration.

## 9. Conflicts and risks

- **Round model vs per-comment feedback:** handled by decision 2.
- **"Links only" vs hosted video:** decision 1; hosting would need a recorded exception.
- **Client link visitor vs "no client portal":** allowed by the brief if narrow; the page is
  read and comment only, no history across projects, no account.
- **Scope:** the brief is several months of work; phases 1 to 3 are the product, 4 to 6 are
  additive and can wait.
- **Token cost and review load:** each phase uses the full build, review and fix cycle.

## 10. Owner decisions recorded (2026-11-17)

- **Review video source:** Google Drive files play in EDITSTATION's own player (HTML video with
  range requests through the Drive API and a server-side API key), behind a provider-independent
  adapter so Vimeo, YouTube unlisted or a direct file can be added later. First release uses
  "Anyone with the link" files; a private service-account route is a later option. A short
  feasibility test with one real Drive file comes first in Phase 2. The owner creates the Google
  Cloud API key; it is stored only as a server secret.
- **Classification is per revision round, not per comment** (section 3.5).
- **Link expiry:** 14 days default, revocable; no comments after the review deadline.
- **WhatsApp and AI:** foundations only, switched off, until provider, budget, templates and
  data handling are decided.
- **Phase 1 approved to start** (local build only; commit, push and hosted changes each need the
  owner's explicit approval for this expansion).
