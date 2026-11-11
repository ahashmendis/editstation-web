import { Suspense, type ReactNode } from "react";

import { Loading } from "@/components/auth-shell";
import { requireApplicant } from "@/lib/auth/access";

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
