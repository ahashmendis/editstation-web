import { StatusPill } from "@/components/status-pill";

import {
  clientStatus,
  formatAmount,
  formatDay,
  milestoneKindLabel,
  paymentStatus,
} from "../constants";
import type { ClientMilestone } from "../schemas";

/** Client-facing project status: words plus a dot (never colour alone). */
export function ClientStatusPill({ status }: { status: string }) {
  const s = clientStatus(status);
  return <StatusPill tone={s.tone}>{s.label}</StatusPill>;
}

export function PaymentStatusPill({ status }: { status: string }) {
  const s = paymentStatus(status);
  return <StatusPill tone={s.tone}>{s.label}</StatusPill>;
}

/** One project's payment milestones (deposit, balance...) with their status. */
export function MilestoneList({ milestones }: { milestones: ClientMilestone[] }) {
  return (
    <ul className="divide-y">
      {milestones.map((m) => {
        const due = formatDay(m.due_date);
        const received = formatDay(m.received_at);
        return (
          <li key={m.id} className="flex flex-wrap items-start justify-between gap-3 py-3">
            <div className="grid min-w-0 gap-0.5">
              <p className="text-sm font-medium">
                {milestoneKindLabel(m.kind)}:{" "}
                <span className="tabular-nums">{formatAmount(m.amount, m.currency)}</span>
              </p>
              <p className="text-muted-foreground text-xs">
                {received
                  ? `Received ${received}`
                  : due
                    ? `Due ${due}`
                    : m.invoice_issued_at
                      ? "Invoiced"
                      : "The studio will invoice this later"}
              </p>
            </div>
            <PaymentStatusPill status={m.payment_status} />
          </li>
        );
      })}
    </ul>
  );
}

/** Studio bank transfer details, shown only when the admin has set them. */
export function BankDetailsPanel({ details }: { details: string }) {
  return (
    <div className="grid gap-2">
      <p className="text-sm">Bank transfer details provided by the studio:</p>
      <pre className="bg-muted rounded-md p-3 font-sans text-sm break-words whitespace-pre-wrap">
        {details}
      </pre>
    </div>
  );
}
