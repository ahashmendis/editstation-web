import Link from "next/link";

import { StatusPill } from "@/components/status-pill";

import { UNPAID_STATUSES } from "../constants";
import type { AdminPaymentRow } from "../queries";
import { colomboDay } from "../summary";
import { Money } from "./money";
import { PaymentStatusPill } from "./payment-status-pill";

const isOverdue = (row: AdminPaymentRow, today: string) =>
  UNPAID_STATUSES.includes(row.status) && row.dueDate !== null && row.dueDate < today;

/** Payments as a table from `sm` up and as row cards below it. */
export function AdminPaymentsTable({ rows, now }: { rows: AdminPaymentRow[]; now: Date }) {
  const today = colomboDay(now);
  return (
    <>
      <ul className="grid gap-3 sm:hidden">
        {rows.map((row) => (
          <li key={row.id} className="grid gap-1 border-t pt-3 text-sm first:border-t-0 first:pt-0">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <Link
                href={`/admin/earnings/${row.id}`}
                className="font-medium break-words underline"
              >
                {row.projectTitle}
              </Link>
              <PaymentStatusPill status={row.status} kind={row.kind} />
            </div>
            <p className="text-muted-foreground">{row.editorName}</p>
            <p className="font-medium">
              <Money amount={row.amount} currency={row.currency} />
            </p>
            <p className="text-muted-foreground flex flex-wrap items-center gap-2 tabular-nums">
              {row.dueDate ? <span>Due {row.dueDate}</span> : null}
              {isOverdue(row, today) ? <StatusPill tone="warning">Overdue</StatusPill> : null}
              {row.transferDate ? <span>Paid {row.transferDate}</span> : null}
            </p>
          </li>
        ))}
      </ul>
      <table className="hidden w-full text-left text-sm sm:table">
        <thead className="text-muted-foreground">
          <tr>
            <th className="py-2 pr-4 font-medium">Project</th>
            <th className="py-2 pr-4 font-medium">Editor</th>
            <th className="py-2 pr-4 font-medium">Amount</th>
            <th className="py-2 pr-4 font-medium">Status</th>
            <th className="py-2 pr-4 font-medium">Due</th>
            <th className="py-2 font-medium">Paid</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.id} className="border-t align-top">
              <td className="py-2 pr-4">
                <Link href={`/admin/earnings/${row.id}`} className="underline">
                  {row.projectTitle}
                </Link>
              </td>
              <td className="py-2 pr-4">{row.editorName}</td>
              <td className="py-2 pr-4 whitespace-nowrap">
                <Money amount={row.amount} currency={row.currency} />
              </td>
              <td className="py-2 pr-4">
                <PaymentStatusPill status={row.status} kind={row.kind} />
              </td>
              <td className="py-2 pr-4 tabular-nums">
                <div className="flex flex-wrap items-center gap-2">
                  {row.dueDate ?? "—"}
                  {isOverdue(row, today) ? <StatusPill tone="warning">Overdue</StatusPill> : null}
                </div>
              </td>
              <td className="py-2 tabular-nums">{row.transferDate ?? "—"}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </>
  );
}
