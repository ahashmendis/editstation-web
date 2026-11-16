import { Suspense, type ReactNode } from "react";

import { AppShell } from "@/components/app-shell/app-shell";
import type { NavItem } from "@/components/app-shell/nav-links";
import { Loading } from "@/components/auth-shell";
import { requireActiveEditor } from "@/lib/auth/access";

const EDITOR_NAV: NavItem[] = [
  { href: "/editor", label: "Dashboard", icon: "dashboard", exact: true },
  { href: "/editor/opportunities", label: "Opportunities", icon: "opportunities" },
  { href: "/editor/earnings", label: "Earnings", icon: "earnings" },
];

// Editor area: only accounts with access_status = 'active' (decision L).
// UI gate only; RLS (private.is_active_editor) is the real boundary.
export default function EditorLayout({ children }: { children: ReactNode }) {
  return (
    <Suspense fallback={<Loading />}>
      <EditorGate>{children}</EditorGate>
    </Suspense>
  );
}

async function EditorGate({ children }: { children: ReactNode }) {
  await requireActiveEditor();
  return (
    <AppShell area="Editor" items={EDITOR_NAV}>
      {children}
    </AppShell>
  );
}
