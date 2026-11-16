import { FileStack, HandCoins, ShieldCheck } from "lucide-react";

import { container, eyebrow, sectionLead, sectionTitle } from "@/features/landing/styles";

// Factual product-rule highlights in place of stat tiles (owner decision 8, 2026-11-16). Each is
// taken from docs/WORKFLOWS.md or docs/BUSINESS_RULES.md; no figures are invented.

const POINTS = [
  {
    icon: ShieldCheck,
    title: "Pay agreed before editing starts",
    body: "Work cannot start until the editor has accepted, the pay is agreed and approved, the brief is confirmed and the client deposit is verified.",
  },
  {
    icon: FileStack,
    title: "Every version and request recorded",
    body: "Submissions are never overwritten. Each version keeps its feedback, and every change request records its reason and whether it uses an included round.",
  },
  {
    icon: HandCoins,
    title: "Two-step payment milestones",
    body: "Client billing and editor pay are kept separate. Each runs in milestones agreed per project before production, and a payment is marked paid only after the transfer is verified.",
  },
];

export function Transparency() {
  return (
    <section aria-labelledby="transparency-title" className={`${container} py-20 lg:py-28`}>
      <div className="grid gap-12 lg:grid-cols-[minmax(0,5fr)_minmax(0,7fr)] lg:gap-16">
        <div>
          <p className={eyebrow}>Transparency</p>
          <h2 id="transparency-title" className={`${sectionTitle} mt-4`}>
            Agreed up front. Recorded all the way.
          </h2>
          <p className={`${sectionLead} mt-5 max-w-[40ch]`}>
            The same rules apply to every project, for clients and editors alike.
          </p>
        </div>
        <ul className="grid gap-4">
          {POINTS.map(({ icon: Icon, title, body }) => (
            <li key={title} className="bg-card flex gap-5 rounded-2xl border p-6 sm:p-7">
              <span className="bg-primary/10 text-brand-text grid size-11 shrink-0 place-items-center rounded-xl">
                <Icon aria-hidden className="size-5" />
              </span>
              <div className="grid gap-1.5">
                <h3 className="text-lg font-bold tracking-[-0.02em]">{title}</h3>
                <p className="text-muted-foreground font-light">{body}</p>
              </div>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
