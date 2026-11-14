"use server";

import { refresh, revalidatePath } from "next/cache";

import { userMessageFromDbError } from "@/features/applications/db-errors";
import { validationError, type FormState } from "@/features/authentication/schemas";
import { requireActiveEditor } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

import { acknowledgeRevisionSchema, submitWorkSchema } from "./schemas";

function refreshEditor(projectId: string) {
  revalidatePath("/editor");
  revalidatePath(`/editor/projects/${projectId}`);
  refresh();
}

/** A new submission version: link, notes and export details. */
export async function submitWorkAction(_prev: FormState, formData: FormData) {
  await requireActiveEditor();
  const kept = {
    link: String(formData.get("link") ?? "").slice(0, 2048),
    notes: String(formData.get("notes") ?? "").slice(0, 4000),
    exportDetails: String(formData.get("exportDetails") ?? "").slice(0, 2000),
  };
  const parsed = submitWorkSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("editor_submit_work", {
    p_assignment_id: v.assignmentId,
    p_link: v.link,
    ...(v.notes === null ? {} : { p_notes: v.notes }),
    ...(v.exportDetails === null ? {} : { p_export_details: v.exportDetails }),
  });
  if (error)
    return { status: "error", message: userMessageFromDbError(error), values: kept } as FormState;
  refreshEditor(v.projectId);
  return { status: "success", message: "Your work was submitted for review." } as FormState;
}

export async function acknowledgeRevisionAction(_prev: FormState, formData: FormData) {
  await requireActiveEditor();
  const parsed = acknowledgeRevisionSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("editor_acknowledge_revision", {
    p_revision_id: v.revisionId,
    p_start: v.start,
  });
  if (error) return { status: "error", message: userMessageFromDbError(error) } as FormState;
  refreshEditor(v.projectId);
  return {
    status: "success",
    message: v.start ? "Marked as in progress." : "Change request acknowledged.",
  } as FormState;
}
