"use server";

import { refresh } from "next/cache";

import { userMessageFromDbError } from "@/features/applications/db-errors";
import { validationError, type FormState } from "@/features/authentication/schemas";
import { requireAdmin } from "@/lib/auth/access";
import type { Database } from "@/lib/supabase/database.types";
import { createClient } from "@/lib/supabase/server";

import {
  budgetRangeSchema,
  inquiryNoteSchema,
  inquiryStatusSchema,
  serviceTypeSchema,
} from "./schemas";

type InquiryStatus = Database["public"]["Enums"]["inquiry_status"];
const nullable = <T>(value: T | null) => value as T;

function done(message: string): FormState {
  refresh();
  return { status: "success", message };
}

function failed(error: { code: string; message: string }): FormState {
  // Unique-key clash on a new service code is the one expected table error here.
  if (error.code === "23505") return { status: "error", message: "That code already exists." };
  return { status: "error", message: userMessageFromDbError(error) };
}

export async function setInquiryStatusAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = inquiryStatusSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_inquiry_status", {
    p_inquiry_id: parsed.data.inquiryId,
    p_status: parsed.data.status as InquiryStatus,
    p_note: nullable(parsed.data.note),
  });
  return error ? failed(error) : done("Status updated.");
}

export async function addInquiryNoteAction(_prev: FormState, formData: FormData) {
  const access = await requireAdmin();
  const parsed = inquiryNoteSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.from("inquiry_notes").insert({
    inquiry_id: parsed.data.inquiryId,
    author_id: access.userId,
    note: parsed.data.note,
  });
  return error ? failed(error) : done("Note added.");
}

/** Create or update a service type. RLS restricts writes to MFA admins. */
export async function saveServiceTypeAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = serviceTypeSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const v = parsed.data;
  const supabase = await createClient();
  const row = { label: v.label, sort_order: v.sortOrder, active: v.active };
  const isNew = formData.get("mode") === "create";
  const { error } = isNew
    ? await supabase.from("service_types").insert({ code: v.code, ...row })
    : await supabase.from("service_types").update(row).eq("code", v.code);
  return error ? failed(error) : done(isNew ? "Service type added." : "Service type saved.");
}

/** Create or update a budget range (decision V: ranges are admin-managed). */
export async function saveBudgetRangeAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = budgetRangeSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const v = parsed.data;
  const supabase = await createClient();
  const row = {
    label: v.label,
    min_amount: v.minAmount,
    max_amount: v.maxAmount,
    currency: v.currency,
    sort_order: v.sortOrder,
    active: v.active,
  };
  const { error } = v.id
    ? await supabase.from("budget_ranges").update(row).eq("id", v.id)
    : await supabase.from("budget_ranges").insert(row);
  return error ? failed(error) : done(v.id ? "Budget range saved." : "Budget range added.");
}
