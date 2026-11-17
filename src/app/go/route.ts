import { NextResponse, type NextRequest } from "next/server";

import { getAccess, homePathFor } from "@/lib/auth/access";

// Signed-in visitors who open the public home page are sent here by src/proxy.ts. It resolves where
// each kind of account belongs (admin, active editor, applicant) and redirects there. A session
// whose account no longer exists goes to sign-in, never back to "/" (that would loop).
export async function GET(request: NextRequest) {
  const access = await getAccess();
  const target = access ? homePathFor(access) : "/sign-in";
  const response = NextResponse.redirect(new URL(target, request.url));
  response.headers.set("Cache-Control", "private, no-store");
  return response;
}
