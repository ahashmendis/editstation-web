import Link from "next/link";
import type { ReactNode } from "react";

import { Wordmark } from "@/components/wordmark";
import { NotificationBell } from "@/features/notifications/components/notification-bell";
import { UserMenu } from "@/features/profile/components/user-menu";

import { MobileNav } from "./mobile-nav";
import { NavLinks, type NavEntry } from "./nav-links";
import { isNavGroup } from "./nav-sections";

// Shared shell for the signed-in work areas (admin and editor): sidebar on large screens, top bar
// with a menu sheet on small ones. Navigation only; pages keep their own heading via AreaShell.
// This is layout, not a gate: access is enforced by each area's layout, the database and RLS.
export function AppShell({
  area,
  items,
  homeHref,
  profileHref,
  children,
}: {
  area: string;
  /** Plain items, or labelled groups (each group renders under its own heading). */
  items: NavEntry[];
  /** The signed-in user's own dashboard: the logo links here, never to the public site. */
  homeHref: string;
  /** Where the user manages their own picture (linked from the account menu). */
  profileHref: string;
  children: ReactNode;
}) {
  // The sidebar bell is only for areas whose nav has no Notifications row of its own.
  const hasNotificationsItem = items.some((entry) =>
    isNavGroup(entry)
      ? entry.items.some((item) => item.href === "/notifications")
      : entry.href === "/notifications",
  );
  return (
    <div data-app-shell className="flex min-h-full flex-1 flex-col lg:flex-row">
      <aside className="bg-sidebar text-sidebar-foreground hidden w-60 shrink-0 border-r lg:block">
        <div className="sticky top-0 flex h-svh flex-col gap-6 overflow-y-auto p-4">
          <div className="grid gap-1 px-3 pt-2">
            <Link
              href={homeHref}
              aria-label="EDITSTATION dashboard"
              className="focus-visible:ring-ring rounded-md focus-visible:ring-2 focus-visible:outline-none"
            >
              <Wordmark />
            </Link>
            <p className="text-muted-foreground text-sm">{area}</p>
          </div>
          <NavLinks items={items} label={area} />
          {hasNotificationsItem ? null : <NotificationBell withLabel />}
          <UserMenu profileHref={profileHref} withLabel />
          <Link
            href="/"
            className="text-muted-foreground hover:text-foreground focus-visible:ring-ring mt-auto rounded-md px-3 py-2 text-sm focus-visible:ring-2 focus-visible:outline-none"
          >
            Public site
          </Link>
        </div>
      </aside>
      <div className="flex min-w-0 flex-1 flex-col">
        <MobileNav
          area={area}
          items={items}
          homeHref={homeHref}
          bell={<NotificationBell />}
          userMenu={<UserMenu profileHref={profileHref} />}
        />
        {children}
      </div>
    </div>
  );
}
