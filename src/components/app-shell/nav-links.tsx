"use client";

import {
  Briefcase,
  ClipboardCheck,
  FolderKanban,
  History,
  Inbox,
  LayoutDashboard,
  Settings,
  UserRound,
  ShieldCheck,
  Users,
  Wallet,
} from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";

import { cn } from "@/lib/utils";

import { isCurrent } from "./is-current";

// Icons are looked up by name because server components cannot pass component functions to
// client components.
const ICONS = {
  dashboard: LayoutDashboard,
  inquiries: Inbox,
  applications: ClipboardCheck,
  projects: FolderKanban,
  clients: Users,
  access: ShieldCheck,
  settings: Settings,
  earnings: Wallet,
  activity: History,
  opportunities: Briefcase,
  profile: UserRound,
} as const;

export type NavIcon = keyof typeof ICONS;
export type NavItem = {
  href: string;
  label: string;
  icon: NavIcon;
  /** Only the exact path is "current" (for an area's overview page). */
  exact?: boolean;
};

export function NavLinks({
  items,
  label,
  onNavigate,
}: {
  items: NavItem[];
  label: string;
  onNavigate?: () => void;
}) {
  const pathname = usePathname();

  return (
    <nav aria-label={label}>
      <ul className="grid gap-1">
        {items.map((item) => {
          const Icon = ICONS[item.icon];
          const current = isCurrent(pathname, item);
          return (
            <li key={item.href}>
              <Link
                href={item.href}
                onClick={onNavigate}
                aria-current={current ? "page" : undefined}
                className={cn(
                  "relative flex min-h-11 items-center gap-3 rounded-md px-3 text-sm transition-colors",
                  "focus-visible:ring-ring focus-visible:ring-2 focus-visible:outline-none",
                  current
                    ? "bg-sidebar-accent text-sidebar-accent-foreground before:bg-primary font-medium before:absolute before:inset-y-2 before:left-0 before:w-0.5 before:rounded-full"
                    : "text-muted-foreground hover:bg-sidebar-accent/60 hover:text-sidebar-accent-foreground",
                )}
              >
                <Icon aria-hidden className="size-4 shrink-0" />
                {item.label}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
