import "server-only";

import { createClient } from "@/lib/supabase/server";

import type { NotificationRow } from "./constants";

// Both read through RLS: a signed-in account only ever sees its own notifications.

export async function countUnreadNotifications(): Promise<number> {
  const supabase = await createClient();
  const { count, error } = await supabase
    .from("notifications")
    .select("id", { count: "exact", head: true })
    .is("read_at", null);
  if (error) throw error;
  return count ?? 0;
}

export async function listNotifications(limit = 100): Promise<NotificationRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("notifications")
    .select("id, kind, entity_type, entity_id, title, body, created_at, read_at")
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) throw error;
  return data;
}
