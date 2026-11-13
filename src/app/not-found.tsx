import Link from "next/link";

import { buttonVariants } from "@/components/ui/button";

export default function NotFound() {
  return (
    <main className="flex flex-1 items-center justify-center px-4 py-16">
      <div className="grid max-w-md gap-4">
        <h1 className="text-2xl font-semibold tracking-tight">Page not found</h1>
        <p className="text-muted-foreground text-sm">
          This page doesn&apos;t exist, or you don&apos;t have access to it.
        </p>
        <div>
          <Link href="/" className={buttonVariants()}>
            Go to the home page
          </Link>
        </div>
      </div>
    </main>
  );
}
