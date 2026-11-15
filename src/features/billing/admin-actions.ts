"use server";

import { refresh, revalidatePath } from "next/cache";

import { userMessageFromDbError } from "@/features/applications/db-errors";
import { validationError, type FormState } from "@/features/authentication/schemas";
import { requireAdmin } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

import {
  billingKeptValues,
  correctPaymentSchema,
  createMilestonesSchema,
  extendDueSchema,
  milestoneActionSchema,
  recordPaymentSchema,
  timezoneSchema,
} from "./schemas";

type Failure = { code: string; message: string };

function failed(error: Failure, values?: FormState["values"]): FormState {
  return { status: "error", message: userMessageFromDbError(error), values };
}

function done(projectId: string | null, message: string): FormState {
  if (projectId) revalidatePath(`/admin/projects/${projectId}`);
  refresh();
  return { status: "success", message };
}

/** Compute the client milestones from the agreed terms and client price (default 50/50). */
export async function createClientMilestonesAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const kept = billingKeptValues(formData);
  const parsed = createMilestonesSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_create_client_milestones", {
    p_project_id: parsed.data.projectId,
    p_shares: parsed.data.shares,
  });
  if (error) return failed(error, kept);
  return done(parsed.data.projectId, `${data} client milestone${data === 1 ? "" : "s"} created.`);
}

export async function issueClientInvoiceAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = milestoneActionSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_issue_client_invoice", {
    p_milestone_id: parsed.data.milestoneId,
  });
  if (error) return failed(error);
  return done(parsed.data.projectId, `Invoice recorded as issued. Due ${data}.`);
}

export async function recordClientPaymentAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const kept = billingKeptValues(formData);
  const parsed = recordPaymentSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_record_client_payment", {
    p_milestone_id: parsed.data.milestoneId,
    p_transfer_reference: parsed.data.transferReference,
    ...(parsed.data.receivedOn ? { p_received_on: parsed.data.receivedOn } : {}),
  });
  if (error) return failed(error, kept);
  return done(
    parsed.data.projectId,
    "Transfer recorded. Verify it once you have checked the bank.",
  );
}

export async function verifyClientPaymentAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = milestoneActionSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_verify_client_payment", {
    p_milestone_id: parsed.data.milestoneId,
  });
  if (error) return failed(error);
  return done(parsed.data.projectId, "Transfer verified.");
}

export async function correctClientPaymentAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const kept = billingKeptValues(formData);
  const parsed = correctPaymentSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_correct_client_payment", {
    p_milestone_id: parsed.data.milestoneId,
    p_reason: parsed.data.reason,
  });
  if (error) return failed(error, kept);
  return done(parsed.data.projectId, "Verification corrected: the transfer is unverified again.");
}

export async function extendDepositDueAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const kept = billingKeptValues(formData);
  const parsed = extendDueSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_extend_deposit_due", {
    p_milestone_id: parsed.data.milestoneId,
    p_due_date: parsed.data.dueDate,
    p_reason: parsed.data.reason,
  });
  if (error) return failed(error, kept);
  return done(parsed.data.projectId, `Deposit due date extended to ${parsed.data.dueDate}.`);
}

export async function setBusinessTimezoneAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const kept = billingKeptValues(formData);
  const parsed = timezoneSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_business_timezone", {
    p_timezone: parsed.data.timezone,
  });
  if (error) return failed(error, kept);
  revalidatePath("/admin/settings");
  return done(null, `Business timezone set to ${parsed.data.timezone}.`);
}
