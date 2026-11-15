import "server-only";

import { createClient } from "@/lib/supabase/server";

/**
 * Runs the timed rules (Phase 12C: the unpaid-deposit auto-hold) as the signed-in admin. Called
 * when the admin dashboard and /admin/earnings load, as the local backstop for pg_cron. Cheap and
 * idempotent; a failure must never break the page, so errors are swallowed (code only is logged).
 */
export async function runTimedRules(): Promise<void> {
  try {
    const supabase = await createClient();
    const { error } = await supabase.rpc("admin_run_timed_rules");
    if (error) console.warn("timed rules skipped", error.code);
  } catch {
    console.warn("timed rules skipped");
  }
}
