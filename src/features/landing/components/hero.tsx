import type { CSSProperties, ReactNode } from "react";
import Link from "next/link";
import { Check } from "lucide-react";

import {
  AdminProjectPanel,
  EditorWorkspacePanel,
} from "@/features/landing/components/dashboard-panels";
import { container, ctaPrimary, ctaSecondary, ctaSize, eyebrow } from "@/features/landing/styles";

// Split hero: copy on the left, a layered stack of the (fictional) dashboard panels on the right.
// One orchestrated entrance on load, CSS only (globals.css, "hero-*"): the headline rises line by
// line out of a mask, the copy and actions follow, then the panels slide in and settle and the
// status chips pop in and idle-float. Under prefers-reduced-motion everything renders in its final
// state. The text is server-rendered and never starts at opacity 0, so it stays the LCP and reads
// without JS. Copy states product rules only (docs/WORKFLOWS.md, docs/BUSINESS_RULES.md).

/** Delay (ms) for one step of the sequence. */
const at = (ms: number) => ({ "--d": `${ms}ms` }) as CSSProperties;

function Line({ children, delay }: { children: ReactNode; delay: number }) {
  return (
    <span className="hero-line block">
      <span className="hero-line-inner block" style={at(delay)}>
        {children}
      </span>
    </span>
  );
}

function Chip({
  children,
  className,
  delay,
  float,
}: {
  children: string;
  className: string;
  delay: number;
  float: number;
}) {
  return (
    <span className={`hero-chip absolute z-20 ${className}`} style={at(delay)}>
      <span
        className="hero-float bg-card/95 flex items-center gap-2 rounded-full border py-1.5 pr-3.5 pl-1.5 font-sans text-xs font-medium whitespace-nowrap shadow-[0_8px_24px_-8px_rgb(60_20_120/0.28)] backdrop-blur"
        style={{ "--f": `${float}s` } as CSSProperties}
      >
        <span className="bg-success/15 text-success grid size-5 place-items-center rounded-full">
          <Check className="size-3" strokeWidth={3} />
        </span>
        {children}
      </span>
    </span>
  );
}

function HeroVisual() {
  return (
    <div aria-hidden="true" className="hero-stage relative mx-auto w-full max-w-[36rem] lg:mx-0">
      {/* Gradient mesh behind the stack. */}
      <div className="hero-mesh pointer-events-none absolute -inset-x-10 -inset-y-12 -z-10" />

      <div className="hero-stack grid">
        <div className="hero-panel hero-panel-back col-start-1 row-start-1 mr-[14%] hidden self-start sm:block">
          <AdminProjectPanel />
        </div>
        <div className="hero-panel hero-panel-front relative z-10 col-start-1 row-start-1 self-end rounded-xl shadow-[0_40px_80px_-32px_color-mix(in_oklch,var(--primary)_45%,transparent)] sm:mt-[38%] sm:ml-[18%]">
          <EditorWorkspacePanel />
        </div>
      </div>

      <Chip
        className="top-[-0.75rem] right-2 sm:top-[2%] sm:right-[-0.5rem]"
        delay={1000}
        float={6}
      >
        Offer accepted
      </Chip>
      <Chip
        className="bottom-[34%] left-[-0.25rem] sm:bottom-[40%] sm:left-[-1.25rem]"
        delay={1100}
        float={7}
      >
        Brief confirmed
      </Chip>
      <Chip className="right-3 bottom-[-0.9rem] sm:right-[6%]" delay={1200} float={6.5}>
        Milestone paid
      </Chip>
    </div>
  );
}

export function Hero() {
  return (
    <section aria-labelledby="hero-title" className="relative isolate overflow-hidden">
      <div
        aria-hidden="true"
        className="landing-glow pointer-events-none absolute inset-x-0 -top-32 -z-10 h-[44rem] opacity-80"
      />
      <div
        className={`${container} grid items-center gap-16 pt-14 pb-20 sm:pt-20 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.08fr)] lg:gap-12 lg:pt-24 lg:pb-28`}
      >
        <div className="grid justify-items-start">
          <p className={`hero-fade ${eyebrow}`} style={at(0)}>
            Video editing operations
          </p>
          <h1
            id="hero-title"
            className="font-landing-serif mt-5 text-[2.75rem] leading-[1.02] font-medium tracking-[-0.01em] sm:text-[3.5rem] lg:text-[4.0625rem]"
          >
            <Line delay={80}>Where every</Line>
            <Line delay={170}>edit comes</Line>
            <Line delay={260}>together.</Line>
          </h1>
          <p
            className="hero-fade text-muted-foreground mt-6 max-w-[44ch] text-lg font-light text-pretty"
            style={at(420)}
          >
            EditStation matches each project with a vetted editor and runs the work from brief to
            final delivery. Pay is agreed and the brief confirmed before any editing starts.
          </p>
          <div
            className="hero-fade mt-9 flex w-full flex-col items-stretch gap-3 min-[420px]:w-auto min-[420px]:flex-row"
            style={at(520)}
          >
            <Link href="/apply" className={`${ctaPrimary} ${ctaSize.lg}`}>
              Join as an editor
            </Link>
            <Link href="/inquire" className={`${ctaSecondary} ${ctaSize.lg}`}>
              Start a project
            </Link>
          </div>
          <p className="hero-fade text-muted-foreground mt-5 max-w-[48ch] text-sm" style={at(600)}>
            Editors apply with a portfolio and are verified before they see any work. Clients send a
            project without creating an account.
          </p>
        </div>

        <HeroVisual />
      </div>
    </section>
  );
}
