import type { Metadata } from "next";

import { AuthShell } from "@/components/auth-shell";
import { ResetPasswordForm } from "@/features/authentication/components/auth-forms";
import { NO_INDEX } from "@/lib/seo/site";

export const metadata: Metadata = {
  title: "Choose a new password · EDITSTATION",
  robots: NO_INDEX,
};

// Reached from the recovery email via /auth/confirm, which signs the user in.
// src/proxy.ts sends visitors without a session to /sign-in.
export default function ResetPasswordPage() {
  return (
    <AuthShell title="Choose a new password">
      <ResetPasswordForm />
    </AuthShell>
  );
}
