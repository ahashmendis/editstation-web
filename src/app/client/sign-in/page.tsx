import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { Suspense } from "react";

import { AuthShell, Loading } from "@/components/auth-shell";
import { ClientSignInForm } from "@/features/client-area/components/client-sign-in-form";
import { getAccess, homePathFor } from "@/lib/auth/access";
import { NO_INDEX } from "@/lib/seo/site";

export const metadata: Metadata = { title: "Client sign in · EDITSTATION", robots: NO_INDEX };

export default function ClientSignInPage() {
  return (
    <AuthShell
      title="Client sign in"
      description="We'll email you a one-time code. No password needed."
      footer={
        <>
          Studio team or editor?{" "}
          <Link href="/sign-in" className="underline">
            Sign in with a password
          </Link>
        </>
      }
    >
      {/* The form reads ?next= (request-time data). */}
      <Suspense fallback={<Loading />}>
        <AlreadySignedInGuard />
        <ClientSignInForm />
      </Suspense>
    </AuthShell>
  );
}

/** A signed-in account goes to its own area instead of signing in again. */
async function AlreadySignedInGuard() {
  const access = await getAccess();
  if (access) redirect(homePathFor(access));
  return null;
}
