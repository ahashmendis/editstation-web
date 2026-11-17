import "server-only";

import { redirect } from "next/navigation";
import { cache } from "react";

import type { Database } from "@/lib/supabase/database.types";
import { createClient } from "@/lib/supabase/server";

import { homePathFor, toClientStatus, type ClientStatus } from "./home-path";

export { homePathFor } from "./home-path";

export type EditorAccessStatus = Database["public"]["Enums"]["editor_access_status"];

export type Access = {
  userId: string;
  email: string | null;
  /** Has a non-revoked admin_users row. Routing only; authorisation also needs MFA. */
  isAdminAccount: boolean;
  /** Session assurance level: aal2 means MFA was verified in this session. */
  aal: "aal1" | "aal2";
  editorAccessStatus: EditorAccessStatus;
  /** Client area membership: active, revoked (all access removed) or null (not a client). */
  clientStatus: ClientStatus;
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

  const [admin, editor, client] = await Promise.all([
    supabase.from("admin_users").select("revoked_at").eq("user_id", claims.sub).maybeSingle(),
    supabase
      .from("editor_profiles")
      .select("access_status")
      .eq("user_id", claims.sub)
      .maybeSingle(),
    // Clients have no table grants; this function reports only the caller's own membership.
    supabase.rpc("my_client_status"),
  ]);
  if (admin.error) throw admin.error;
  if (editor.error) throw editor.error;
  if (client.error) throw client.error;

  // Every real account has an editor_profiles row (sign-up trigger). No row means the token
  // outlived its account (deleted user, or a reset local DB): treat as signed out.
  if (!editor.data) return null;

  return {
    userId: claims.sub,
    email: typeof claims.email === "string" ? claims.email : null,
    isAdminAccount: Boolean(admin.data && admin.data.revoked_at === null),
    aal: claims.aal === "aal2" ? "aal2" : "aal1",
    editorAccessStatus: editor.data.access_status,
    clientStatus: toClientStatus(client.data),
  };
});

export async function requireSignedIn(): Promise<Access> {
  const access = await getAccess();
  if (!access) redirect("/sign-in");
  return access;
}

/** Any signed-in account that is neither an admin, a client nor an active editor. */
export async function requireApplicant(): Promise<Access> {
  const access = await requireSignedIn();
  const home = homePathFor(access);
  if (home !== "/apply") redirect(home);
  return access;
}

export async function requireActiveEditor(): Promise<Access> {
  const access = await requireSignedIn();
  if (homePathFor(access) !== "/editor") redirect(homePathFor(access));
  return access;
}

/**
 * A client user with active access (UI gate; the client_* database functions re-check the
 * membership on every call, so a revocation applies even to an open page's next request).
 */
export async function requireClient(): Promise<Access> {
  const access = await getAccess();
  if (!access) redirect("/client/sign-in");
  if (homePathFor(access) !== "/client") redirect(homePathFor(access));
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
