import { EmptyState } from "@/components/empty-state";
import { formatDateTime } from "@/features/applications/components/status-badge";
import { activityLabel } from "@/lib/activity-labels";

import type { AdminPaymentDetail } from "../queries";

/** Audit history of one payment (activity_logs, newest first). */
export function PaymentHistory({ activity }: { activity: AdminPaymentDetail["activity"] }) {
  if (activity.length === 0) return <EmptyState title="No history yet." />;
  return (
    <ol className="grid gap-2 text-sm">
      {activity.map((entry) => (
        <li key={entry.id} className="flex flex-wrap justify-between gap-x-4 gap-y-1">
          <span>
            {activityLabel(entry.action)}
            {entry.actor ? <span className="text-muted-foreground"> · {entry.actor}</span> : null}
          </span>
          <span className="text-muted-foreground tabular-nums">
            {formatDateTime(entry.createdAt)}
          </span>
        </li>
      ))}
    </ol>
  );
}
