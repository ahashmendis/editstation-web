import Link from "next/link";
import type { ReactNode } from "react";

import { Wordmark } from "@/components/wordmark";
import { SUPPORT_EMAIL } from "@/lib/site-contact";

// Public site chrome. Copy is placeholder until brand (KB2) and services (KB3) are settled
// (decision S: English only). Link labels match the home page CTAs ("Send a project",
// "Join as an editor") so each entry point has one name across the site.
const navLink =
  "rounded-md px-1 py-1 underline-offset-4 transition-colors hover:underline focus-visible:ring-3 focus-visible:ring-ring/60 outline-none";

export function SiteHeader() {
  return (
    <header className="border-b">
      <div className="mx-auto flex w-full max-w-6xl flex-wrap items-center justify-between gap-x-6 gap-y-2 px-4 py-4 md:px-6">
        <Link
          href="/"
          aria-label="EDITSTATION home"
          className="focus-visible:ring-ring/60 rounded-md outline-none focus-visible:ring-3"
        >
          <Wordmark />
        </Link>
        <nav aria-label="Main" className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
          <Link href="/inquire" className={navLink}>
            Send a project
          </Link>
          <Link href="/sign-up" className={navLink}>
            Join as an editor
          </Link>
          <Link
            href="/sign-in"
            className={`${navLink} text-muted-foreground hover:text-foreground`}
          >
            Sign in
          </Link>
        </nav>
      </div>
    </header>
  );
}

export function SiteFooter() {
  return (
    <footer className="mt-auto border-t">
      <div className="text-muted-foreground mx-auto flex w-full max-w-6xl flex-wrap justify-between gap-3 px-4 py-6 text-sm md:px-6">
        <p>
          EDITSTATION, a Lenscape Studios production network.{" "}
          <a href={`mailto:${SUPPORT_EMAIL}`} className="underline underline-offset-4">
            {SUPPORT_EMAIL}
          </a>
        </p>
        <nav aria-label="Legal" className="flex gap-4">
          <Link href="/legal/privacy" className={navLink}>
            Privacy notice
          </Link>
        </nav>
      </div>
    </footer>
  );
}

export function PublicPage({ children }: { children: ReactNode }) {
  return (
    <div className="flex min-h-full flex-1 flex-col">
      <SiteHeader />
      <main id="main" className="flex-1">
        {children}
      </main>
      <SiteFooter />
    </div>
  );
}
