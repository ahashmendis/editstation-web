import { Bell } from "lucide-react";
import Link from "next/link";
import { Suspense } from "react";

import { cn } from "@/lib/utils";

import { unreadBadge } from "../constants";
import { countUnreadNotifications } from "../queries";

const linkClass =
  "text-muted-foreground hover:text-foreground hover:bg-muted focus-visible:ring-ring relative inline-flex min-h-11 min-w-11 items-center justify-center gap-2 rounded-md px-2 text-sm focus-visible:ring-2 focus-visible:outline-none";

/**
 * Link to /notifications with the unread count. The count is a per-request read, so it streams
 * in its own Suspense boundary and never blocks the shell.
 */
export function NotificationBell({ withLabel = false }: { withLabel?: boolean }) {
  return (
    <Suspense fallback={<BellLink count={0} withLabel={withLabel} />}>
      <BellWithCount withLabel={withLabel} />
    </Suspense>
  );
}

async function BellWithCount({ withLabel }: { withLabel: boolean }) {
  const count = await countUnreadNotifications();
  return <BellLink count={count} withLabel={withLabel} />;
}

/** Unread count pill for a nav row. Streams in its own Suspense boundary; renders nothing at 0. */
export function UnreadNavBadge() {
  return (
    <Suspense fallback={null}>
      <UnreadNavBadgeCount />
    </Suspense>
  );
}

async function UnreadNavBadgeCount() {
  const badge = unreadBadge(await countUnreadNotifications());
  if (!badge) return null;
  return (
    <span className="bg-primary text-primary-foreground ml-auto min-w-5 rounded-full px-1 text-center text-[11px] leading-5 font-semibold tabular-nums">
      {badge}
      <span className="sr-only"> unread</span>
    </span>
  );
}

function BellLink({ count, withLabel }: { count: number; withLabel: boolean }) {
  const badge = unreadBadge(count);
  const label = count === 0 ? "Notifications" : `Notifications, ${count} unread`;
  return (
    <Link
      href="/notifications"
      aria-label={label}
      className={cn(linkClass, withLabel && "justify-start gap-3 px-3")}
    >
      <Bell aria-hidden className="size-5" />
      {withLabel ? <span>Notifications</span> : null}
      {badge ? (
        <span
          aria-hidden
          className="bg-primary text-primary-foreground absolute top-1 right-0 min-w-5 rounded-full px-1 text-center text-[11px] leading-5 font-semibold tabular-nums"
        >
          {badge}
        </span>
      ) : null}
    </Link>
  );
}
