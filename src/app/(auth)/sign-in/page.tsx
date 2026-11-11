import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";

import { AuthShell, Loading } from "@/components/auth-shell";
import { SignInForm } from "@/features/authentication/components/auth-forms";

export const metadata: Metadata = { title: "Sign in · EDITSTATION" };

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
        <SignInForm />
      </Suspense>
    </AuthShell>
  );
}
