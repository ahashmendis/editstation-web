"use server";

import { refresh, revalidatePath } from "next/cache";

import { userMessageFromDbError } from "@/features/applications/db-errors";
import { validationError, type FormState } from "@/features/authentication/schemas";
import { requireAdmin } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

import { classifyRevisionSchema, completeProjectSchema, reviewSubmissionSchema } from "./schemas";

function refreshProject(projectId: string) {
  revalidatePath("/admin/projects");
  revalidatePath(`/admin/projects/${projectId}`);
  revalidatePath("/admin/earnings");
  refresh();
}

/** Review outcome with feedback; a change request is classified in the same step. */
export async function reviewSubmissionAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const kept = {
    outcome: String(formData.get("outcome") ?? "").slice(0, 40),
    feedback: String(formData.get("feedback") ?? "").slice(0, 4000),
    revisionType: String(formData.get("revisionType") ?? "").slice(0, 40),
    reason: String(formData.get("reason") ?? "").slice(0, 4000),
  };
  const parsed = reviewSubmissionSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const v = parsed.data;
  const approved = v.outcome === "approved";
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_review_submission", {
    p_submission_id: v.submissionId,
    p_outcome: v.outcome,
    ...(v.feedback === null ? {} : { p_feedback: v.feedback }),
    ...(approved || v.revisionType === null ? {} : { p_revision_type: v.revisionType }),
    ...(approved || v.reason === null ? {} : { p_reason: v.reason }),
  });
  if (error)
    return { status: "error", message: userMessageFromDbError(error), values: kept } as FormState;
  refreshProject(v.projectId);
  return {
    status: "success",
    message: approved ? "Work approved." : "Review saved and the editor can see it.",
  } as FormState;
}

export async function classifyRevisionAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const kept = {
    revisionType: String(formData.get("revisionType") ?? "").slice(0, 40),
    reason: String(formData.get("reason") ?? "").slice(0, 4000),
  };
  const parsed = classifyRevisionSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_classify_revision", {
    p_revision_id: v.revisionId,
    p_type: v.revisionType,
    p_reason: v.reason,
  });
  if (error)
    return { status: "error", message: userMessageFromDbError(error), values: kept } as FormState;
  refreshProject(v.projectId);
  return { status: "success", message: "Classification saved." } as FormState;
}

export async function completeProjectAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = completeProjectSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_complete_project", {
    p_project_id: parsed.data.projectId,
  });
  if (error) return { status: "error", message: userMessageFromDbError(error) } as FormState;
  refreshProject(parsed.data.projectId);
  return { status: "success", message: "Project completed." } as FormState;
}
