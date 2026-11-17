"use client";

import Link from "next/link";

import { Button, buttonVariants } from "@/components/ui/button";

// Error state for the client area, inside its shell. Never shows error.message (it can carry
// database or server details); the digest lets the studio find the matching server log entry.
export default function ClientAreaError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <main className="mx-auto grid w-full max-w-4xl gap-4 px-4 py-10">
      <h1 className="text-2xl font-semibold tracking-tight">This page couldn&apos;t load</h1>
      <p className="text-muted-foreground text-sm">
        Something went wrong on our side. Try again. If it keeps happening, contact the studio and
        mention the reference below.
      </p>
      {error.digest ? (
        <p className="text-muted-foreground font-mono text-xs">Reference: {error.digest}</p>
      ) : null}
      <div className="flex flex-wrap gap-3">
        <Button onClick={() => reset()}>Try again</Button>
        <Link href="/client" className={buttonVariants({ variant: "outline" })}>
          Back to overview
        </Link>
      </div>
    </main>
  );
}
