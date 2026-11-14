import type { CSSProperties } from "react";
import Link from "next/link";

import { PublicPage } from "@/components/site-chrome";
import { buttonVariants } from "@/components/ui/button";
import { ProjectTimeline } from "@/features/landing/components/project-timeline";
import { ServiceFormats } from "@/features/landing/components/service-formats";
import { StepList } from "@/features/landing/components/step-list";

// Public home. Copy describes only how the process works (docs/WORKFLOWS.md,
// docs/BUSINESS_RULES.md): no clients, figures, prices or turnaround promises. The positioning
// line is the working suggestion from KB §2.1; the brand name is pending clearance (KB2) and the
// service list is a placeholder (KB §7.1, §17.3). CTA labels match the header so each intent
// has exactly one name: "Send a project" and "Join as an editor".

const cta = "h-11 px-5 text-base";
const ctaOutline = `${cta} border-foreground/20`;

const CLIENT_STEPS = [
  {
    title: "Tell us about the project",
    body: "Use the inquiry form. No account needed: describe the work, the deliverables and your deadline.",
  },
  {
    title: "Lenscape reviews and quotes",
    body: "We get back to you to agree scope, timing and price before anything is booked.",
  },
  {
    title: "A vetted editor is assigned",
    body: "We choose an editor whose experience fits your brief. Nobody bids on your project.",
  },
  {
    title: "Brief, references and revisions",
    body: "Your references go into the brief. Three rounds of revisions are included.",
  },
  {
    title: "Delivery",
    body: "Lenscape checks the final cut and delivers the files to you.",
  },
];

const EDITOR_STEPS = [
  {
    title: "Create an account",
    body: "Register with your email. An account on its own gives no access to projects.",
  },
  {
    title: "Apply with your portfolio",
    body: "Share your work, specialisations, software and availability.",
  },
  {
    title: "Get verified by Lenscape",
    body: "Our team reviews every application before activating an editor.",
  },
  {
    title: "Receive clear briefs",
    body: "Each invitation states the deliverables, the deadline and the pay. Work starts only once the pay is agreed.",
  },
];

const PRINCIPLES = [
  {
    title: "One point of contact",
    body: "Clients deal with Lenscape Studios from the first message to the final files. Editors never quote or invoice clients directly.",
  },
  {
    title: "Not a marketplace",
    body: "There are no listings and no bidding. Lenscape matches each project to an editor it has verified.",
  },
  {
    title: "Agreed before it starts",
    body: "No editing begins until the scope is agreed with the client and the editor's pay is approved.",
  },
  {
    title: "Revisions counted fairly",
    body: "Three client revision rounds are included. Fixing an editor's own mistakes does not use one up.",
  },
];

