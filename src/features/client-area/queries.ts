import "server-only";

import { createClient } from "@/lib/supabase/server";

import {
  adminClientUpdatesSchema,
  clientPaymentInfoSchema,
  clientProjectSchema,
  clientRequestRowSchema,
  type AdminClientUpdates,
  type ClientPaymentInfo,
  type ClientProject,
  type ClientRequestRow,
} from "./schemas";

// Client reads go only through the client_* database functions (clients have no table grants).
// Each call re-checks the caller's membership, so a revoked user is refused on the next request.

export type ClientProjectRow = {
  id: string;
  title: string;
  client_status: string;
  created_at: string;
  last_update_at: string | null;
};

export async function listClientProjects(): Promise<ClientProjectRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("client_list_projects");
  if (error) throw error;
  return data ?? [];
}

/** Null when the project is not one of the caller's client's (same answer as "does not exist"). */
export async function getClientProject(projectId: string): Promise<ClientProject | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("client_get_project", { p_project_id: projectId });
  if (error) throw error;
  return data === null ? null : clientProjectSchema.parse(data);
}

export async function getClientPaymentInfo(): Promise<ClientPaymentInfo> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("client_get_payment_info");
  if (error) throw error;
  return clientPaymentInfoSchema.parse(data);
}

/** The caller's client's project requests (leads), newest first, client-safe fields only. */
export async function listClientRequests(): Promise<ClientRequestRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("client_list_requests");
  if (error) throw error;
  return clientRequestRowSchema.array().parse(data ?? []);
}

// ---------------------------------------------------------------------------
// Admin (MFA) reads
// ---------------------------------------------------------------------------

export type ClientUserRow = {
  id: string;
  client_id: string;
  user_id: string;
  email: string;
  created_at: string;
  revoked_at: string | null;
  last_sign_in_at: string | null;
};

/** Every client user (active first), for the admin clients page. */
export async function listClientUsers(): Promise<ClientUserRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_list_client_users", {});
  if (error) throw error;
  return data ?? [];
}

export async function getAdminClientUpdates(projectId: string): Promise<AdminClientUpdates> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_list_client_updates", {
    p_project_id: projectId,
  });
  if (error) throw error;
  return adminClientUpdatesSchema.parse(data);
}

/** The studio bank details shown to clients ("" when not set, which hides the panel). */
export async function getBankDetails(): Promise<string> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("app_settings")
    .select("value")
    .eq("key", "client_bank_details")
    .maybeSingle();
  if (error) throw error;
  return typeof data?.value === "string" ? data.value : "";
}
