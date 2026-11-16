import type { CSSProperties } from "react";
import Link from "next/link";

import { container, ctaPrimary, ctaSecondary, ctaSize, eyebrow } from "@/features/landing/styles";

// One orchestrated entrance: eyebrow, headline, subhead and actions rise in sequence (--i).
// Reduced motion renders the final state (globals.css). Copy states product rules only
// (docs/WORKFLOWS.md, docs/BUSINESS_RULES.md): no figures, clients or promises.
const rise = (i: number) => ({ "--i": i }) as CSSProperties;

export function Hero() {
  return (
    <section aria-labelledby="hero-title" className="relative isolate overflow-hidden">
      <div
        aria-hidden="true"
        className="landing-glow pointer-events-none absolute inset-x-0 -top-24 -z-10 h-[46rem]"
      />
      <div
        className={`${container} flex flex-col items-center pt-16 pb-20 text-center sm:pt-24 lg:pt-28 lg:pb-28`}
      >
        <p className={`landing-rise ${eyebrow}`} style={rise(0)}>
          Video editing operations
        </p>
        <h1
          id="hero-title"
          className="landing-rise font-landing-serif mt-5 max-w-[16ch] text-[2.75rem] leading-[1.02] font-medium tracking-[-0.01em] text-balance sm:text-[3.5rem] lg:text-[4.0625rem]"
          style={rise(1)}
        >
          Where every edit comes together.
        </h1>
        <p
          className="landing-rise text-muted-foreground mt-6 max-w-[46ch] text-lg font-light text-pretty"
          style={rise(2)}
        >
          EditStation matches each project with a vetted editor and runs the work from brief to
          final delivery. Pay is agreed and the brief confirmed before any editing starts.
        </p>
        <div
          className="landing-rise mt-9 flex w-full flex-col items-stretch justify-center gap-3 min-[420px]:w-auto min-[420px]:flex-row"
          style={rise(3)}
        >
          <Link href="/apply" className={`${ctaPrimary} ${ctaSize.lg}`}>
            Join as an editor
          </Link>
          <Link href="/inquire" className={`${ctaSecondary} ${ctaSize.lg}`}>
            Start a project
          </Link>
        </div>
        <p className="landing-rise text-muted-foreground mt-5 max-w-[52ch] text-sm" style={rise(4)}>
          Editors apply with a portfolio and are verified before they see any work. Clients send a
          project without creating an account.
        </p>
      </div>
    </section>
  );
}
