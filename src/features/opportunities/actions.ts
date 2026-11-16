"use server";

import { refresh, revalidatePath } from "next/cache";

import { userMessageFromDbError } from "@/features/applications/db-errors";
import { validationError, type FormState } from "@/features/authentication/schemas";
import { requireActiveEditor } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

import { registerInterestSchema, withdrawInterestSchema } from "./schemas";

const kept = (formData: FormData): FormState["values"] => {
  const pick = (name: string) => {
    const value = formData.get(name);
    return typeof value === "string" ? value.slice(0, 500) : "";
  };
  return {
    proposedAmount: pick("proposedAmount"),
    proposedCurrency: pick("proposedCurrency"),
    note: pick("note"),
  };
};

/** Registers interest in an opportunity. The proposed rate is only a signal; it never sets pay. */
export async function registerInterestAction(_prev: FormState, formData: FormData) {
  await requireActiveEditor();
  const parsed = registerInterestSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept(formData));
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("editor_register_interest", {
    p_opportunity_id: v.opportunityId,
    ...(v.proposedAmount !== null
      ? {
          p_proposed_amount: v.proposedAmount,
          ...(v.proposedCurrency ? { p_proposed_currency: v.proposedCurrency } : {}),
        }
      : {}),
    ...(v.note ? { p_note: v.note } : {}),
  });
  if (error)
    return {
      status: "error",
      message: userMessageFromDbError(error),
      values: kept(formData),
    } as FormState;
  revalidatePath("/editor/opportunities");
  refresh();
  return {
    status: "success",
    message: "Interest registered. Lenscape will let you know if you are chosen.",
  } as FormState;
}

export async function withdrawInterestAction(_prev: FormState, formData: FormData) {
  await requireActiveEditor();
  const parsed = withdrawInterestSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("editor_withdraw_interest", {
    p_interest_id: parsed.data.interestId,
  });
  if (error) return { status: "error", message: userMessageFromDbError(error) } as FormState;
  revalidatePath("/editor/opportunities");
  refresh();
  return { status: "success", message: "Interest withdrawn." } as FormState;
}
