import { Suspense, type ReactNode } from "react";

import { AdminNav } from "@/components/admin-nav";
import { Loading } from "@/components/auth-shell";
import { requireAdmin } from "@/lib/auth/access";

// Admin area: admin account AND an MFA-verified (aal2) session (decision A).
// UI gate only; RLS (private.is_admin, which also requires aal2) is the real boundary.
export default function AdminLayout({ children }: { children: ReactNode }) {
  return (
    <Suspense fallback={<Loading />}>
      <AdminGate>{children}</AdminGate>
    </Suspense>
  );
}

async function AdminGate({ children }: { children: ReactNode }) {
  await requireAdmin();
  return (
    <>
      <AdminNav />
      {children}
    </>
  );
}
