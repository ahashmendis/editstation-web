import "server-only";

import { createClient } from "@/lib/supabase/server";

import { OPEN_INQUIRY_STATUSES, type InquiryStatus } from "./constants";

function check<T>(result: { data: T | null; error: unknown }): T {
  if (result.error) throw result.error;
  if (result.data === null) throw new Error("Unexpected empty result");
  return result.data;
}

/** Options for the public form. Works for anonymous visitors (active rows only, via RLS). */
export async function getInquiryFormOptions() {
  const supabase = await createClient();
  const [services, budgets] = await Promise.all([
    supabase.from("service_types").select("code, label").eq("active", true).order("sort_order"),
    supabase
      .from("budget_ranges")
      .select("id, label, currency")
      .eq("active", true)
      .order("sort_order"),
  ]);
  return { services: check(services), budgets: check(budgets) };
}

export type InquiryFilter = "open" | "closed" | "all";

const FILTER_STATUSES: Record<InquiryFilter, InquiryStatus[] | null> = {
  open: OPEN_INQUIRY_STATUSES,
  closed: ["converted", "declined", "closed", "spam"],
  all: null,
};

/** Admin list (RLS: MFA admins only). */
export async function listInquiries(filter: InquiryFilter) {
  const supabase = await createClient();
  let query = supabase
    .from("client_inquiries")
    .select("id, contact_name, company, email, service_type_label, status, submitted_at")
    .order("submitted_at", { ascending: false })
    .limit(200);
  const statuses = FILTER_STATUSES[filter];
  if (statuses) query = query.in("status", statuses);
  return check(await query);
}

export async function getInquiryDetail(inquiryId: string) {
  const supabase = await createClient();
  const { data: inquiry, error } = await supabase
    .from("client_inquiries")
    .select("*")
    .eq("id", inquiryId)
    .maybeSingle();
  if (error) throw error;
  if (!inquiry) return null;

  const [links, notes, activity] = await Promise.all([
    supabase.from("client_inquiry_links").select("id, url, label").eq("inquiry_id", inquiryId),
    supabase
      .from("inquiry_notes")
      .select("id, note, created_at")
      .eq("inquiry_id", inquiryId)
      .order("created_at", { ascending: false }),
    supabase
      .from("activity_logs")
      .select("id, action, created_at")
      .eq("entity_type", "client_inquiry")
      .eq("entity_id", inquiryId)
      .order("created_at", { ascending: false })
      .limit(30),
  ]);

  return { inquiry, links: check(links), notes: check(notes), activity: check(activity) };
}

/** Admin settings lists, including inactive rows (RLS shows them only to admins). */
export async function getSettingsLists() {
  const supabase = await createClient();
  const [services, budgets] = await Promise.all([
    supabase.from("service_types").select("code, label, active, sort_order").order("sort_order"),
    supabase
      .from("budget_ranges")
      .select("id, label, min_amount, max_amount, currency, active, sort_order")
      .order("sort_order"),
  ]);
  return { services: check(services), budgets: check(budgets) };
}

/** Count of inquiries waiting for a first look, for the admin overview. */
export async function countNewInquiries() {
  const supabase = await createClient();
  const { count, error } = await supabase
    .from("client_inquiries")
    .select("id", { count: "exact", head: true })
    .eq("status", "new");
  if (error) throw error;
  return count ?? 0;
}
