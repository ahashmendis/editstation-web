import Link from "next/link";

import {
  container,
  ctaPrimary,
  ctaSecondary,
  ctaSize,
  eyebrow,
  sectionLead,
  sectionTitle,
} from "@/features/landing/styles";

// "For clients": what the client area actually does today (docs/superpowers/specs/2026-11-17-
// client-area-design.md). Every point below is built; nothing about video review, messaging or
// notifications is promised until it exists. The editor is never named or shown to clients.
const POINTS = [
  {
    title: "Start a project online",
    body: "Send a brief from your account and follow what happens to it. The studio reviews it and gets back to you.",
  },
  {
    title: "Follow every project",
    body: "See each project's status in plain language, with progress updates written by the studio.",
  },
  {
    title: "See what is due and what is paid",
    body: "Payment milestones show the amount, the due date and where each payment stands.",
  },
];

export function ClientsSection() {
  return (
    <section
      id="clients"
      aria-labelledby="clients-title"
      className={`${container} scroll-mt-20 py-20 lg:py-28`}
    >
      <div className="grid gap-12 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)] lg:gap-16">
        <div className="grid content-start gap-5">
          <p className={eyebrow}>For clients</p>
          <h2 id="clients-title" className={sectionTitle}>
            One contact. Every project in view.
          </h2>
          <p className={`${sectionLead} max-w-[48ch]`}>
            You deal only with the studio. We manage the editing, so you never have to chase an
            update.
          </p>
          <div className="flex flex-col gap-3 pt-2 min-[420px]:flex-row">
            <Link href="/inquire" className={`${ctaPrimary} ${ctaSize.lg}`}>
              Start a project
            </Link>
            <Link href="/client/sign-in" className={`${ctaSecondary} ${ctaSize.lg}`}>
              Client sign-in
            </Link>
          </div>
          <p className="text-muted-foreground max-w-[44ch] text-sm">
            Client accounts are created by the studio. Send a project first and we will set up your
            access.
          </p>
        </div>
        <ul className="grid gap-4">
          {POINTS.map((point) => (
            <li key={point.title} className="bg-secondary/70 grid gap-1.5 rounded-2xl border p-5">
              <h3 className="font-landing-sans text-lg font-bold tracking-[-0.02em]">
                {point.title}
              </h3>
              <p className="text-muted-foreground font-light">{point.body}</p>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
