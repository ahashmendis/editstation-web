import "server-only";

import { cache } from "react";

import { requireAdmin, requireSignedIn } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

import { signAvatarPaths } from "./avatar";

export type MyProfileSummary = {
  name: string | null;
  email: string | null;
  avatarPath: string | null;
  avatarUrl: string | null;
};

/**
 * The signed-in user's own name and picture, read through RLS with their own session. Memoised for
 * one request only (React cache), so the header menu and a form on the same page share one signed
 * URL; never cached across requests or users.
 */
export const getMyProfileSummary = cache(async (): Promise<MyProfileSummary> => {
  const access = await requireSignedIn();
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("profiles")
    .select("full_name, email, avatar_path")
    .eq("id", access.userId)
    .maybeSingle();
  if (error) throw error;
  const avatarPath = data?.avatar_path ?? null;
  const urls = await signAvatarPaths(supabase, [avatarPath]);
  return {
    name: data?.full_name ?? null,
    email: data?.email ?? access.email,
    avatarPath,
    avatarUrl: avatarPath ? (urls.get(avatarPath) ?? null) : null,
  };
});

/**
 * Admin only: signed picture URLs for the given accounts, keyed by user id. Runs after
 * requireAdmin(); storage RLS also requires an MFA admin session for other users' pictures.
 */
export async function getAvatarUrlsForUsers(userIds: string[]): Promise<Map<string, string>> {
  await requireAdmin();
  const ids = Array.from(new Set(userIds));
  const result = new Map<string, string>();
  if (ids.length === 0) return result;
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("profiles")
    .select("id, avatar_path")
    .in("id", ids)
    .not("avatar_path", "is", null);
  if (error) throw error;
  const urls = await signAvatarPaths(
    supabase,
    data.map((r) => r.avatar_path),
  );
  for (const row of data) {
    const url = row.avatar_path ? urls.get(row.avatar_path) : undefined;
    if (url) result.set(row.id, url);
  }
  return result;
}
