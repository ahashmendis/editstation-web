import type { Metadata } from "next";
import { Suspense, type ReactNode } from "react";

import { AppShell } from "@/components/app-shell/app-shell";
import type { NavItem } from "@/components/app-shell/nav-links";
import { Loading } from "@/components/auth-shell";
import { requireClient } from "@/lib/auth/access";
import { NO_INDEX } from "@/lib/seo/site";

// Private area: never indexed.
export const metadata: Metadata = { robots: NO_INDEX };

// Client navigation: no editor, notification or profile links (none exist for clients in C1).
const CLIENT_NAV: NavItem[] = [
  { href: "/client", label: "Overview", icon: "dashboard", exact: true },
  { href: "/client/projects", label: "Projects", icon: "projects" },
  { href: "/client/payments", label: "Payments", icon: "payments" },
];

// Client area: an account with an active client_users membership. UI gate only; every client_*
// database function re-checks the membership on each call (the real boundary).
export default function ClientLayout({ children }: { children: ReactNode }) {
  return (
    <Suspense fallback={<Loading />}>
      <ClientGate>{children}</ClientGate>
    </Suspense>
  );
}

async function ClientGate({ children }: { children: ReactNode }) {
  await requireClient();
  return (
    <AppShell area="Client" items={CLIENT_NAV} homeHref="/client" showNotifications={false}>
      {children}
    </AppShell>
  );
}
