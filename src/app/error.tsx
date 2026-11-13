"use client";

import Link from "next/link";

import { Button, buttonVariants } from "@/components/ui/button";

// Last-resort error boundary. Never shows error.message: it can carry database or server details.
// The digest lets the owner find the matching server log entry.
export default function ErrorPage({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <main className="flex flex-1 items-center justify-center px-4 py-16">
      <div className="grid max-w-md gap-4">
        <h1 className="text-2xl font-semibold tracking-tight">This page couldn&apos;t load</h1>
        <p className="text-muted-foreground text-sm">
          Something went wrong on our side. Try again. If it keeps happening, tell the admin and
          mention the reference below.
        </p>
        {error.digest ? (
          <p className="text-muted-foreground font-mono text-xs">Reference: {error.digest}</p>
        ) : null}
        <div className="flex flex-wrap gap-3">
          <Button onClick={() => reset()}>Try again</Button>
          <Link href="/" className={buttonVariants({ variant: "outline" })}>
            Go to the home page
          </Link>
        </div>
      </div>
    </main>
  );
}
