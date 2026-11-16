# Owner decision questions (2026-11-16)

Prepared from `docs/OPEN_QUESTIONS.md`. Answer in chat; each answer is then recorded in the
decisions log there. **Nothing here is decided.** A recommendation is only a suggestion, and
"legal" items need counsel, not a guess. Suggested order is the launch-blocking order.

## 1. KB2: final brand, domain, trademark

- Is "EditStation" the final public name?
- Which domain do you want (and is it registered)? Which sender address for auth emails?
- Have the trademark checks in the knowledge base (section 2.2) been run in Sri Lanka and in any
  market you will sell to?
- Recommendation: keep building as EditStation; run the checks and register the domain before
  launch. Rebranding later is costly. Blocks: public launch, production email, Turnstile setup.

## 2. KB3: services and deliverables at launch

- Which editing services do you launch with (for example short-form reels, YouTube long-form,
  ads, corporate, wedding)? For each: typical deliverables (aspect ratios, lengths, formats).
- Recommendation: give me the initial list; it lives in an admin-managed list so it can change
  without code. Blocks: seed content for the inquiry form.

## 3. KB4: client price ranges and editor pay ranges

- Do you want guide ranges per service (client side and editor side), or is every price quoted
  per project? If ranges, give the figures; I will not invent any.
- Recommendation: quote per project for the pilot, no published ranges. Blocks: the pilot.

## 4. KB5: turnaround and late delivery

- Standard turnaround per service, how extensions are agreed, and what happens when an editor is
  late (flag only, reassign, pay impact?).
- Recommendation: the app stores deadlines and flags late submissions; no automatic penalties.
  Blocks: policy before the pilot.

## 5. KB8: editor contract and portfolio permission

- Who drafts the editor terms (confidentiality, ownership of work, non-circumvention, portfolio
  use)? Do editors need to sign before applying or only before assignment?
- Recommendation: counsel drafts; acceptance (version + timestamp) is stored at application.
  Development uses a placeholder. Blocks: public launch of registration.

## 6. P: data retention and privacy notice

- How long are unconverted inquiries, rejected applications and withdrawn accounts kept? Who
  drafts the privacy notice? Is it acceptable that audit entries keep user ids after an account
  deletion (actor removed), or must they be scrubbed further?
- This needs counsel (Sri Lankan PDPA). Recommendation: no period from me; I can add privacy
  notice version stored per record and a scheduled deletion job once you choose. Blocks: launch.

## 7. KB1: legal entity / data controller

- Which legal entity is the data controller and the counterparty to editor terms (Lenscape
  Studios, registered as what, where)? Counsel decision. Blocks: privacy notice, editor terms.

## 8. G: practical tests

- Are practical tests paid? If paid, tracked in EditStation (payment type "assessment", no
  project) or outside?
- Recommendation: track tests in the app; record paid ones as assessment payments.

## 9. W: re-application after withdrawal

- Current behaviour (not a decision): a withdrawn applicant must ask an admin to reopen before
  reapplying, same as rejection. Confirm or change. Recommendation: keep it. Blocks: nothing.

## 10. A2: narrower "mark paid" permission

- Wait until there is a second admin. Not needed now.

## Also needed from you (not in the log yet)

- Landing page: any copy changes, and permission confirmation for each client logo shown.
- Hosted setup go-ahead (Supabase project, Vercel, email sender), each needs your approval.
- Counsel's PDPA review before the payout-details switch is ever turned on (decision E).
