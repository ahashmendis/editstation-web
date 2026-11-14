"use server";

import { refresh, revalidatePath } from "next/cache";

import { userMessageFromDbError } from "@/features/applications/db-errors";
import { validationError, type FormState } from "@/features/authentication/schemas";
import { requireActiveEditor } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

import { confirmBriefSchema, startWorkSchema, submitInterpretationSchema } from "./schemas";

function refreshEditor(projectId: string) {
  revalidatePath("/editor");
  revalidatePath(`/editor/projects/${projectId}`);
  refresh();
}

/** The editor's interpretation of the brief: what they will reproduce, adapt, and ask. */
export async function submitInterpretationAction(_prev: FormState, formData: FormData) {
  await requireActiveEditor();
  const kept = {
    willReproduce: String(formData.get("willReproduce") ?? "").slice(0, 4000),
    willAdapt: String(formData.get("willAdapt") ?? "").slice(0, 4000),
    questions: String(formData.get("questions") ?? "").slice(0, 4000),
  };
  const parsed = submitInterpretationSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("editor_submit_interpretation", {
    p_assignment_id: v.assignmentId,
    p_brief_version: v.briefVersion,
    p_will_reproduce: v.willReproduce,
    p_will_adapt: v.willAdapt,
    ...(v.questions === null ? {} : { p_questions: v.questions }),
  });
  if (error)
    return { status: "error", message: userMessageFromDbError(error), values: kept } as FormState;
  refreshEditor(v.projectId);
  return { status: "success", message: "Your interpretation was sent for review." } as FormState;
}

/** Confirms exactly the version, deadline and pay the editor was shown. */
export async function confirmBriefAction(_prev: FormState, formData: FormData) {
  await requireActiveEditor();
  const parsed = confirmBriefSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("editor_confirm_brief", {
    p_assignment_id: v.assignmentId,
    p_brief_version: v.briefVersion,
    p_deadline: v.deadline,
    p_amount: v.amount,
    p_currency: v.currency,
  });
  if (error) return { status: "error", message: userMessageFromDbError(error) } as FormState;
  refreshEditor(v.projectId);
  return { status: "success", message: "You confirmed the brief." } as FormState;
}

export async function startWorkAction(_prev: FormState, formData: FormData) {
  await requireActiveEditor();
  const parsed = startWorkSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("editor_start_work", {
    p_assignment_id: parsed.data.assignmentId,
  });
  if (error) return { status: "error", message: userMessageFromDbError(error) } as FormState;
  refreshEditor(parsed.data.projectId);
  return { status: "success", message: "Work started." } as FormState;
}
