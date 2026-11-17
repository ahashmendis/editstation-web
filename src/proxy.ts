import type { NextRequest } from "next/server";

import { shouldEnterArea } from "@/lib/auth/enter-area";
import { redirectPreservingSession, updateSession } from "@/lib/supabase/proxy";

// Areas that need a signed-in user. Which kind of user is checked server-side in
// each area's layout and enforced by RLS; this is only an early redirect.
const SIGNED_IN_PREFIXES = [
  "/apply",
  "/editor",
  "/admin",
  "/mfa",
  "/reset-password",
  "/notifications",
];

export async function proxy(request: NextRequest) {
  const { response, isSignedIn } = await updateSession(request);
  const { pathname, search } = request.nextUrl;

  const needsSession = SIGNED_IN_PREFIXES.some(
    (prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`),
  );

  // A signed-in user opening the public home page goes to their own area instead.
  if (shouldEnterArea(pathname, isSignedIn)) {
    const url = request.nextUrl.clone();
    url.pathname = "/go";
    url.search = "";
    return redirectPreservingSession(response, url);
  }

  if (needsSession && !isSignedIn) {
    const url = request.nextUrl.clone();
    url.pathname = "/sign-in";
    url.search = "";
    url.searchParams.set("next", `${pathname}${search}`);
    return redirectPreservingSession(response, url);
  }

  return response;
}

export const config = {
  matcher: [
    // Everything except Next internals and static files.
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)",
  ],
};
