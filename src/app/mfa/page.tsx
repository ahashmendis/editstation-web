import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { Suspense } from "react";

import { AuthShell, Loading } from "@/components/auth-shell";
import { SignOutButton } from "@/components/sign-out-button";
import { MfaEnrollForm, MfaVerifyForm } from "@/features/authentication/components/mfa-forms";
import { requireAdminAccount } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Two-step verification · EDITSTATION" };

export default function MfaPage() {
  return (
    <Suspense fallback={<Loading />}>
      <MfaStep />
    </Suspense>
  );
}

async function MfaStep() {
  const access = await requireAdminAccount();
  if (access.aal === "aal2") redirect("/admin");

  const supabase = await createClient();
  const { data } = await supabase.auth.mfa.listFactors();
  const hasVerifiedFactor = Boolean(data?.totp.some((f) => f.status === "verified"));

  return (
    <AuthShell
      title={hasVerifiedFactor ? "Enter your verification code" : "Set up two-step verification"}
      description={
        hasVerifiedFactor
          ? "Open your authenticator app and enter the current code for EDITSTATION."
          : "Admin access requires an authenticator app."
      }
      footer={<SignOutButton />}
    >
      {hasVerifiedFactor ? <MfaVerifyForm /> : <MfaEnrollForm />}
    </AuthShell>
  );
}
