import "server-only";

import { redirect } from "next/navigation";
import { cache } from "react";

import type { Database } from "@/lib/supabase/database.types";
import { createClient } from "@/lib/supabase/server";

export type EditorAccessStatus = Database["public"]["Enums"]["editor_access_status"];

export type Access = {
  userId: string;
  email: string | null;
  /** Has a non-revoked admin_users row. Routing only; authorisation also needs MFA. */
  isAdminAccount: boolean;
  /** Session assurance level: aal2 means MFA was verified in this session. */
  aal: "aal1" | "aal2";
  editorAccessStatus: EditorAccessStatus;
};

/**
 * Data Access Layer: who is the current user and what may they reach?
 * Reads only the user's own rows, through RLS. Memoised per request, never cached
 * across requests, so suspension or revocation applies on the next request.
 */
export const getAccess = cache(async (): Promise<Access | null> => {
  const supabase = await createClient();
  const { data, error } = await supabase.auth.getClaims();
  const claims = data?.claims;
  if (error || !claims?.sub) return null;

  const [admin, editor] = await Promise.all([
    supabase.from("admin_users").select("revoked_at").eq("user_id", claims.sub).maybeSingle(),
    supabase
      .from("editor_profiles")
      .select("access_status")
      .eq("user_id", claims.sub)
      .maybeSingle(),
  ]);
  if (admin.error) throw admin.error;
  if (editor.error) throw editor.error;

  // Every real account has an editor_profiles row (sign-up trigger). No row means the token
  // outlived its account (deleted user, or a reset local DB): treat as signed out.
  if (!editor.data) return null;

  return {
    userId: claims.sub,
    email: typeof claims.email === "string" ? claims.email : null,
    isAdminAccount: Boolean(admin.data && admin.data.revoked_at === null),
    aal: claims.aal === "aal2" ? "aal2" : "aal1",
    editorAccessStatus: editor.data.access_status,
  };
});

/** Where a signed-in user belongs. */
export function homePathFor(access: Access): string {
  if (access.isAdminAccount) return access.aal === "aal2" ? "/admin" : "/mfa";
  if (access.editorAccessStatus === "active") return "/editor";
  return "/apply";
}

export async function requireSignedIn(): Promise<Access> {
  const access = await getAccess();
  if (!access) redirect("/sign-in");
  return access;
}

/** Any signed-in account that is neither an admin nor an active editor. */
export async function requireApplicant(): Promise<Access> {
  const access = await requireSignedIn();
  const home = homePathFor(access);
  if (home !== "/apply") redirect(home);
  return access;
}

export async function requireActiveEditor(): Promise<Access> {
  const access = await requireSignedIn();
  if (access.isAdminAccount || access.editorAccessStatus !== "active") {
    redirect(homePathFor(access));
  }
  return access;
}

/** Admin account, MFA not necessarily verified yet. For the MFA screens only. */
export async function requireAdminAccount(): Promise<Access> {
  const access = await requireSignedIn();
  if (!access.isAdminAccount) redirect(homePathFor(access));
  return access;
}

/** Admin with an MFA-verified session (decision A). Mirrors private.is_admin(). */
export async function requireAdmin(): Promise<Access> {
  const access = await requireAdminAccount();
  if (access.aal !== "aal2") redirect("/mfa");
  return access;
}
