import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { EmptyState } from "@/components/empty-state";
import { Card, CardContent } from "@/components/ui/card";
import { formatDateTime } from "@/features/applications/components/status-badge";
import {
  MarkAllReadButton,
  MarkReadButton,
} from "@/features/notifications/components/mark-read-buttons";
import { notificationHref } from "@/features/notifications/constants";
import { listNotifications } from "@/features/notifications/queries";
import { homePathFor, requireSignedIn } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Notifications · EDITSTATION" };

// Any signed-in account (admin, editor, applicant). RLS returns only the caller's own rows.
export default function NotificationsPage() {
  return (
    <Suspense fallback={<Loading />}>
      <NotificationsContent />
    </Suspense>
  );
}

async function NotificationsContent() {
  const access = await requireSignedIn();
  const rows = await listNotifications();
  const unread = rows.filter((n) => n.read_at === null).length;

  return (
    <AreaShell
      title="Notifications"
      subtitle={unread === 0 ? "You're all caught up." : `${unread} unread`}
      actions={
        <Link
          href={homePathFor(access)}
          className="hover:bg-muted focus-visible:ring-ring inline-flex min-h-11 items-center rounded-md border px-3 text-sm focus-visible:ring-2 focus-visible:outline-none"
        >
          Back to workspace
        </Link>
      }
    >
      {unread > 0 ? <MarkAllReadButton /> : null}
      <Card>
        <CardContent>
          {rows.length === 0 ? (
            <EmptyState title="No notifications yet">
              Updates about your work appear here, such as new requests, decisions and payments.
            </EmptyState>
          ) : (
            <ul className="divide-y">
              {rows.map((n) => {
                const isUnread = n.read_at === null;
                return (
                  <li key={n.id} className="flex flex-wrap items-start justify-between gap-3 py-3">
                    <div className="grid min-w-0 flex-1 gap-1">
                      <p className="flex flex-wrap items-center gap-2 text-sm">
                        {isUnread ? (
                          <span className="bg-primary/15 text-primary rounded px-1.5 py-0.5 text-xs font-medium">
                            Unread
                          </span>
                        ) : null}
                        <Link
                          href={notificationHref(n)}
                          className={
                            isUnread
                              ? "font-semibold break-words underline-offset-4 hover:underline"
                              : "break-words underline-offset-4 hover:underline"
                          }
                        >
                          {n.title}
                        </Link>
                      </p>
                      <p className="text-muted-foreground text-sm break-words">{n.body}</p>
                      <p className="text-muted-foreground text-xs tabular-nums">
                        {formatDateTime(n.created_at)}
                      </p>
                    </div>
                    {isUnread ? <MarkReadButton id={n.id} title={n.title} /> : null}
                  </li>
                );
              })}
            </ul>
          )}
        </CardContent>
      </Card>
    </AreaShell>
  );
}
