"use server";

import { refresh, revalidatePath } from "next/cache";

import { userMessageFromDbError } from "@/features/applications/db-errors";
import { validationError, type FormState } from "@/features/authentication/schemas";
import { requireActiveEditor } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

import { savePayoutSchema } from "./schemas";

const text = (formData: FormData, name: string) => String(formData.get(name) ?? "").slice(0, 120);

/**
 * The editor saves their own payout details. The database refuses while the feature is locked.
 * The account number is never echoed back (the form keeps it because it is not reset).
 */
export async function savePayoutDetailsAction(_prev: FormState, formData: FormData) {
  await requireActiveEditor();
  const kept = {
    accountHolder: text(formData, "accountHolder"),
    bank: text(formData, "bank"),
    branch: text(formData, "branch"),
  };
  const parsed = savePayoutSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, kept);
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("editor_save_payout_details", {
    p_account_holder: v.accountHolder,
    p_bank: v.bank,
    p_branch: v.branch,
    p_account_number: v.accountNumber,
  });
  if (error)
    return { status: "error", message: userMessageFromDbError(error), values: kept } as FormState;
  revalidatePath("/editor/earnings");
  refresh();
  return {
    status: "success",
    message: "Payout details saved. Lenscape will confirm them with you by phone before paying.",
  } as FormState;
}
