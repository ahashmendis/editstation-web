/**
 * Where a signed-in account belongs. Pure (no server imports) so it can be unit tested.
 *
 * Order matters: an admin account first (MFA screen until verified), then a client account
 * (client_users membership), then editor access. Every account has an editor_profiles row from the
 * sign-up trigger (status none), so the client check must come before the editor fallback or a
 * client would be sent to /apply. The database guarantees an account is never both a client and
 * an admin or active editor (guard triggers in the client area migration).
 */
export type ClientStatus = "active" | "revoked" | null;

export type RoutingAccess = {
  isAdminAccount: boolean;
  aal: "aal1" | "aal2";
  clientStatus: ClientStatus;
  editorAccessStatus: string;
};

export const CLIENT_HOME = "/client";
export const CLIENT_ACCESS_ENDED = "/client/access-ended";
export const CLIENT_SIGN_IN = "/client/sign-in";

export function homePathFor(access: RoutingAccess): string {
  if (access.isAdminAccount) return access.aal === "aal2" ? "/admin" : "/mfa";
  if (access.clientStatus === "active") return CLIENT_HOME;
  if (access.editorAccessStatus === "active") return "/editor";
  // A former client user (all access removed) is told so, never offered an editor application.
  if (access.clientStatus === "revoked") return CLIENT_ACCESS_ENDED;
  return "/apply";
}

/** Normalises the my_client_status() result. Anything unexpected reads as "not a client". */
export function toClientStatus(value: unknown): ClientStatus {
  return value === "active" || value === "revoked" ? value : null;
}

/** Paths under /client that a signed-out visitor may open (everything else needs a session). */
export function isPublicClientPath(pathname: string): boolean {
  return pathname === CLIENT_SIGN_IN;
}

/** True for /client and anything below it. */
export function isClientPath(pathname: string): boolean {
  return pathname === CLIENT_HOME || pathname.startsWith(`${CLIENT_HOME}/`);
}
