import "server-only";

import { createClient } from "@/lib/supabase/server";

import type { DashboardMetrics } from "./constants";

/** Admin-only (the function requires an MFA admin session and raises ES403 otherwise). */
export async function getDashboardMetrics(): Promise<DashboardMetrics> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_dashboard_metrics");
  if (error) throw error;
  return data as unknown as DashboardMetrics;
}
