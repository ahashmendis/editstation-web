import { EmptyState } from "@/components/empty-state";
import { StatusPill } from "@/components/status-pill";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { AdminActionForm } from "@/features/applications/components/admin-action-form";
import { formatDateTime } from "@/features/applications/components/status-badge";

import {
  correctClientPaymentAction,
  createClientMilestonesAction,
  extendDepositDueAction,
  issueClientInvoiceAction,
  recordClientPaymentAction,
  verifyClientPaymentAction,
} from "../admin-actions";
import {
  MILESTONE_KIND_LABEL,
  VERIFICATION_LABEL,
  VERIFICATION_TONE,
  isOverdue,
  milestoneActions,
  type MilestoneRow,
} from "../constants";
import { BillingForm } from "./billing-form";

function Milestone({
  m,
  projectId,
  today,
  workStarted,
  locked,
  cancelled,
}: {
  m: MilestoneRow;
  projectId: string;
  today: string;
  workStarted: boolean;
  locked: boolean;
  cancelled: boolean;
}) {
  const can = milestoneActions(m, workStarted, cancelled);
  const ids = { projectId, milestoneId: m.id };
  const overdue = isOverdue(m, today);
  return (
    <li className="grid gap-3 border-t pt-3 first:border-t-0 first:pt-0">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="font-medium">
          {m.seq}. {MILESTONE_KIND_LABEL[m.kind]}
          {m.share_percent !== null ? ` (${m.share_percent}%)` : ""}: {m.amount} {m.currency}
        </span>
        <StatusPill tone={VERIFICATION_TONE[m.verification_status]}>
          {VERIFICATION_LABEL[m.verification_status]}
        </StatusPill>
      </div>
      <dl className="grid gap-x-4 gap-y-1 text-sm sm:grid-cols-[auto_1fr]">
        <dt className="text-muted-foreground">Invoice</dt>
        <dd>
          {m.invoice_issued_at ? `Issued ${formatDateTime(m.invoice_issued_at)}` : "Not issued"}
        </dd>
        <dt className="text-muted-foreground">Due</dt>
        <dd>
          {m.due_date ?? "No due date"}
          {overdue ? " (overdue)" : ""}
          {m.due_change_reason ? ` · extended: ${m.due_change_reason}` : ""}
        </dd>
        {m.received_at ? (
          <>
            <dt className="text-muted-foreground">Transfer</dt>
            <dd className="break-words">
              {m.transfer_reference} · {formatDateTime(m.received_at)}
            </dd>
          </>
        ) : null}
        {m.verified_at ? (
          <>
            <dt className="text-muted-foreground">Verified</dt>
            <dd>{formatDateTime(m.verified_at)}</dd>
          </>
        ) : null}
        {m.correction_reason ? (
          <>
            <dt className="text-muted-foreground">Last correction</dt>
            <dd className="break-words">{m.correction_reason}</dd>
          </>
        ) : null}
        {m.auto_held_at ? (
          <>
            <dt className="text-muted-foreground">Auto-hold</dt>
            <dd>
              The project was put on hold on {formatDateTime(m.auto_held_at)} because this deposit
              was overdue. Extend the due date (this releases the hold) or cancel the project.
            </dd>
          </>
        ) : null}
      </dl>
      {locked ? null : (
        <div className="grid gap-4 sm:grid-cols-2">
          {can.issue ? (
            <AdminActionForm
              action={issueClientInvoiceAction}
              submitLabel="Mark invoice issued"
              variant="outline"
              confirm="Record that this invoice was sent to the client today?"
            >
              <input type="hidden" name="projectId" value={projectId} />
              <input type="hidden" name="milestoneId" value={m.id} />
            </AdminActionForm>
          ) : null}
          {can.record ? (
            <BillingForm
              action={recordClientPaymentAction}
              submitLabel={
                m.verification_status === "received_unverified"
                  ? "Update transfer"
                  : "Record transfer"
              }
              idPrefix={`rec-${m.id}`}
              hidden={ids}
              fields={[
                {
                  name: "transferReference",
                  label: m.kind === "refund" ? "Refund transfer reference" : "Transfer reference",
                  defaultValue: m.transfer_reference ?? "",
                },
                {
                  name: "receivedOn",
                  label: "Transfer date",
                  type: "date",
                  hint: "Leave empty for today.",
                },
              ]}
            />
          ) : null}
          {can.verify ? (
            <AdminActionForm
              action={verifyClientPaymentAction}
              submitLabel="Verify transfer"
              confirm="Have you checked the bank and found this transfer? Verified is final."
            >
              <input type="hidden" name="projectId" value={projectId} />
              <input type="hidden" name="milestoneId" value={m.id} />
            </AdminActionForm>
          ) : null}
          {can.extend ? (
            <BillingForm
              action={extendDepositDueAction}
              submitLabel="Extend due date"
              idPrefix={`ext-${m.id}`}
              hidden={ids}
              fields={[
                { name: "dueDate", label: "New due date", type: "date" },
                { name: "reason", label: "Reason for the extension", textarea: true },
              ]}
            />
          ) : null}
          {can.correct ? (
            <BillingForm
              action={correctClientPaymentAction}
              submitLabel="Correct verification"
              idPrefix={`cor-${m.id}`}
              hidden={ids}
              fields={[
                {
                  name: "reason",
                  label: "Reason for the correction",
                  hint: "Only for a mistaken verification. Recorded and audited.",
                  textarea: true,
                },
              ]}
            />
          ) : null}
        </div>
      )}
    </li>
  );
}

