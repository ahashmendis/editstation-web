"use server";

import { redirect } from "next/navigation";

import { requireAdminAccount } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

import { totpCodeSchema, validationError, type FormState } from "./schemas";

export type EnrollmentState = FormState & {
  factorId?: string;
  qrCode?: string;
  secret?: string;
};

/** Start TOTP enrolment for an admin account (decision A: admins require MFA). */
export async function startTotpEnrollmentAction(): Promise<EnrollmentState> {
  await requireAdminAccount();
  const supabase = await createClient();

  // Clear abandoned, unverified factors so retries don't pile up.
  const { data: factors } = await supabase.auth.mfa.listFactors();
  for (const factor of factors?.all ?? []) {
    if (factor.factor_type === "totp" && factor.status === "unverified") {
      await supabase.auth.mfa.unenroll({ factorId: factor.id });
    }
  }

  const { data, error } = await supabase.auth.mfa.enroll({
    factorType: "totp",
    friendlyName: `EDITSTATION admin ${new Date().toISOString().slice(0, 10)}`,
  });
  if (error || !data) {
    return { status: "error", message: "Could not start authenticator setup. Please try again." };
  }

  return {
    status: "idle",
    factorId: data.id,
    qrCode: data.totp.qr_code,
    secret: data.totp.secret,
  };
}

async function verifyFactor(factorId: string, code: string): Promise<FormState | null> {
  const supabase = await createClient();
  const { error } = await supabase.auth.mfa.challengeAndVerify({ factorId, code });
  if (error) {
    return {
      status: "error",
      message: "That code didn't work. Check your authenticator app and try again.",
    };
  }
  return null;
}

/** Confirm a newly enrolled factor; this also upgrades the session to aal2. */
export async function verifyTotpEnrollmentAction(
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  await requireAdminAccount();
  const parsed = totpCodeSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);

  const factorId = formData.get("factorId");
  if (typeof factorId !== "string" || factorId.length === 0) {
    return { status: "error", message: "Setup expired. Please start again." };
  }

  // Only accept a factor that belongs to this user and is still unverified.
  const supabase = await createClient();
  const { data: factors } = await supabase.auth.mfa.listFactors();
  const factor = factors?.all.find((f) => f.id === factorId && f.status === "unverified");
  if (!factor) return { status: "error", message: "Setup expired. Please start again." };

  const failure = await verifyFactor(factor.id, parsed.data.code);
  if (failure) return failure;
  redirect("/admin");
}

/** Sign-in step two for admins who already have a verified authenticator. */
export async function verifyTotpAction(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminAccount();
  const parsed = totpCodeSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);

  const supabase = await createClient();
  const { data: factors } = await supabase.auth.mfa.listFactors();
  const factor = factors?.totp.find((f) => f.status === "verified");
  if (!factor)
    return { status: "error", message: "No authenticator is set up. Please set one up." };

  const failure = await verifyFactor(factor.id, parsed.data.code);
  if (failure) return failure;
  redirect("/admin");
}
