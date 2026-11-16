import Link from "next/link";

import { Wordmark } from "@/components/wordmark";
import { container, ctaPrimary, ctaSecondary, ctaSize, focusRing } from "@/features/landing/styles";

const navLink = `${focusRing} font-landing-ui text-muted-foreground hover:text-foreground px-1 py-1 text-[0.8125rem] font-bold transition-colors`;

export function LandingHeader({ showWork }: { showWork: boolean }) {
  return (
    <header className="bg-background/80 supports-[backdrop-filter]:bg-background/70 sticky top-0 z-40 border-b border-transparent backdrop-blur-md">
      <a
        href="#main"
        className="bg-primary text-primary-foreground font-landing-ui sr-only rounded-md px-3 py-2 text-sm font-bold focus:not-sr-only focus:absolute focus:top-3 focus:left-4"
      >
        Skip to content
      </a>
      <div className={`${container} flex h-16 items-center justify-between gap-4`}>
        <Link href="/" aria-label="EditStation home" className={`${focusRing} shrink-0`}>
          <Wordmark />
        </Link>

        <nav aria-label="Sections" className="hidden items-center gap-5 lg:flex">
          {showWork ? (
            <a href="#work" className={navLink}>
              Work
            </a>
          ) : null}
          <a href="#platform" className={navLink}>
            Platform
          </a>
          <a href="#process" className={navLink}>
            Process
          </a>
          <Link href="/sign-in" className={navLink}>
            Sign in
          </Link>
        </nav>

        <div className="flex items-center gap-2">
          <Link href="/inquire" className={`${ctaSecondary} ${ctaSize.sm} max-sm:hidden`}>
            Start a project
          </Link>
          <Link href="/apply" className={`${ctaPrimary} ${ctaSize.sm} max-[399px]:hidden`}>
            Join as an editor
          </Link>
        </div>
      </div>
    </header>
  );
}
