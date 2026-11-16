import "server-only";

import { createClient } from "@/lib/supabase/server";
import type { Database } from "@/lib/supabase/database.types";

type Fns = Database["public"]["Functions"];
export type EditorOpportunity = Fns["editor_list_opportunities"]["Returns"][number];
export type AdminInterest = Fns["admin_list_interests"]["Returns"][number];
export type AdminOpportunity = Database["public"]["Tables"]["project_opportunities"]["Row"];

/**
 * Open opportunities for the signed-in active editor: the summary projection only (the database
 * function returns an allow-list of columns), plus the editor's own latest interest on each.
 */
export async function listMyOpportunities(): Promise<EditorOpportunity[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("editor_list_opportunities");
  if (error) throw error;
  return data ?? [];
}

/** The project's opportunity (if published) and every interest on it, in one call. Admin only. */
export async function getAdminOpportunity(
  projectId: string,
): Promise<{ opportunity: AdminOpportunity | null; interests: AdminInterest[] }> {
  const supabase = await createClient();
  // One round trip; the API role cannot read project_id/published_by/closed_by directly.
  const { data, error } = await supabase.rpc("admin_get_opportunity", { p_project_id: projectId });
  if (error) throw error;
  const result = data as {
    opportunity: AdminOpportunity | null;
    interests: AdminInterest[];
  } | null;
  return { opportunity: result?.opportunity ?? null, interests: result?.interests ?? [] };
}
