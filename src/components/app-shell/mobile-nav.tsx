"use client";

import { Menu } from "lucide-react";
import Link from "next/link";
import { useState, type ReactNode } from "react";

import { Button } from "@/components/ui/button";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { Wordmark } from "@/components/wordmark";

import { NavLinks, type NavEntry } from "./nav-links";

// Phone and tablet navigation: a top bar with a menu button that opens the same links in a sheet.
export function MobileNav({
  area,
  items,
  homeHref,
  bell,
  userMenu,
}: {
  area: string;
  items: NavEntry[];
  /** The signed-in user's own dashboard (the logo link). */
  homeHref: string;
  /** Server-rendered notification link (an element, not a function). */
  bell?: ReactNode;
  /** Server-rendered account menu (an element, not a function). */
  userMenu?: ReactNode;
}) {
  const [open, setOpen] = useState(false);

  return (
    <div className="bg-background sticky top-0 z-40 flex items-center justify-between gap-3 border-b px-4 py-2 lg:hidden">
      <Link
        href={homeHref}
        aria-label="EDITSTATION dashboard"
        className="focus-visible:ring-ring min-w-0 shrink rounded-md focus-visible:ring-2 focus-visible:outline-none"
      >
        <Wordmark />
      </Link>
      <div className="flex shrink-0 items-center gap-1">
        {bell}
        {userMenu}
        <Button
          variant="outline"
          className="min-h-11 min-w-11"
          onClick={() => setOpen(true)}
          aria-label={`Open ${area} menu`}
        >
          <Menu aria-hidden />
          {/* Icon only on the narrowest phones so the bar fits 375px with the account menu. */}
          <span className="max-[420px]:sr-only">Menu</span>
        </Button>
      </div>
      <Sheet open={open} onOpenChange={setOpen}>
        <SheetContent side="left" showCloseButton>
          <SheetHeader>
            <SheetTitle>{area}</SheetTitle>
            <SheetDescription className="sr-only">Navigate this area</SheetDescription>
          </SheetHeader>
          <div className="grid gap-4 px-4 pb-4">
            <NavLinks items={items} label={area} onNavigate={() => setOpen(false)} />
            <Link
              href="/"
              className="text-muted-foreground hover:text-foreground focus-visible:ring-ring flex min-h-11 items-center rounded-md px-3 text-sm focus-visible:ring-2 focus-visible:outline-none"
            >
              Public site
            </Link>
          </div>
        </SheetContent>
      </Sheet>
    </div>
  );
}
