import { container, eyebrow, sectionLead, sectionTitle } from "@/features/landing/styles";

// Brief, Match, Edit, Review, Deliver: the project workflow from docs/WORKFLOWS.md (sections 1,
// 3 and 3a) in plain words. Revision rounds are set per project (decision F), so no number is
// promised here.

const STEPS = [
  {
    title: "Brief",
    body: "Send the project through the inquiry form, no account needed. We agree scope, deadline and price with you, then build a versioned brief from your references.",
    tags: ["Inquiry form", "Scope agreed", "References"],
  },
  {
    title: "Match",
    body: "We offer the project to a verified editor whose experience fits. Nobody bids: the editor accepts, declines or counters, and the pay is approved before assignment.",
    tags: ["Verified editors", "No bidding", "Agreed pay"],
  },
  {
    title: "Edit",
    body: "The editor confirms the brief, deliverables, deadline and pay. Editing starts once the deposit is verified, working from the footage links you share.",
    tags: ["Brief confirmed", "Deposit verified"],
  },
  {
    title: "Review",
    body: "Each version is reviewed against the brief. Requests follow the revision policy agreed for your project; corrections to the editor's own mistakes are never charged.",
    tags: ["Every version kept", "Revision policy per project"],
  },
  {
    title: "Deliver",
    body: "Once approved, the final files are delivered and the project is completed. The balance falls due under the terms agreed before production.",
    tags: ["Final approval", "Agreed terms"],
  },
];

export function Process() {
  return (
    <section
      id="process"
      aria-labelledby="process-title"
      className="bg-secondary/60 scroll-mt-16 border-y py-20 lg:py-28"
    >
      <div className={container}>
        <div className="max-w-2xl">
          <p className={eyebrow}>Process</p>
          <h2 id="process-title" className={`${sectionTitle} mt-4`}>
            From brief to delivery, in five steps.
          </h2>
          <p className={`${sectionLead} mt-5 max-w-[48ch]`}>
            Every project follows the same path, managed by the studio from the first message to the
            final files.
          </p>
        </div>

        <ol className="mt-14 grid gap-4 md:grid-cols-2 lg:grid-cols-5 lg:gap-3">
          {STEPS.map((step, i) => (
            <li
              key={step.title}
              className="bg-card grid content-start gap-4 rounded-2xl border p-6 md:last:col-span-2 lg:p-5 lg:last:col-span-1"
            >
              <span className="font-landing-serif text-brand-text text-[2rem] leading-none font-medium">
                {String(i + 1).padStart(2, "0")}
              </span>
              <h3 className="text-lg font-bold tracking-[-0.02em]">{step.title}</h3>
              <p className="text-muted-foreground text-[0.9375rem] font-light">{step.body}</p>
              <ul aria-label={`${step.title} highlights`} className="flex flex-wrap gap-1.5">
                {step.tags.map((t) => (
                  <li
                    key={t}
                    className="font-landing-ui bg-secondary text-secondary-foreground rounded-full px-2.5 py-1 text-[0.6875rem] font-bold"
                  >
                    {t}
                  </li>
                ))}
              </ul>
            </li>
          ))}
        </ol>
      </div>
    </section>
  );
}
