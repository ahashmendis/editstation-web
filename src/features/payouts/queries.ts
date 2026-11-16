import "server-only";

import { createClient } from "@/lib/supabase/server";

import {
  adminPayoutSchema,
  editorPayoutSchema,
  type AdminPayout,
  type EditorPayout,
} from "./schemas";

/** The signed-in editor's own payout details (account number masked). Active editors only. */
export async function getMyPayout(): Promise<EditorPayout> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("editor_get_payout_details");
  if (error) throw error;
  return editorPayoutSchema.parse(data);
}

/** One editor's payout details (masked), verification, attestation and mark-paid status. Admin only. */
export async function getAdminPayout(editorId: string): Promise<AdminPayout | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_get_payout_details_masked", {
    p_editor_id: editorId,
  });
  if (error?.code === "ES422") return null; // not an editor
  if (error) throw error;
  return adminPayoutSchema.parse(data);
}

/** The payout_details_enabled flag (admin-only RLS on app_settings). */
export async function getPayoutEnabled(): Promise<boolean> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("app_settings")
    .select("value")
    .eq("key", "payout_details_enabled")
    .maybeSingle();
  if (error) throw error;
  return data?.value === true;
}
