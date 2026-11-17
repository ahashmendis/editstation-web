import { Suspense, type ReactNode } from "react";

import { Loading } from "@/components/auth-shell";
import { requireApplicant } from "@/lib/auth/access";
import { NO_INDEX } from "@/lib/seo/site";
import type { Metadata } from "next";

// Private area: never indexed (access control is sign-in, MFA for admins, and RLS).
export const metadata: Metadata = { robots: NO_INDEX };

// Applicant area: any signed-in account that is not an admin or an active editor.
// UI gate only; RLS is the real boundary.
export default function ApplyLayout({ children }: { children: ReactNode }) {
  return (
    <Suspense fallback={<Loading />}>
      <ApplicantGate>{children}</ApplicantGate>
    </Suspense>
  );
}

async function ApplicantGate({ children }: { children: ReactNode }) {
  await requireApplicant();
  return children;
}
