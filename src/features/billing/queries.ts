import "server-only";

import { createClient } from "@/lib/supabase/server";

import { DEFAULT_BUSINESS_TIMEZONE, businessToday, type MilestoneRow } from "./constants";

/** The business timezone admin setting (RLS: MFA admins only). */
export async function getBusinessTimezone(): Promise<string> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("app_settings")
    .select("value")
    .eq("key", "business_timezone")
    .maybeSingle();
  if (error) throw error;
  return typeof data?.value === "string" ? data.value : DEFAULT_BUSINESS_TIMEZONE;
}

/** Current (not replaced) client milestones of a project, admin only (RLS). */
export async function getClientBilling(projectId: string) {
  const supabase = await createClient();
  const [milestones, timezone] = await Promise.all([
    supabase
      .from("client_milestones")
      .select(
        "id, seq, kind, share_percent, amount, currency, invoice_issued_at, due_date, received_at, transfer_reference, verification_status, verified_at, auto_held_at, due_change_reason, correction_reason",
      )
      .eq("project_id", projectId)
      .is("voided_at", null)
      .order("seq"),
    getBusinessTimezone(),
  ]);
  if (milestones.error) throw milestones.error;
  return {
    milestones: milestones.data as MilestoneRow[],
    timezone,
    today: businessToday(timezone),
  };
}
