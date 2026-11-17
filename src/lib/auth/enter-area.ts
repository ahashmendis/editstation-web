/**
 * Where "Public site" links point. "/" sends signed-in users to their own area, so these links use
 * a path that serves the same public home page for everyone (rewritten in next.config.ts).
 */
export const PUBLIC_SITE_PATH = "/site";

/** True when a signed-in visitor opened the public home page and should land in their own area. */
export function shouldEnterArea(pathname: string, isSignedIn: boolean): boolean {
  return isSignedIn && pathname === "/";
}
