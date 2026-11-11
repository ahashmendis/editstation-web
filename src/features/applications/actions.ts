"use server";

import { refresh } from "next/cache";

import { validationError, type FormState } from "@/features/authentication/schemas";
import { requireApplicant } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

import { EDITOR_TERMS_VERSION, PRIVACY_NOTICE_VERSION } from "./constants";
import { userMessageFromDbError } from "./db-errors";
import { editorProfileSchema, profileFormInput, requestResponseSchema } from "./schemas";

// Supabase's generated RPC arg types mark every argument non-null, but our SQL treats null as
// "empty" (drafts). This narrows the type without changing the value.
const nullable = <T>(value: T | null) => value as T;

/** Save the applicant's profile; with intent=submit, also submit the application. */
export async function saveApplicationAction(
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  await requireApplicant();
  const parsed = editorProfileSchema.safeParse(profileFormInput(formData));
  if (!parsed.success) return validationError(parsed.error);
  const v = parsed.data;

  const submitting = formData.get("intent") === "submit";
  if (submitting && formData.get("acceptTerms") !== "on") {
    return {
      status: "error",
      message: "Please confirm you accept the editor terms and privacy notice.",
      fieldErrors: { acceptTerms: ["Required to submit."] },
    };
  }

  const supabase = await createClient();
  const saved = await supabase.rpc("save_editor_profile", {
    p_full_name: nullable(v.fullName),
    p_phone: nullable(v.phone),
    p_region: nullable(v.region),
    p_experience_years: nullable(v.experienceYears),
    p_experience_summary: nullable(v.experienceSummary),
    p_availability: nullable(v.availability),
    p_typical_turnaround: nullable(v.typicalTurnaround),
    p_hardware: nullable(v.hardware),
    p_software_other: nullable(v.softwareOther),
    p_specialisations: v.specialisations,
    p_software: v.software,
    p_links: v.links,
  });
  if (saved.error) return { status: "error", message: userMessageFromDbError(saved.error) };

  if (submitting) {
    const submitted = await supabase.rpc("submit_editor_application", {
      p_terms_version: EDITOR_TERMS_VERSION,
      p_privacy_version: PRIVACY_NOTICE_VERSION,
    });
    if (submitted.error) {
      refresh();
      return {
        status: "error",
        message: `Your details were saved, but the application was not submitted. ${userMessageFromDbError(submitted.error)}`,
      };
    }
    refresh();
    return { status: "success", message: "Application submitted. We'll be in touch." };
  }

  refresh();
  return { status: "success", message: "Saved. You can come back and submit later." };
}

export async function respondToRequestAction(
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  await requireApplicant();
  const parsed = requestResponseSchema.safeParse({
    requestId: formData.get("requestId"),
    response: formData.get("response") ?? "",
    responseLink: formData.get("responseLink") ?? "",
  });
  if (!parsed.success) return validationError(parsed.error);

  const supabase = await createClient();
  const { error } = await supabase.rpc("respond_to_application_request", {
    p_request_id: parsed.data.requestId,
    p_response: nullable(parsed.data.response),
    p_response_link: nullable(parsed.data.responseLink),
  });
  if (error) return { status: "error", message: userMessageFromDbError(error) };

  refresh();
  return { status: "success", message: "Thanks, your response has been sent." };
}

export async function withdrawApplicationAction(): Promise<FormState> {
  await requireApplicant();
  const supabase = await createClient();
  const { error } = await supabase.rpc("withdraw_editor_application");
  if (error) return { status: "error", message: userMessageFromDbError(error) };
  refresh();
  return { status: "success", message: "Your application has been withdrawn." };
}
