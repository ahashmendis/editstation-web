import { formatDateTime } from "@/features/applications/components/status-badge";

import { HOLD_LABEL, milestoneLabel } from "../constants";
import type { EditorPaymentRow } from "../queries";
import { Money } from "./money";
import { PaymentStatusPill } from "./payment-status-pill";

/**
 * The editor's own payments as cards (one column at 375px), one per pay milestone. Holds and waits
 * show a fixed label only (KB9a-5): never the admin's reason or any client money.
 */
export function EditorPaymentList({ rows }: { rows: EditorPaymentRow[] }) {
  return (
    <ul className="grid gap-3">
      {rows.map((row) => (
        <li
          key={row.id}
          className="bg-card ring-foreground/10 grid gap-2 rounded-xl p-4 text-sm ring-1"
        >
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div className="grid gap-0.5">
              <p className="font-medium break-words">{row.projectTitle}</p>
              <p className="text-muted-foreground text-xs">
                {milestoneLabel(row.milestoneSeq)}
                {row.splitFromPaymentId ? " · disputed part" : ""}
              </p>
            </div>
            <PaymentStatusPill status={row.status} kind={row.kind} />
          </div>
          <p className="text-lg font-semibold">
            <Money amount={row.amount} currency={row.currency} />
          </p>
          <dl className="text-muted-foreground grid gap-1 sm:grid-cols-2">
            {row.dueDate && row.status !== "paid" ? (
              <div>
                <dt className="inline">Due: </dt>
                <dd className="inline tabular-nums">{row.dueDate}</dd>
              </div>
            ) : null}
            {row.status === "paid" && row.kind === "assignment" ? (
              <>
                <div>
                  <dt className="inline">Paid: </dt>
                  <dd className="inline tabular-nums">
                    {row.transferDate ?? formatDateTime(row.markedPaidAt)}
                  </dd>
                </div>
                {row.transactionReference ? (
                  <div>
                    <dt className="inline">Reference: </dt>
                    <dd className="inline break-all">{row.transactionReference}</dd>
                  </div>
                ) : null}
              </>
            ) : null}
          </dl>
          {row.holdLabel ? (
            <p className="text-sm">
              <span className="font-medium">
                {row.status === "on_hold" ? "On hold: " : "Status: "}
              </span>
              {HOLD_LABEL[row.holdLabel]}
            </p>
          ) : null}
          {row.kind === "reversal" ? (
            <p className="text-sm">
              <span className="font-medium">Status: </span>
              Reversed
            </p>
          ) : null}
        </li>
      ))}
    </ul>
  );
}
