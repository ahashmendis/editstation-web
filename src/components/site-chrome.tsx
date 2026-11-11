import Link from "next/link";
import type { ReactNode } from "react";

// Public site chrome. Copy is placeholder until brand (KB2) and services (KB3) are settled
// (decision S: English only).
export function SiteHeader() {
  return (
    <header className="border-b">
      <div className="mx-auto flex w-full max-w-5xl flex-wrap items-center justify-between gap-3 px-4 py-4">
        <Link href="/" className="text-lg font-semibold tracking-tight">
          EDITSTATION
        </Link>
        <nav aria-label="Main" className="flex flex-wrap items-center gap-4 text-sm">
          <Link href="/inquire" className="hover:underline">
            Send a project
          </Link>
          <Link href="/sign-up" className="hover:underline">
            Join as an editor
          </Link>
          <Link href="/sign-in" className="text-muted-foreground hover:underline">
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
      <div className="text-muted-foreground mx-auto flex w-full max-w-5xl flex-wrap justify-between gap-3 px-4 py-6 text-sm">
        <p>EDITSTATION · A Lenscape Studios production network</p>
        <nav aria-label="Legal" className="flex gap-4">
          <Link href="/legal/privacy" className="hover:underline">
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
      <main className="flex-1">{children}</main>
      <SiteFooter />
    </div>
  );
}