/** Admin-only client billing: milestones, invoices, transfers and verification (Phase 12C). */
export function ClientBillingPanel({
  projectId,
  milestones,
  today,
  timezone,
  termsAgreed,
  hasClientPrice,
  workStarted,
  locked,
  cancelled,
}: {
  projectId: string;
  milestones: MilestoneRow[];
  today: string;
  timezone: string;
  termsAgreed: boolean;
  hasClientPrice: boolean;
  workStarted: boolean;
  locked: boolean;
  /** Money still moves after a cancellation (record, verify); nothing new is invoiced. */
  cancelled: boolean;
}) {
  const replaceable =
    !workStarted &&
    milestones.every(
      (m) =>
        (m.kind === "deposit" || m.kind === "balance") &&
        m.invoice_issued_at === null &&
        m.verification_status === "expected",
    );
  const deposit = milestones.find((m) => m.kind === "deposit");
  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-center gap-3">
          <CardTitle>Client billing</CardTitle>
          {deposit ? (
            <StatusPill tone={deposit.verification_status === "verified" ? "success" : "warning"}>
              {deposit.verification_status === "verified"
                ? "Deposit verified"
                : "Deposit not verified"}
            </StatusPill>
          ) : null}
        </div>
        <CardDescription>
          Admin only; editors never see these amounts, only whether work can start. Work cannot
          start until the deposit is verified. Due dates use calendar days in {timezone}.
        </CardDescription>
      </CardHeader>
      <CardContent className="grid gap-6">
        {milestones.length === 0 ? (
          <EmptyState title="No client milestones yet">
            {!termsAgreed
              ? "Agree the project terms first."
              : !hasClientPrice
                ? "Set the client price in the details first."
                : "Create them from the client price below."}
          </EmptyState>
        ) : (
          <ol className="grid gap-4 text-sm">
            {milestones.map((m) => (
              <Milestone
                key={m.id}
                m={m}
                projectId={projectId}
                today={today}
                workStarted={workStarted}
                locked={locked}
                cancelled={cancelled}
              />
            ))}
          </ol>
        )}

        {!locked && !cancelled && replaceable && termsAgreed && hasClientPrice ? (
          <section className="grid gap-2" aria-labelledby="billing-create">
            <h3 id="billing-create" className="font-medium">
              {milestones.length === 0 ? "Create client milestones" : "Replace client milestones"}
            </h3>
            <p className="text-muted-foreground text-sm">
              Shares of the client price in order: the first is the deposit, the rest are balance
              payments; the last takes any rounding remainder. Possible only before an invoice is
              issued and before work starts.
            </p>
            <BillingForm
              action={createClientMilestonesAction}
              submitLabel={milestones.length === 0 ? "Create milestones" : "Replace milestones"}
              idPrefix="create"
              hidden={{ projectId }}
              fields={[
                {
                  name: "shares",
                  label: "Client milestones (%)",
                  hint: "For example 50, 50 (default) or 100 for all upfront.",
                  defaultValue:
                    milestones.length > 0
                      ? milestones.map((m) => m.share_percent ?? 0).join(", ")
                      : "50, 50",
                },
              ]}
            />
          </section>
        ) : null}
      </CardContent>
    </Card>
  );
}