export default function Home() {
  return (
    <PublicPage>
      {/* Hero */}
      <section className="relative isolate overflow-hidden">
        <div aria-hidden="true" className="landing-glow absolute inset-0 -z-10" />
        <div className="mx-auto grid w-full max-w-6xl grid-cols-[minmax(0,1fr)] gap-10 px-4 pt-14 pb-16 sm:pt-20 md:px-6 lg:pb-24">
          <div className="grid max-w-3xl gap-6">
            <p
              className="landing-rise text-brand-text text-sm font-medium"
              style={{ "--i": 0 } as CSSProperties}
            >
              Video editing, managed by Lenscape Studios
            </p>
            <h1
              className="landing-rise text-[2.625rem] leading-[1.02] font-semibold tracking-tighter text-balance sm:text-6xl lg:text-7xl"
              style={{ "--i": 1 } as CSSProperties}
            >
              Where every edit comes together.
            </h1>
            <p
              className="landing-rise text-muted-foreground max-w-[44ch] text-lg text-pretty sm:text-xl"
              style={{ "--i": 2 } as CSSProperties}
            >
              Send us your project. We assign a vetted editor and manage the edit from brief to
              final delivery.
            </p>
            <div
              className="landing-rise flex flex-wrap gap-3"
              style={{ "--i": 3 } as CSSProperties}
            >
              <Link href="/inquire" className={buttonVariants({ size: "lg", className: cta })}>
                Send a project
              </Link>
              <Link
                href="/sign-up"
                className={buttonVariants({
                  size: "lg",
                  variant: "outline",
                  className: ctaOutline,
                })}
              >
                Join as an editor
              </Link>
            </div>
          </div>

          <div className="landing-rise" style={{ "--i": 4 } as CSSProperties}>
            <ProjectTimeline />
          </div>
        </div>
      </section>

      {/* The two entry points */}
      <section
        aria-labelledby="ways-in"
        className="mx-auto w-full max-w-6xl px-4 py-16 md:px-6 lg:py-24"
      >
        <h2
          id="ways-in"
          className="max-w-2xl text-3xl font-semibold tracking-tight text-balance sm:text-4xl"
        >
          Two ways in, kept separate
        </h2>
        <p className="text-muted-foreground mt-4 max-w-[60ch] text-lg">
          Clients send work without an account. Editors register and apply. The two never cross
          paths without Lenscape in between.
        </p>

        <div className="bg-card mt-10 grid overflow-hidden rounded-2xl border lg:grid-cols-2">
          <article className="grid content-start gap-8 p-6 sm:p-8 lg:p-10">
            <div className="grid gap-2">
              <h3 className="text-2xl font-semibold tracking-tight">For clients and agencies</h3>
              <p className="text-muted-foreground">
                Tell us what you need. Lenscape manages the edit for you.
              </p>
            </div>
            <StepList steps={CLIENT_STEPS} />
            <div>
              <Link href="/inquire" className={buttonVariants({ size: "lg", className: cta })}>
                Send a project
              </Link>
            </div>
          </article>

          <article className="grid content-start gap-8 border-t p-6 sm:p-8 lg:border-t-0 lg:border-l lg:p-10">
            <div className="grid gap-2">
              <h3 className="text-2xl font-semibold tracking-tight">For video editors</h3>
              <p className="text-muted-foreground">Well-briefed work, without pitching for it.</p>
            </div>
            <StepList steps={EDITOR_STEPS} />
            <div>
              <Link
                href="/sign-up"
                className={buttonVariants({
                  size: "lg",
                  variant: "outline",
                  className: ctaOutline,
                })}
              >
                Join as an editor
              </Link>
            </div>
          </article>
        </div>
      </section>

      {/* Services */}
      <section
        aria-labelledby="formats"
        className="mx-auto w-full max-w-6xl px-4 py-16 md:px-6 lg:py-24"
      >
        <h2 id="formats" className="text-3xl font-semibold tracking-tight sm:text-4xl">
          What we edit
        </h2>
        <p className="text-muted-foreground mt-4 max-w-[60ch] text-lg">
          Not sure where your project fits? Describe it in the inquiry and we will suggest the right
          approach.
        </p>
        <div className="mt-10">
          <ServiceFormats />
        </div>
      </section>

      {/* How it works, as principles */}
      <section
        aria-labelledby="principles"
        className="mx-auto w-full max-w-6xl px-4 py-16 md:px-6 lg:py-24"
      >
        <div className="grid gap-10 lg:grid-cols-[minmax(0,5fr)_minmax(0,7fr)] lg:gap-16">
          <div className="lg:sticky lg:top-10 lg:self-start">
            <h2
              id="principles"
              className="text-3xl font-semibold tracking-tight text-balance sm:text-4xl"
            >
              How we work with both sides
            </h2>
            <p className="text-muted-foreground mt-4 max-w-[40ch] text-lg">
              The same rules apply to every project, whoever you are.
            </p>
          </div>
          <dl className="grid gap-x-10 gap-y-10 sm:grid-cols-2">
            {PRINCIPLES.map((p) => (
              <div
                key={p.title}
                className="border-brand-text/50 grid content-start gap-2 border-l-2 pl-5"
              >
                <dt className="text-lg font-semibold tracking-tight">{p.title}</dt>
                <dd className="text-muted-foreground">{p.body}</dd>
              </div>
            ))}
          </dl>
        </div>
      </section>

      {/* Closing choice */}
      <section
        aria-labelledby="start"
        className="mx-auto w-full max-w-6xl px-4 pt-8 pb-20 md:px-6 lg:pb-28"
      >
        <h2 id="start" className="sr-only">
          Get started
        </h2>
        <div className="grid gap-4 md:grid-cols-2">
          <Link
            href="/inquire"
            className="group bg-primary text-primary-foreground focus-visible:ring-ring/60 grid gap-10 rounded-2xl p-8 transition-transform duration-300 ease-[cubic-bezier(0.16,1,0.3,1)] outline-none hover:-translate-y-1 focus-visible:ring-4 active:translate-y-0 motion-reduce:transition-none motion-reduce:hover:translate-y-0 sm:p-10"
          >
            <span className="text-lg font-medium opacity-90">I have a project</span>
            <span className="text-3xl font-semibold tracking-tight sm:text-4xl">
              Send a project
            </span>
          </Link>
          <Link
            href="/sign-up"
            className="group bg-card focus-visible:ring-ring/60 grid gap-10 rounded-2xl border p-8 transition-transform duration-300 ease-[cubic-bezier(0.16,1,0.3,1)] outline-none hover:-translate-y-1 focus-visible:ring-4 active:translate-y-0 motion-reduce:transition-none motion-reduce:hover:translate-y-0 sm:p-10"
          >
            <span className="text-muted-foreground text-lg font-medium">I edit video</span>
            <span className="text-3xl font-semibold tracking-tight sm:text-4xl">
              Join as an editor
            </span>
          </Link>
        </div>
      </section>
    </PublicPage>
  );
}
