"use server";

import { createHash } from "node:crypto";
import { headers } from "next/headers";

import { userMessageFromDbError } from "@/features/applications/db-errors";
import { validationError, type FormState } from "@/features/authentication/schemas";
import { createClient } from "@/lib/supabase/server";

import { PRIVACY_NOTICE_VERSION } from "./constants";
import { inquiryFormInput, inquiryKeptValues, inquirySchema } from "./schemas";

const nullable = <T>(value: T | null) => value as T;

const THANK_YOU: FormState = {
  status: "success",
  message:
    "Thank you. We've received your project details and will be in touch to discuss scope, timing and pricing.",
};

/**
 * Per-source key for rate limiting: SHA-256 of the client IP. The raw IP is never stored;
 * the database keeps the hash for one hour (decision O). Null when no IP is available.
 */
async function clientKey(): Promise<string | null> {
  const h = await headers();
  const ip = h.get("x-forwarded-for")?.split(",")[0]?.trim() || h.get("x-real-ip")?.trim();
  return ip ? createHash("sha256").update(ip).digest("hex") : null;
}

/** Public client/agency inquiry. No account; never creates a project. */
export async function submitInquiryAction(
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  // Honeypot: a field humans never see. Pretend success so bots learn nothing.
  if (String(formData.get("website") ?? "") !== "") return THANK_YOU;

  const values = inquiryKeptValues(formData);
  const parsed = inquirySchema.safeParse(inquiryFormInput(formData));
  if (!parsed.success) return validationError(parsed.error, values);

  if (formData.get("acceptPrivacy") !== "on") {
    return {
      status: "error",
      message: "Please confirm you've read the privacy notice.",
      fieldErrors: { acceptPrivacy: ["Required to send your inquiry."] },
      values,
    };
  }

  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("submit_client_inquiry", {
    p_contact_name: v.contactName,
    p_company: nullable(v.company),
    p_email: v.email,
    p_phone: nullable(v.phone),
    p_service_type: v.serviceType,
    p_description: v.description,
    p_expected_deliverables: nullable(v.expectedDeliverables),
    p_budget_range_id: nullable(v.budgetRangeId),
    p_expected_deadline: nullable(v.expectedDeadline),
    p_client_notes: nullable(v.clientNotes),
    p_links: v.links,
    p_privacy_notice_version: PRIVACY_NOTICE_VERSION,
    p_client_key: nullable(await clientKey()),
  });
  if (error) return { status: "error", message: userMessageFromDbError(error), values };

  return THANK_YOU;
}
