import { Suspense, type ReactNode } from "react";

import { AppShell } from "@/components/app-shell/app-shell";
import type { NavItem } from "@/components/app-shell/nav-links";
import { Loading } from "@/components/auth-shell";
import { requireAdmin } from "@/lib/auth/access";

const ADMIN_NAV: NavItem[] = [
  { href: "/admin", label: "Overview", icon: "dashboard", exact: true },
  { href: "/admin/inquiries", label: "Inquiries", icon: "inquiries" },
  { href: "/admin/projects", label: "Projects", icon: "projects" },
  { href: "/admin/earnings", label: "Earnings", icon: "earnings" },
  { href: "/admin/clients", label: "Clients", icon: "clients" },
  { href: "/admin/access-review", label: "Access review", icon: "access" },
  { href: "/admin/applications", label: "Applications", icon: "applications" },
  { href: "/admin/settings", label: "Settings", icon: "settings" },
];

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
    <AppShell area="Admin" items={ADMIN_NAV}>
      {children}
    </AppShell>
  );
}
