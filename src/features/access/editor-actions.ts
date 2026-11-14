"use server";

import { refresh, revalidatePath } from "next/cache";

import { userMessageFromDbError } from "@/features/applications/db-errors";
import { validationError, type FormState } from "@/features/authentication/schemas";
import { requireActiveEditor } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

import { respondSchema } from "./schemas";

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
