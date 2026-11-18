import Link from "next/link";

import { Wordmark } from "@/components/wordmark";
import { container, focusRing } from "@/features/landing/styles";
import { SUPPORT_EMAIL } from "@/lib/site-contact";

// The only place "Lenscape Studios" appears on the landing page (owner decision 10). Legal pages
// are placeholders until counsel's text exists; their wording is not decided here.

const link = `${focusRing} text-muted-foreground hover:text-foreground transition-colors`;

export function LandingFooter() {
  return (
    <footer className="border-t">
      <div className={`${container} grid gap-10 py-12 md:grid-cols-[minmax(0,1fr)_auto]`}>
        <div className="grid content-start gap-4">
          <Link href="/" aria-label="EditStation home" className={`${focusRing} w-fit`}>
            <Wordmark />
          </Link>
          <p className="text-muted-foreground max-w-[40ch] text-sm font-light">
            EditStation, a Lenscape Studios production network, starting with clients and editors in
            Sri Lanka.
          </p>
          <a href={`mailto:${SUPPORT_EMAIL}`} className={`${link} w-fit text-sm`}>
            {SUPPORT_EMAIL}
          </a>
        </div>
        <div className="grid grid-cols-2 gap-10 text-sm sm:gap-16">
          <nav aria-label="Get started" className="grid content-start gap-3">
            <p className="font-landing-ui text-xs font-bold tracking-[0.14em] uppercase">Start</p>
            <Link href="/apply" className={link}>
              Join as an editor
            </Link>
            <Link href="/editors" className={link}>
              How editor applications work
            </Link>
            <Link href="/inquire" className={link}>
              Start a project
            </Link>
            <Link href="/client/sign-in" className={link}>
              Client sign-in
            </Link>
            <Link href="/sign-in" className={link}>
              Editor and admin sign-in
            </Link>
          </nav>
          <nav aria-label="Legal" className="grid content-start gap-3">
            <p className="font-landing-ui text-xs font-bold tracking-[0.14em] uppercase">Legal</p>
            <Link href="/legal/privacy" className={link}>
              Privacy notice
            </Link>
            <Link href="/legal/editor-terms" className={link}>
              Editor terms
            </Link>
          </nav>
        </div>
      </div>
    </footer>
  );
}
