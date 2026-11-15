"use server";

import { refresh, revalidatePath } from "next/cache";

import { userMessageFromDbError } from "@/features/applications/db-errors";
import { validationError, type FormState } from "@/features/authentication/schemas";
import { requireAdmin } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

import {
  adjustmentIdSchema,
  adjustmentKeptValues,
  chargeRoundSchema,
  createQuoteSchema,
  offerAdjustmentSchema,
  quoteAnswerSchema,
  quoteIdSchema,
  setRequiredSchema,
  settleSchema,
} from "./schemas";

type Failure = { code: string; message: string };

function failed(error: Failure, values?: FormState["values"]): FormState {
  return { status: "error", message: userMessageFromDbError(error), values };
}

function done(projectId: string, message: string): FormState {
  revalidatePath(`/admin/projects/${projectId}`);
  revalidatePath("/admin/projects");
  revalidatePath("/admin/earnings");
  refresh();
  return { status: "success", message };
}

/** Mark (or clear) an open client revision as needing extra editor pay before it begins. */
export async function setAdjustmentRequiredAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = setRequiredSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_revision_adjustment_required", {
    p_revision_id: parsed.data.revisionId,
    p_required: parsed.data.required,
  });
  if (error) return failed(error);
  return done(
    parsed.data.projectId,
    parsed.data.required
      ? "Extra pay is now required before this round begins."
      : "Extra pay is no longer required for this round.",
  );
}

export async function offerAdjustmentAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const kept = adjustmentKeptValues(formData);
  const parsed = offerAdjustmentSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_offer_adjustment", {
    p_assignment_id: v.assignmentId,
    p_kind: v.kind,
    p_amount: v.amount,
    ...(v.revisionId ? { p_revision_request_id: v.revisionId } : {}),
    ...(v.quoteId ? { p_scope_quote_id: v.quoteId } : {}),
    ...(v.note ? { p_note: v.note } : {}),
  });
  if (error) return failed(error, kept);
  return done(v.projectId, "Extra pay offered. The editor has been notified.");
}

export async function withdrawAdjustmentAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = adjustmentIdSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_withdraw_adjustment", {
    p_adjustment_id: parsed.data.adjustmentId,
  });
  if (error) return failed(error);
  return done(parsed.data.projectId, "Offer withdrawn.");
}

export async function createScopeQuoteAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const kept = adjustmentKeptValues(formData);
  const parsed = createQuoteSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_create_scope_quote", {
    p_revision_request_id: v.revisionId,
    p_description: v.description,
    p_amount: v.amount,
    p_currency: v.currency,
  });
  if (error) return failed(error, kept);
  return done(v.projectId, "Scope quote drafted.");
}

export async function sendScopeQuoteAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = quoteIdSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_send_scope_quote", {
    p_quote_id: parsed.data.quoteId,
  });
  if (error) return failed(error);
  return done(parsed.data.projectId, "Scope quote marked as sent to the client.");
}

export async function recordScopeQuoteAnswerAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const kept = adjustmentKeptValues(formData);
  const parsed = quoteAnswerSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_record_scope_quote_answer", {
    p_quote_id: v.quoteId,
    p_accepted: v.accepted,
    ...(v.dueDate ? { p_due_date: v.dueDate } : {}),
  });
  if (error) return failed(error, kept);
  return done(
    v.projectId,
    v.accepted
      ? "Client acceptance recorded; the extra work charge was added to client billing."
      : "Client decline recorded.",
  );
}

export async function chargeExtraRoundAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const kept = adjustmentKeptValues(formData);
  const parsed = chargeRoundSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_charge_extra_round", {
    p_revision_request_id: parsed.data.revisionId,
    p_due_date: parsed.data.dueDate,
  });
  if (error) return failed(error, kept);
  return done(parsed.data.projectId, "Extra round charge added to client billing.");
}

/** Cancel the project and settle both sides in one step. */
export async function settleCancellationAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const kept = adjustmentKeptValues(formData);
  const parsed = settleSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_settle_cancellation", {
    p_project_id: v.projectId,
    ...(v.adjustedEarned === null ? {} : { p_adjusted_editor_earned: v.adjustedEarned }),
    ...(v.reason ? { p_reason: v.reason } : {}),
  });
  if (error) return failed(error, kept);
  return done(v.projectId, "Project cancelled and settled.");
}
