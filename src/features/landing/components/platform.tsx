import type { ReactNode } from "react";

import {
  AdminProjectPanel,
  EarningsPanel,
  EditorWorkspacePanel,
  ReviewPanel,
} from "@/features/landing/components/dashboard-panels";
import { container, eyebrow, sectionLead, sectionTitle } from "@/features/landing/styles";

// "The platform": four feature groups, each beside the screen it describes. Copy comes from
// docs/WORKFLOWS.md and docs/BUSINESS_RULES.md; the graphics hold fictional data only.

const FEATURES: { title: string; body: string; panel: ReactNode }[] = [
  {
    title: "Briefs, references and agreed terms",
    body: "Every project starts from a versioned brief with its deliverables, references and footage links. The revision policy, pay milestones and cancellation schedule are agreed per project and recorded before work begins.",
    panel: <AdminProjectPanel />,
  },
  {
    title: "Offers and agreed pay",
    body: "Editors are offered the work, never asked to bid. They accept, decline or counter, and the editor confirms the brief, deadline and pay before anything starts.",
    panel: <EditorWorkspacePanel />,
  },
  {
    title: "Versions, requests and rounds",
    body: "Every submission is kept as its own version with its feedback. Each request is classified as an editor correction, a client revision or a scope change, so corrections never use up a round.",
    panel: <ReviewPanel />,
  },
  {
    title: "Milestones and notifications",
    body: "Editors see the status of each pay milestone and get notified of new offers and decisions. Client prices and billing stay with the studio.",
    panel: <EarningsPanel />,
  },
];

export function Platform() {
  return (
    <section
      id="platform"
      aria-labelledby="platform-title"
      className={`${container} scroll-mt-20 py-20 lg:py-28`}
    >
      <div className="max-w-2xl">
        <p className={eyebrow}>The platform</p>
        <h2 id="platform-title" className={`${sectionTitle} mt-4`}>
          One place for every brief, version and payment.
        </h2>
        <p className={`${sectionLead} mt-5 max-w-[52ch]`}>
          The studio, its editors and the work all run through EditStation, so nothing depends on a
          lost message or a spreadsheet.
        </p>
      </div>

      <div className="mt-14 grid gap-6 lg:grid-cols-2 lg:gap-8">
        {FEATURES.map((f) => (
          <figure
            key={f.title}
            className="bg-secondary/70 grid content-start gap-6 rounded-3xl border p-5 sm:p-7"
          >
            <figcaption className="grid gap-2">
              <h3 className="font-landing-sans text-lg font-bold tracking-[-0.02em]">{f.title}</h3>
              <p className="text-muted-foreground font-light">{f.body}</p>
            </figcaption>
            {f.panel}
          </figure>
        ))}
      </div>
    </section>
  );
}
