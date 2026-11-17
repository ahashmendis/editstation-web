import { Suspense, type ReactNode } from "react";

import { AppShell } from "@/components/app-shell/app-shell";
import type { NavEntry } from "@/components/app-shell/nav-links";
import { Loading } from "@/components/auth-shell";
import { UnreadNavBadge } from "@/features/notifications/components/notification-bell";
import { requireActiveEditor } from "@/lib/auth/access";
import { NO_INDEX } from "@/lib/seo/site";
import type { Metadata } from "next";

// Private area: never indexed (access control is sign-in, MFA for admins, and RLS).
export const metadata: Metadata = { robots: NO_INDEX };

// Grouped navigation. Only routes that exist are listed (no calendar, support or AI yet).
const EDITOR_NAV: NavEntry[] = [
  {
    group: "Workspace",
    items: [
      { href: "/editor", label: "Dashboard", icon: "dashboard", exact: true },
      { href: "/editor/projects", label: "My projects", icon: "projects" },
      { href: "/editor/opportunities", label: "Opportunities", icon: "opportunities" },
    ],
  },
  {
    group: "Production",
    items: [{ href: "/editor/feedback", label: "Feedback & revisions", icon: "feedback" }],
  },
  {
    group: "Financials",
    items: [{ href: "/editor/earnings", label: "Earnings", icon: "earnings" }],
  },
  {
    group: "Account",
    items: [
      { href: "/editor/profile", label: "Profile", icon: "profile" },
      {
        href: "/notifications",
        label: "Notifications",
        icon: "notifications",
        badge: <UnreadNavBadge />,
      },
    ],
  },
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
    <AppShell area="Editor" items={EDITOR_NAV} homeHref="/editor" profileHref="/editor/profile">
      {children}
    </AppShell>
  );
}
