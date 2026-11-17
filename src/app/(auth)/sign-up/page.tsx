import type { Metadata } from "next";
import Link from "next/link";

import { AuthShell } from "@/components/auth-shell";
import { SignUpForm } from "@/features/authentication/components/auth-forms";
import { NO_INDEX } from "@/lib/seo/site";

export const metadata: Metadata = {
  title: "Join the editor network · EDITSTATION",
  robots: NO_INDEX,
};

export default function SignUpPage() {
  return (
    <AuthShell
      title="Join the editor network"
      description="Create an account, then apply to join our vetted network of video editors."
      footer={
        <>
          Already have an account?{" "}
          <Link href="/sign-in" className="underline">
            Sign in
          </Link>
        </>
      }
    >
      <SignUpForm />
    </AuthShell>
  );
}
