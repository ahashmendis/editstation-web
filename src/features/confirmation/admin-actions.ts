"use server";

import { refresh, revalidatePath } from "next/cache";

import { userMessageFromDbError } from "@/features/applications/db-errors";
import { validationError, type FormState } from "@/features/authentication/schemas";
import { requireAdmin } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

import { reviewInterpretationSchema, startWorkSchema } from "./schemas";

function refreshProject(projectId: string) {
  revalidatePath("/admin/projects");
  revalidatePath(`/admin/projects/${projectId}`);
  refresh();
}

export async function reviewInterpretationAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const kept = { feedback: String(formData.get("feedback") ?? "").slice(0, 4000) };
  const parsed = reviewInterpretationSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_review_interpretation", {
    p_interpretation_id: v.interpretationId,
    p_decision: v.decision,
    ...(v.feedback === null ? {} : { p_feedback: v.feedback }),
  });
  if (error)
    return { status: "error", message: userMessageFromDbError(error), values: kept } as FormState;
  refreshProject(v.projectId);
  return {
    status: "success",
    message: v.decision === "accept" ? "Interpretation accepted." : "Changes requested.",
  } as FormState;
}

/** Starts work on the editor's behalf. The database applies the same gate as for the editor. */
export async function adminStartWorkAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = startWorkSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_start_work", {
    p_assignment_id: parsed.data.assignmentId,
  });
  if (error) return { status: "error", message: userMessageFromDbError(error) } as FormState;
  refreshProject(parsed.data.projectId);
  return { status: "success", message: "Work started." } as FormState;
}
