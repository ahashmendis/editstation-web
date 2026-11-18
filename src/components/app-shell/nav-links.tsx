"use client";

import {
  Bell,
  Briefcase,
  ClipboardCheck,
  FolderKanban,
  FolderPlus,
  History,
  Inbox,
  LayoutDashboard,
  MessageSquareText,
  Receipt,
  Settings,
  UserRound,
  ShieldCheck,
  Users,
  Wallet,
} from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useId, type ReactNode } from "react";

import { cn } from "@/lib/utils";

import { isMostSpecificCurrent } from "./is-current";
import { isNavGroup, toSections, type BaseNavItem, type NavGroup } from "./nav-sections";

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
  feedback: MessageSquareText,
  notifications: Bell,
  payments: Receipt,
  newProject: FolderPlus,
} as const;

export type NavIcon = keyof typeof ICONS;
/** `badge` is a server-rendered element (for example an unread count) shown at the row end. */
export type NavItem = BaseNavItem<NavIcon> & { badge?: ReactNode };
export type NavEntry = NavItem | NavGroup<NavItem>;
export function NavLinks({
  items,
  label,
  onNavigate,
}: {
  items: NavEntry[];
  label: string;
  onNavigate?: () => void;
}) {
  const pathname = usePathname();
  const id = useId();
  const allItems = items.flatMap((entry) => (isNavGroup(entry) ? entry.items : [entry]));

  const list = (sectionItems: NavItem[], labelledBy?: string) => (
    <ul className="grid gap-1" aria-labelledby={labelledBy}>
      {sectionItems.map((item) => {
        const Icon = ICONS[item.icon];
        const current = isMostSpecificCurrent(pathname, item, allItems);
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
              {item.badge}
            </Link>
          </li>
        );
      })}
    </ul>
  );

  return (
    <nav aria-label={label} className="grid gap-4">
      {toSections(items).map((section, i) =>
        section.title ? (
          <div key={section.title} className="grid gap-1">
            <p
              id={`${id}-${i}`}
              className="text-muted-foreground px-3 text-xs font-medium tracking-wide uppercase"
            >
              {section.title}
            </p>
            {list(section.items, `${id}-${i}`)}
          </div>
        ) : (
          <div key={`plain-${i}`}>{list(section.items)}</div>
        ),
      )}
    </nav>
  );
}
