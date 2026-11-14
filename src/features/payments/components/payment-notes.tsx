import { EmptyState } from "@/components/empty-state";
import { formatDateTime } from "@/features/applications/components/status-badge";

import type { AdminPaymentDetail } from "../queries";

/** Admin-only notes log, newest first. */
export function PaymentNotes({ notes }: { notes: AdminPaymentDetail["notes"] }) {
  if (notes.length === 0) return <EmptyState title="No notes yet." />;
  return (
    <ul className="grid gap-3 text-sm">
      {notes.map((n) => (
        <li key={n.id} className="grid gap-1 border-t pt-3 first:border-t-0 first:pt-0">
          <p className="text-muted-foreground text-xs">
            {n.author} · {formatDateTime(n.createdAt)}
          </p>
          <p className="break-words whitespace-pre-wrap">{n.note}</p>
        </li>
      ))}
    </ul>
  );
}
