"use server";

import { redirect } from "next/navigation";

import { userMessageFromDbError } from "@/features/applications/db-errors";
import { keptValues, validationError, type FormState } from "@/features/authentication/schemas";
import { PRIVACY_NOTICE_VERSION } from "@/features/inquiries/constants";
import { getAccess, homePathFor } from "@/lib/auth/access";
import { isClientPath } from "@/lib/auth/home-path";
import { safeNextPath } from "@/lib/auth/safe-next-path";
import { createClient } from "@/lib/supabase/server";

import {
  clientProjectRequestInput,
  clientProjectRequestKeptValues,
  clientProjectRequestSchema,
  requestCodeSchema,
  verifyCodeSchema,
} from "./schemas";

// Client sign-in by emailed one-time code (design "Accounts and sign-in"). Only accounts an admin
// invited exist, and shouldCreateUser is false, so this flow can never create an account. The
// same message is shown whether or not the email has access (no account enumeration).

const SENT_MESSAGE =
  "If this email has client access, we've sent an 8-digit sign-in code to it. Enter it below.";

export async function requestClientCodeAction(
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  const parsed = requestCodeSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, keptValues(formData));

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithOtp({
    email: parsed.data.email,
    options: { shouldCreateUser: false },
  });
  // Only the per-IP request limit gets its own message. The per-email send limit can only be hit
  // for an existing account, so it gets the same answer as a sent code (no enumeration).
  if (error && error.code === "over_request_rate_limit") {
    return {
      status: "error",
      message: "Too many attempts. Please wait a few minutes and try again.",
      values: { email: parsed.data.email },
    };
  }
  // Any other error (no such user, per-email send limit...) gets the same answer as a sent code.
  return {
    status: "success",
    message: SENT_MESSAGE,
    values: { email: parsed.data.email, step: "code" },
  };
}

export async function verifyClientCodeAction(
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  const parsed = verifyCodeSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) {
    const failed = validationError(parsed.error, keptValues(formData));
    return { ...failed, values: { email: String(formData.get("email") ?? ""), step: "code" } };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.verifyOtp({
    email: parsed.data.email,
    token: parsed.data.code,
    type: "email",
  });
  if (error) {
    return {
      status: "error",
      message:
        error.status === 429
          ? "Too many attempts. Please wait a few minutes and try again."
          : "That code is not valid or has expired. Check the latest email or request a new code.",
      values: { email: parsed.data.email, step: "code" },
    };
  }

  const access = await getAccess();
  const home = access ? homePathFor(access) : "/client/sign-in";
  // Admins always go through MFA; a client may follow a safe `next` inside the client area only.
  const next = formData.get("next");
  const destination =
    home === "/client" && typeof next === "string" && isClientPath(safeNextPath(next, ""))
      ? safeNextPath(next, home)
      : home;
  redirect(destination);
}

// ---------------------------------------------------------------------------
// New project (a request: a lead the studio reviews, never a project by itself)
// ---------------------------------------------------------------------------

const REQUEST_SENT: FormState = {
  status: "success",
  message:
    "Thank you. The studio will review your request and get in touch about scope, timing and pricing. You can follow it under My requests.",
};

const nullable = <T>(value: T | null) => value as T;

/**
 * Sends a project request for the signed-in client. Contact details are not part of the form:
 * the database takes them from the client's own account (client_submit_project), which also
 * checks the client's access and the daily limit.
 */
export async function submitClientProjectAction(
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  // Honeypot, as on the public form: pretend success so bots learn nothing.
  if (String(formData.get("website") ?? "") !== "") return REQUEST_SENT;

  const values = clientProjectRequestKeptValues(formData);
  const parsed = clientProjectRequestSchema.safeParse(clientProjectRequestInput(formData));
  if (!parsed.success) return validationError(parsed.error, values);

  if (formData.get("acceptPrivacy") !== "on") {
    return {
      status: "error",
      message: "Please confirm you've read the privacy notice.",
      fieldErrors: { acceptPrivacy: ["Required to send your request."] },
      values,
    };
  }

  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("client_submit_project", {
    p_service_type: v.serviceType,
    p_description: v.description,
    p_expected_deliverables: nullable(v.expectedDeliverables),
    p_budget_range_id: nullable(v.budgetRangeId),
    p_expected_deadline: nullable(v.expectedDeadline),
    p_client_notes: nullable(v.clientNotes),
    p_links: v.links,
    p_privacy_notice_version: PRIVACY_NOTICE_VERSION,
  });
  if (error) return { status: "error", message: userMessageFromDbError(error), values };

  return REQUEST_SENT;
}
