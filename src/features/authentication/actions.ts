"use server";

import { redirect } from "next/navigation";

import { getAccess, homePathFor } from "@/lib/auth/access";
import { safeNextPath } from "@/lib/auth/safe-next-path";
import { createClient } from "@/lib/supabase/server";

import {
  newPasswordSchema,
  passwordResetRequestSchema,
  signInSchema,
  signUpSchema,
  keptValues,
  validationError,
  type FormState,
} from "./schemas";

function authErrorMessage(code: string | undefined): string {
  switch (code) {
    case "weak_password":
      return "That password is too weak. Use at least 10 characters with letters and numbers.";
    case "over_email_send_rate_limit":
    case "over_request_rate_limit":
      return "Too many attempts. Please wait a few minutes and try again.";
    case "same_password":
      return "Choose a password you haven't used for this account.";
    default:
      return "Something went wrong. Please try again.";
  }
}

export async function signUpAction(_prev: FormState, formData: FormData): Promise<FormState> {
  const parsed = signUpSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, keptValues(formData));

  const supabase = await createClient();
  // Sign-up never carries role or access data: the database creates every new
  // account with no editor access (decision D / L).
  const { error } = await supabase.auth.signUp({
    email: parsed.data.email,
    password: parsed.data.password,
  });

  if (error) {
    return { status: "error", message: authErrorMessage(error.code), values: keptValues(formData) };
  }

  // Same message whether or not the email was already registered (no account enumeration).
  return {
    status: "success",
    message:
      "Check your email for a confirmation link. Once confirmed, you can sign in and start your editor application.",
  };
}

export async function signInAction(_prev: FormState, formData: FormData): Promise<FormState> {
  const parsed = signInSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, keptValues(formData));

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword(parsed.data);

  if (error) {
    if (error.code === "email_not_confirmed") {
      return {
        status: "error",
        message: "Please confirm your email first. Check your inbox for the confirmation link.",
        values: keptValues(formData),
      };
    }
    if (error.code === "invalid_credentials") {
      return {
        status: "error",
        message: "Incorrect email or password.",
        values: keptValues(formData),
      };
    }
    return { status: "error", message: authErrorMessage(error.code) };
  }

  const access = await getAccess();
  const home = access ? homePathFor(access) : "/sign-in";
  // Admins always go through MFA first; everyone else may follow a safe `next`.
  const destination =
    access?.isAdminAccount && access.aal !== "aal2"
      ? "/mfa"
      : safeNextPath(formData.get("next"), home);
  redirect(destination);
}

export async function signOutAction(): Promise<void> {
  // Clients sign in with an emailed code, so they return to their own sign-in page.
  const access = await getAccess();
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect(access?.clientStatus ? "/client/sign-in" : "/sign-in");
}

export async function requestPasswordResetAction(
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  const parsed = passwordResetRequestSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, keptValues(formData));

  const supabase = await createClient();
  const { error } = await supabase.auth.resetPasswordForEmail(parsed.data.email);
  if (error && (error.code === "over_email_send_rate_limit" || error.status === 429)) {
    return { status: "error", message: authErrorMessage(error.code) };
  }

  // Generic response: never reveal whether an account exists.
  return {
    status: "success",
    message: "If an account exists for that email, we've sent a password reset link.",
  };
}

export async function updatePasswordAction(
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  const parsed = newPasswordSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);

  const access = await getAccess();
  if (!access)
    return { status: "error", message: "Your reset link has expired. Request a new one." };

  const supabase = await createClient();
  const { error } = await supabase.auth.updateUser({ password: parsed.data.password });
  if (error) return { status: "error", message: authErrorMessage(error.code) };

  redirect(homePathFor(access));
}
