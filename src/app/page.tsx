import Link from "next/link";

import { buttonVariants } from "@/components/ui/button";

// Placeholder home. The public website and client inquiry form arrive in Phase 3.
export default function Home() {
  return (
    <main className="flex flex-1 flex-col items-center justify-center gap-6 p-8 text-center">
      <div className="grid gap-2">
        <h1 className="text-2xl font-semibold tracking-tight">EDITSTATION</h1>
        <p className="text-muted-foreground text-sm">A Lenscape Studios production network.</p>
      </div>
      <div className="flex flex-wrap justify-center gap-3">
        <Link href="/sign-up" className={buttonVariants()}>
          Join the editor network
        </Link>
        <Link href="/sign-in" className={buttonVariants({ variant: "outline" })}>
          Sign in
        </Link>
      </div>
    </main>
  );
}
