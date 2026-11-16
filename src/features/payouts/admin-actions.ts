"use server";

import { refresh, revalidatePath } from "next/cache";

import { userMessageFromDbError } from "@/features/applications/db-errors";
import { validationError, type FormState } from "@/features/authentication/schemas";
import { requireAdmin } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

import {
  attestPayoutSchema,
  payoutEnabledSchema,
  revealPayoutSchema,
  verifyPayoutSchema,
} from "./schemas";

type Failure = { code: string; message: string };

const text = (formData: FormData, name: string, max = 500) =>
  String(formData.get(name) ?? "").slice(0, max);

function failed(error: Failure, values?: FormState["values"]): FormState {
  return { status: "error", message: userMessageFromDbError(error), values };
}

function done(message: string): FormState {
  revalidatePath("/admin/earnings", "layout");
  refresh();
  return { status: "success", message };
}

/** Record an out-of-band (phone) verification of the version the admin is looking at. */
export async function verifyPayoutAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const kept = { note: text(formData, "note"), method: text(formData, "method", 20) };
  const parsed = verifyPayoutSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_verify_payout_details", {
    p_editor_id: v.editorId,
    p_version: v.version,
    p_method: v.method,
    p_note: v.note,
  });
  if (error) return failed(error, kept);
  return done("Payout details marked verified.");
}

/** Interim attestation (call 1): only while payout details are locked. No bank data. */
export async function attestPayoutAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const kept = { note: text(formData, "note") };
  const parsed = attestPayoutSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_attest_payout_outside_app", {
    p_editor_id: parsed.data.editorId,
    p_note: parsed.data.note,
  });
  if (error) return failed(error, kept);
  return done("Recorded: payout account verified outside the app.");
}

/** Reveal result: the number travels in its own field, never in the message. */
export type RevealState = FormState & { revealed?: string };

/**
 * Reveal the full account number. Every reveal is audited by the database with the reason. The
 * form shows the number until Hide or a short timer clears it; it is never stored.
 */
export async function revealPayoutAction(
  _prev: RevealState,
  formData: FormData,
): Promise<RevealState> {
  await requireAdmin();
  const kept = { reason: text(formData, "reason") };
  const parsed = revealPayoutSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_reveal_payout_details", {
    p_editor_id: parsed.data.editorId,
    p_reason: parsed.data.reason,
  });
  if (error) return failed(error, kept);
  if (typeof data !== "string" || data.trim() === "") {
    return { status: "error", message: "Something went wrong. Please try again.", values: kept };
  }
  return {
    status: "success",
    message: "Revealed. This was recorded in the activity log.",
    revealed: data,
  };
}

/** The payout details lock. Must stay off until counsel confirms PDPA handling. */
export async function setPayoutEnabledAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = payoutEnabledSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const enabled = parsed.data.enabled === "on";
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_payout_enabled", { p_enabled: enabled });
  if (error) return failed(error);
  revalidatePath("/admin/settings");
  return done(enabled ? "Payout details are now ON." : "Payout details are now OFF (locked).");
}
