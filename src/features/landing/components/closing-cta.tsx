import Link from "next/link";

import { container, ctaPrimary, ctaSize } from "@/features/landing/styles";

// Repeats the two entry points on the dark band. "Join as an editor" stays the primary action.
export function ClosingCta() {
  return (
    <section aria-labelledby="closing-title" className={`${container} py-20 lg:py-28`}>
      <div className="relative isolate overflow-hidden rounded-3xl bg-[var(--landing-ink)] px-6 py-16 text-center text-[var(--landing-ink-foreground)] sm:px-10 lg:py-24">
        <div
          aria-hidden="true"
          className="landing-glow pointer-events-none absolute inset-x-0 -bottom-40 -z-10 h-[30rem] opacity-90"
        />
        <h2
          id="closing-title"
          className="font-landing-serif mx-auto max-w-[18ch] text-[2.5rem] leading-[1.02] font-medium tracking-[-0.01em] text-balance lg:text-[3.5rem]"
        >
          Ready when you are.
        </h2>
        <p className="mx-auto mt-5 max-w-[46ch] text-lg font-light text-pretty text-[var(--landing-ink-muted)]">
          Editors: apply with your portfolio and we will review it. Clients: tell us about the
          project and we will be in touch.
        </p>
        <div className="mt-9 flex flex-col items-stretch justify-center gap-3 min-[420px]:flex-row min-[420px]:items-center">
          <Link href="/apply" className={`${ctaPrimary} ${ctaSize.lg}`}>
            Join as an editor
          </Link>
          <Link
            href="/inquire"
            className={`font-landing-ui inline-flex h-12 items-center justify-center rounded-full border border-white/25 px-6 text-[0.9375rem] font-bold transition-colors outline-none hover:border-white/60 focus-visible:ring-4 focus-visible:ring-white/50 motion-reduce:transition-none`}
          >
            Start a project
          </Link>
        </div>
      </div>
    </section>
  );
}
