import Link from "next/link";
import { Suspense, type ReactNode } from "react";

import { getAccess, homePathFor } from "@/lib/auth/access";

/**
 * Header link for the public home page. Signed-out visitors see "Sign in"; a signed-in user sees
 * a link back to their own area, so they never sign in again (a fresh password sign-in starts a
 * new session at assurance level 1 and would ask an admin for the authenticator code again).
 * The per-request session read sits in Suspense so the rest of the page stays static.
 */
export function HeaderAccountLink({ className }: { className: string }) {
  const signIn = (
    <Link href="/sign-in" className={className}>
      Editor sign-in
    </Link>
  );
  return (
    <Suspense fallback={signIn}>
      <AccountLink signIn={signIn} className={className} />
    </Suspense>
  );
}

async function AccountLink({ signIn, className }: { signIn: ReactNode; className: string }) {
  const access = await getAccess();
  if (!access) return signIn;
  return (
    <Link href={homePathFor(access)} className={className}>
      Open my area
    </Link>
  );
}
