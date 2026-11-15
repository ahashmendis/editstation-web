"use server";

import { refresh, revalidatePath } from "next/cache";

import { userMessageFromDbError } from "@/features/applications/db-errors";
import { validationError, type FormState } from "@/features/authentication/schemas";
import { requireActiveEditor } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

import { respondAdjustmentSchema } from "./schemas";

/** The editor accepts or declines their own extra pay offer. */
export async function respondAdjustmentAction(_prev: FormState, formData: FormData) {
  await requireActiveEditor();
  const parsed = respondAdjustmentSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("editor_respond_adjustment", {
    p_adjustment_id: v.adjustmentId,
    p_response: v.response,
  });
  if (error) return { status: "error", message: userMessageFromDbError(error) } as FormState;
  revalidatePath(`/editor/projects/${v.projectId}`);
  revalidatePath("/editor/earnings");
  refresh();
  return {
    status: "success",
    message:
      v.response === "accept"
        ? "Extra pay accepted. It is listed on your earnings page."
        : "Offer declined. Lenscape will follow up.",
  } as FormState;
}
