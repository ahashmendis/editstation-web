import type { Metadata } from "next";
import Link from "next/link";

import { AuthShell } from "@/components/auth-shell";
import { ForgotPasswordForm } from "@/features/authentication/components/auth-forms";
import { NO_INDEX } from "@/lib/seo/site";

export const metadata: Metadata = { title: "Reset password · EDITSTATION", robots: NO_INDEX };

export default function ForgotPasswordPage() {
  return (
    <AuthShell
      title="Reset your password"
      description="We'll email you a link to choose a new password."
      footer={
        <Link href="/sign-in" className="underline">
          Back to sign in
        </Link>
      }
    >
      <ForgotPasswordForm />
    </AuthShell>
  );
}
