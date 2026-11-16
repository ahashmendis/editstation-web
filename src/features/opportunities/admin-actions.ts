"use server";

import { refresh, revalidatePath } from "next/cache";

import { userMessageFromDbError } from "@/features/applications/db-errors";
import { validationError, type FormState } from "@/features/authentication/schemas";
import { requireAdmin } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

import {
  closeOpportunitySchema,
  publishOpportunitySchema,
  selectEditorSchema,
  summaryArgs,
  updateOpportunitySchema,
} from "./schemas";

type Failure = { code: string; message: string };

const SUMMARY_FIELDS = [
  "title",
  "deliverablesSummary",
  "serviceTypeCode",
  "deadline",
  "formatNotes",
  "showPay",
  "payAmount",
  "payCurrency",
  "closesOn",
] as const;

function keptValues(formData: FormData, names: readonly string[]): FormState["values"] {
  const values: Record<string, string> = {};
  for (const name of names) {
    const value = formData.get(name);
    values[name] = typeof value === "string" ? value.slice(0, 2000) : "";
  }
  return values;
}

function failed(error: Failure, values?: FormState["values"]): FormState {
  return { status: "error", message: userMessageFromDbError(error), values };
}

function done(projectId: string, message: string): FormState {
  revalidatePath(`/admin/projects/${projectId}`);
  revalidatePath("/editor/opportunities");
  refresh();
  return { status: "success", message };
}

export async function publishOpportunityAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const values = keptValues(formData, SUMMARY_FIELDS);
  const parsed = publishOpportunitySchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, values);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_publish_opportunity", {
    p_project_id: parsed.data.projectId,
    ...summaryArgs(parsed.data),
  });
  if (error) return failed(error, values);
  return done(parsed.data.projectId, "Published. Active editors can now see the summary.");
}

export async function updateOpportunityAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const values = keptValues(formData, SUMMARY_FIELDS);
  const parsed = updateOpportunitySchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, values);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_update_opportunity", {
    p_opportunity_id: parsed.data.opportunityId,
    ...summaryArgs(parsed.data),
  });
  if (error) return failed(error, values);
  return done(parsed.data.projectId, "Opportunity summary saved.");
}

export async function closeOpportunityAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = closeOpportunitySchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_close_opportunity", {
    p_opportunity_id: parsed.data.opportunityId,
  });
  if (error) return failed(error);
  return done(parsed.data.projectId, "Opportunity closed. Interested editors were told.");
}

/**
 * "Choose this editor": the existing offer (admin_make_offer, called inside admin_select_editor)
 * at the admin's amount; every other interested editor becomes not selected.
 */
export async function selectEditorAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const values = keptValues(formData, ["amount", "currency", "message"]);
  const parsed = selectEditorSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, values);
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_select_editor", {
    p_interest_id: v.interestId,
    p_amount: v.amount as number,
    ...(v.currency ? { p_currency: v.currency } : {}),
    ...(v.message ? { p_message: v.message } : {}),
  });
  if (error) return failed(error, values);
  return done(v.projectId, "Editor chosen and the offer sent. Follow it in the Editors card.");
}
