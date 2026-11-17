import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { Suspense } from "react";

import { AuthShell, Loading } from "@/components/auth-shell";
import { SignInForm } from "@/features/authentication/components/auth-forms";
import { getAccess, homePathFor } from "@/lib/auth/access";
import { NO_INDEX } from "@/lib/seo/site";

export const metadata: Metadata = { title: "Sign in · EDITSTATION", robots: NO_INDEX };

export default function SignInPage() {
  return (
    <AuthShell
      title="Sign in"
      footer={
        <>
          New editor?{" "}
          <Link href="/sign-up" className="underline">
            Create an account
          </Link>
        </>
      }
    >
      {/* The form reads ?next= and ?error= (request-time data). */}
      <Suspense fallback={<Loading />}>
        <AlreadySignedInGuard />
        <SignInForm />
      </Suspense>
    </AuthShell>
  );
}

/**
 * A signed-in user has no reason to sign in again, and a new password sign-in would replace an
 * MFA-verified session with an assurance level 1 one. Send them to their own area instead.
 */
async function AlreadySignedInGuard() {
  const access = await getAccess();
  if (access) redirect(homePathFor(access));
  return null;
}
