"use server";

import { refresh, revalidatePath } from "next/cache";

import { userMessageFromDbError } from "@/features/applications/db-errors";
import { validationError, type FormState } from "@/features/authentication/schemas";
import { requireActiveEditor } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

import { assetActionSchema, reportAssetSchema, respondSchema } from "./schemas";

/** The editor's answer to an offer: accept, decline or propose a different amount. */
export async function editorRespondAction(_prev: FormState, formData: FormData) {
  await requireActiveEditor();
  const kept = {
    amount: String(formData.get("amount") ?? "").slice(0, 20),
    currency: String(formData.get("currency") ?? "").slice(0, 3),
    message: String(formData.get("message") ?? "").slice(0, 2000),
  };
  const parsed = respondSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("editor_respond_offer", {
    p_assignment_id: v.assignmentId,
    p_action: v.action,
    ...(v.action === "counter" && v.amount !== null ? { p_amount: v.amount } : {}),
    ...(v.action === "counter" && v.currency !== null ? { p_currency: v.currency } : {}),
    ...(v.message === null ? {} : { p_message: v.message }),
  });
  if (error) {
    return { status: "error", message: userMessageFromDbError(error), values: kept } as FormState;
  }
  revalidatePath("/editor");
  revalidatePath(`/editor/projects/${v.projectId}`);
  refresh();
  return {
    status: "success",
    message:
      v.action === "accept"
        ? "You accepted the offer. The studio will confirm the assignment."
        : v.action === "counter"
          ? "Your counteroffer was sent."
          : "You declined the offer.",
  } as FormState;
}

/** KB7: the assigned editor cannot open an asset. Notifies the studio. */
export async function reportAssetAction(_prev: FormState, formData: FormData) {
  await requireActiveEditor();
  const kept = { note: String(formData.get("note") ?? "").slice(0, 1000) };
  const parsed = reportAssetSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const supabase = await createClient();
  const { error } = await supabase.rpc("editor_report_asset_inaccessible", {
    p_asset_id: parsed.data.assetId,
    p_note: parsed.data.note,
  });
  if (error) {
    return { status: "error", message: userMessageFromDbError(error), values: kept } as FormState;
  }
  revalidatePath(`/editor/projects/${parsed.data.projectId}`);
  refresh();
  return {
    status: "success",
    message: "Reported. The studio has been told and will sort out access.",
  } as FormState;
}

/** The editor can open the asset. Recorded for the studio; it does not verify access. */
export async function confirmAssetAccessAction(_prev: FormState, formData: FormData) {
  await requireActiveEditor();
  const parsed = assetActionSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("editor_confirm_asset_access", {
    p_asset_id: parsed.data.assetId,
  });
  if (error) {
    return { status: "error", message: userMessageFromDbError(error) } as FormState;
  }
  revalidatePath(`/editor/projects/${parsed.data.projectId}`);
  refresh();
  return {
    status: "success",
    message: "Thanks. The studio will verify your access.",
  } as FormState;
}
