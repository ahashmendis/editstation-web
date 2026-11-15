"use server";

import { refresh, revalidatePath } from "next/cache";

import { userMessageFromDbError } from "@/features/applications/db-errors";
import { validationError, type FormState } from "@/features/authentication/schemas";
import { requireAdmin } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

import {
  markPaidSchema,
  paymentNoteSchema,
  releaseHoldSchema,
  reversePaymentSchema,
  setDueDateSchema,
  setPaymentStatusSchema,
  splitDisputeSchema,
} from "./schemas";

function refreshPayment(paymentId: string) {
  revalidatePath("/admin/earnings");
  revalidatePath(`/admin/earnings/${paymentId}`);
  refresh();
}

const text = (formData: FormData, name: string, max: number) =>
  String(formData.get(name) ?? "").slice(0, max);

const STATUS_MESSAGE: Record<string, string> = {
  pending_approval: "Sent for approval.",
  approved: "Payment approved.",
  processing: "Marked as transfer in progress.",
  on_hold: "Payment put on hold.",
};

export async function setPaymentStatusAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const kept = { reason: text(formData, "reason", 500) };
  const parsed = setPaymentStatusSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_payment_status", {
    p_payment_id: v.paymentId,
    p_status: v.status,
    ...(v.reason === null ? {} : { p_reason: v.reason }),
  });
  if (error)
    return { status: "error", message: userMessageFromDbError(error), values: kept } as FormState;
  refreshPayment(v.paymentId);
  return { status: "success", message: STATUS_MESSAGE[v.status] } as FormState;
}

export async function releasePaymentHoldAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = releaseHoldSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_release_payment_hold", {
    p_payment_id: parsed.data.paymentId,
  });
  if (error) return { status: "error", message: userMessageFromDbError(error) } as FormState;
  refreshPayment(parsed.data.paymentId);
  return { status: "success", message: "Hold released." } as FormState;
}

export async function markPaymentPaidAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const kept = {
    reference: text(formData, "reference", 120),
    transferDate: text(formData, "transferDate", 10),
  };
  const parsed = markPaidSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_mark_payment_paid", {
    p_payment_id: v.paymentId,
    p_transaction_reference: v.reference,
    p_transfer_date: v.transferDate,
  });
  if (error)
    return { status: "error", message: userMessageFromDbError(error), values: kept } as FormState;
  refreshPayment(v.paymentId);
  return { status: "success", message: "Marked paid." } as FormState;
}

export async function setPaymentDueDateAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const kept = { dueDate: text(formData, "dueDate", 10) };
  const parsed = setDueDateSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_payment_due_date", {
    p_payment_id: v.paymentId,
    // The generated type omits null for a nullable date argument; null clears the due date.
    p_due_date: v.dueDate as string,
  });
  if (error)
    return { status: "error", message: userMessageFromDbError(error), values: kept } as FormState;
  refreshPayment(v.paymentId);
  return {
    status: "success",
    message: v.dueDate === null ? "Due date cleared." : "Due date saved.",
  } as FormState;
}

export async function reversePaymentAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const kept = { reason: text(formData, "reason", 500) };
  const parsed = reversePaymentSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_reverse_payment", {
    p_payment_id: v.paymentId,
    p_reason: v.reason,
    p_reopen: v.reopen,
  });
  if (error)
    return { status: "error", message: userMessageFromDbError(error), values: kept } as FormState;
  refreshPayment(v.paymentId);
  return {
    status: "success",
    message: v.reopen ? "Reversed and re-opened for approval." : "Payment reversed.",
  } as FormState;
}

export async function splitPaymentForDisputeAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const kept = { amount: text(formData, "amount", 20), reason: text(formData, "reason", 500) };
  const parsed = splitDisputeSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_split_payment_for_dispute", {
    p_payment_id: v.paymentId,
    p_disputed_amount: v.amount,
    p_reason: v.reason,
  });
  if (error)
    return { status: "error", message: userMessageFromDbError(error), values: kept } as FormState;
  refreshPayment(v.paymentId);
  return {
    status: "success",
    message: "Split: the disputed part is on hold; the rest continues.",
  } as FormState;
}

export async function addPaymentNoteAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const kept = { note: text(formData, "note", 4000) };
  const parsed = paymentNoteSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_add_payment_note", {
    p_payment_id: v.paymentId,
    p_note: v.note,
  });
  if (error)
    return { status: "error", message: userMessageFromDbError(error), values: kept } as FormState;
  refreshPayment(v.paymentId);
  return { status: "success", message: "Note added." } as FormState;
}
