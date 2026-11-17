"use client";

import Link from "next/link";
import { useTransition } from "react";

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { signOutAction } from "@/features/authentication/actions";
import { cn } from "@/lib/utils";

import { UserAvatar } from "./user-avatar";

export function UserMenuView({
  name,
  email,
  url,
  profileHref,
  withLabel,
}: {
  name: string | null;
  email: string | null;
  url: string | null;
  profileHref?: string;
  withLabel: boolean;
}) {
  const [signingOut, startSignOut] = useTransition();
  const display = name ?? email ?? "Your account";

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        aria-label="Account menu"
        className={cn(
          "hover:bg-muted focus-visible:ring-ring inline-flex min-h-11 min-w-11 items-center justify-center gap-3 rounded-md px-1 text-sm focus-visible:ring-2 focus-visible:outline-none",
          withLabel && "w-full justify-start px-3",
        )}
      >
        <UserAvatar url={url} name={name} email={email} size="sm" />
        {withLabel ? <span className="min-w-0 truncate">{display}</span> : null}
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-60">
        <DropdownMenuGroup>
          <DropdownMenuLabel className="grid gap-0.5">
            <span className="text-foreground truncate font-medium">{display}</span>
            {name && email ? (
              <span className="text-muted-foreground truncate text-xs">{email}</span>
            ) : null}
          </DropdownMenuLabel>
        </DropdownMenuGroup>
        <DropdownMenuSeparator />
        {profileHref ? (
          <DropdownMenuItem className="min-h-11" render={<Link href={profileHref} />}>
            Profile picture
          </DropdownMenuItem>
        ) : null}
        <DropdownMenuItem
          className="min-h-11"
          disabled={signingOut}
          onClick={() => startSignOut(() => signOutAction())}
        >
          {signingOut ? "Signing out…" : "Sign out"}
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
