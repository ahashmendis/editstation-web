"use server";

import { refresh } from "next/cache";
import type { z } from "zod";

import { validationError, type FormState } from "@/features/authentication/schemas";
import { requireAdmin } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

import { userMessageFromDbError } from "./db-errors";
import {
  applicationIdSchema,
  approveSchema,
  assessmentSchema,
  createRequestSchema,
  editorAccessSchema,
  rejectSchema,
  reopenSchema,
  vettingNoteSchema,
} from "./schemas";

const nullable = <T>(value: T | null) => value as T;

type Supabase = Awaited<ReturnType<typeof createClient>>;

/**
 * Shared shape of every admin action: require an MFA-verified admin, validate, run one
 * database function (which re-checks admin + state), refresh the page.
 * The database is the authority; this check only gives a clean early error.
 */
function adminAction<S extends z.ZodType>(
  schema: S,
  run: (
    supabase: Supabase,
    input: z.infer<S>,
  ) => PromiseLike<{ error: { code: string; message: string } | null }>,
  success: string,
) {
  return async (_prev: FormState, formData: FormData): Promise<FormState> => {
    await requireAdmin();
    const parsed = schema.safeParse(Object.fromEntries(formData));
    if (!parsed.success) return validationError(parsed.error);
    const supabase = await createClient();
    const { error } = await run(supabase, parsed.data);
    if (error) return { status: "error", message: userMessageFromDbError(error) };
    refresh();
    return { status: "success", message: success };
  };
}

export const startReviewAction = adminAction(
  applicationIdSchema,
  (db, v) => db.rpc("admin_start_application_review", { p_application_id: v.applicationId }),
  "Moved to review.",
);

export const createRequestAction = adminAction(
  createRequestSchema,
  (db, v) =>
    db.rpc("admin_create_application_request", {
      p_application_id: v.applicationId,
      p_kind: v.kind,
      p_message: v.message,
    }),
  "Request sent to the applicant.",
);

export const recordAssessmentAction = adminAction(
  assessmentSchema,
  (db, v) =>
    db.rpc("admin_record_assessment_result", {
      p_request_id: v.requestId,
      p_result: v.result,
      p_notes: nullable(v.notes),
    }),
  "Test result recorded.",
);

export const approveAction = adminAction(
  approveSchema,
  (db, v) =>
    db.rpc("admin_approve_application", {
      p_application_id: v.applicationId,
      p_level: v.level,
      p_message: nullable(v.message),
    }),
  "Approved. Editor access is now active.",
);

export const rejectAction = adminAction(
  rejectSchema,
  (db, v) =>
    db.rpc("admin_reject_application", {
      p_application_id: v.applicationId,
      p_message: nullable(v.message),
    }),
  "Application marked as not approved.",
);

export const reopenAction = adminAction(
  reopenSchema,
  (db, v) => db.rpc("admin_reopen_application", { p_editor_id: v.editorId }),
  "Application reopened. The applicant can now submit again.",
);

export const setEditorAccessAction = adminAction(
  editorAccessSchema,
  (db, v) =>
    db.rpc("admin_set_editor_access", {
      p_editor_id: v.editorId,
      p_status: v.status,
      p_reason: v.reason,
    }),
  "Editor access updated.",
);

export const addVettingNoteAction = adminAction(
  vettingNoteSchema,
  async (db, v) => {
    const access = await requireAdmin();
    return db
      .from("editor_vetting_notes")
      .insert({ application_id: v.applicationId, author_id: access.userId, note: v.note });
  },
  "Note added.",
);
