# Development Roadmap

Vertical slices (KB §15.5). Validate database permissions before building lots of screens. The KB's
four-week plan is a target, not a guarantee; a pilot after Phase 8 is realistic, with Phase 9 run
manually at first.

| #   | Phase                                                        | Done when                                                    | Blocking questions |
| --- | ------------------------------------------------------------ | ------------------------------------------------------------ | ------------------ |
| 0   | Repo foundation, tooling, CI, docs                           | `npm run check` + build pass; local DB + guardrail test pass | none               |
| 1   | Auth, `profiles`, roles, RLS helpers, pgTAP identity harness | Role tests pass for all 5 identities                         | A, D               |
| 2   | Editor application & admin vetting                           | Apply → review → approve/level/decline                       | D, E               |
| 3   | Projects, 3 brief types, brief versions, deliverables        | All 3 types creatable; versions retained                     | J                  |
| 4   | Assets & references with stage visibility                    | References visible only to the right editor                  | B, K               |
| 5   | Project access, invitations, negotiation, rate approval      | Offer history; one active assignment                         | C                  |
| 6   | Interpretation & brief confirmation; in-progress gate        | Gate enforced in the DB                                      | none               |
| 7   | Submissions, review, revision classification                 | 3-round allowance correct; corrections/scope excluded        | F                  |
| 8   | Payments                                                     | Only admin marks paid; editors see own; audited              | G, I, KB §17.9     |
| 9   | Notifications, dashboards, pilot metrics, audit view         | KB §14 metrics computable                                    | KB §17.6, §17.10   |
| 10  | Hardening: e2e, security review, restore test, runbooks      | KB §16 acceptance criteria met                               | —                  |
