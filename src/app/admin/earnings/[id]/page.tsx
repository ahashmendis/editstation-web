import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense, type ReactNode } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { SignOutButton } from "@/components/sign-out-button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { formatDateTime } from "@/features/applications/components/status-badge";
import {
  PAYABLE_REASON_LABEL,
  PAYMENT_STATUS_LABEL,
  canSplitForDispute,
  adminLineLabel,
  nextAdminActions,
} from "@/features/payments/constants";
import { Money } from "@/features/payments/components/money";
import {
  PaymentActions,
  PaymentNoteForm,
  SplitDisputeForm,
} from "@/features/payments/components/payment-actions";
import { PaymentHistory } from "@/features/payments/components/payment-history";
import { PaymentNotes } from "@/features/payments/components/payment-notes";
import { PaymentStatusPill } from "@/features/payments/components/payment-status-pill";
import { getAdminPayment } from "@/features/payments/queries";
import { colomboDay } from "@/features/payments/summary";
import { AdminPayoutCard } from "@/features/payouts/components/payout-cards";
import { getAdminPayout } from "@/features/payouts/queries";
import { requireAdmin } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Payment · Admin · EDITSTATION" };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default function AdminPaymentPage({ params }: PageProps<"/admin/earnings/[id]">) {
  return (
    <Suspense fallback={<Loading />}>
      <PaymentContent params={params} />
    </Suspense>
  );
}

function Fact({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="grid gap-0.5">
      <dt className="text-muted-foreground text-xs">{label}</dt>
      <dd className="break-words">{children}</dd>
    </div>
  );
}

async function PaymentContent({ params }: { params: PageProps<"/admin/earnings/[id]">["params"] }) {
  await requireAdmin();
  const { id } = await params;
  if (!UUID.test(id)) notFound();
  const p = await getAdminPayment(id);
  if (!p) notFound();

  const payout = await getAdminPayout(p.editorId);
  const actions = nextAdminActions(p.status, p.kind, p.reversedById !== null);
  const splittable = canSplitForDispute(p);

  return (
    <AreaShell
      title={p.kind === "reversal" ? "Correction" : "Payment"}
      subtitle={`${p.projectTitle} · ${p.editorName}`}
      actions={<SignOutButton />}
    >
      <p className="text-sm">
        <Link href="/admin/earnings" className="underline">
          Back to earnings
        </Link>
      </p>

      <Card>
        <CardHeader>
          <CardTitle className="flex flex-wrap items-center gap-3">
            <span className="text-xl">
              <Money amount={p.amount} currency={p.currency} />
            </span>
            <PaymentStatusPill status={p.status} kind={p.kind} />
          </CardTitle>
        </CardHeader>
        <CardContent>
          <dl className="grid gap-4 text-sm sm:grid-cols-2">
            <Fact label="Project">
              <Link href={`/admin/projects/${p.projectId}`} className="underline">
                {p.projectTitle}
              </Link>
            </Fact>
            <Fact label="Editor">{p.editorName}</Fact>
            <Fact label="Milestone">
              {adminLineLabel(p)}
              {p.splitFromPaymentId ? " (disputed part)" : ""}
            </Fact>
            <Fact label="Payable">
              {p.payableReason ? PAYABLE_REASON_LABEL[p.payableReason] : "Not yet"}
              {p.payableAt ? (
                <span className="text-muted-foreground block text-xs">
                  {formatDateTime(p.payableAt)}
                </span>
              ) : null}
              {p.waitingOnClient ? (
                <span className="text-muted-foreground block text-xs">
                  Waiting for client payment (the editor sees this label)
                </span>
              ) : null}
            </Fact>
            <Fact label="Due date">{p.dueDate ?? "Not set"}</Fact>
            {p.amountBeforeSplit !== null ? (
              <Fact label="Split for a dispute">
                Originally <Money amount={p.amountBeforeSplit} currency={p.currency} />
                {p.splitChildId ? (
                  <Link href={`/admin/earnings/${p.splitChildId}`} className="block underline">
                    The disputed part
                  </Link>
                ) : null}
              </Fact>
            ) : null}
            {p.splitFromPaymentId ? (
              <Fact label="Split from">
                <Link href={`/admin/earnings/${p.splitFromPaymentId}`} className="underline">
                  The undisputed part
                </Link>
              </Fact>
            ) : null}
            {p.status === "on_hold" ? (
              <Fact label="On hold">
                {p.onHoldReason}
                {p.heldFromStatus ? (
                  <span className="text-muted-foreground block text-xs">
                    Returns to {PAYMENT_STATUS_LABEL[p.heldFromStatus].toLowerCase()} on release
                  </span>
                ) : null}
              </Fact>
            ) : null}
            {p.approvedAt ? (
              <Fact label="Approved">
                {formatDateTime(p.approvedAt)}
                {p.approvedBy ? ` by ${p.approvedBy}` : ""}
              </Fact>
            ) : null}
            {p.markedPaidAt ? (
              <Fact label="Marked paid">
                {formatDateTime(p.markedPaidAt)}
                {p.markedPaidBy ? ` by ${p.markedPaidBy}` : ""}
              </Fact>
            ) : null}
            {p.transferDate ? <Fact label="Transfer date">{p.transferDate}</Fact> : null}
            {p.transactionReference ? (
              <Fact label="Transaction reference">{p.transactionReference}</Fact>
            ) : null}
            {p.reversesPaymentId ? (
              <Fact label="Reverses">
                <Link href={`/admin/earnings/${p.reversesPaymentId}`} className="underline">
                  The original payment
                </Link>
                {p.reversalReason ? (
                  <span className="text-muted-foreground block">{p.reversalReason}</span>
                ) : null}
              </Fact>
            ) : null}
            {p.reversedById ? (
              <Fact label="Reversed by">
                <Link href={`/admin/earnings/${p.reversedById}`} className="underline">
                  The correction
                </Link>
              </Fact>
            ) : null}
            <Fact label="Created">{formatDateTime(p.createdAt)}</Fact>
          </dl>
        </CardContent>
      </Card>

      {actions.length > 0 ? (
        <Card>
          <CardHeader>
            <CardTitle>
              <h2>Actions</h2>
            </CardTitle>
          </CardHeader>
          <CardContent>
            <PaymentActions
              paymentId={p.id}
              actions={actions}
              dueDate={p.dueDate}
              today={colomboDay(new Date())}
              markPaidBlock={payout?.mark_paid_block ?? null}
            />
          </CardContent>
        </Card>
      ) : null}

      {payout && p.kind !== "reversal" ? (
        <AdminPayoutCard editorId={p.editorId} editorName={p.editorName} payout={payout} />
      ) : null}

      {splittable ? (
        <Card>
          <CardHeader>
            <CardTitle>
              <h2>Partial dispute</h2>
            </CardTitle>
          </CardHeader>
          <CardContent className="grid gap-2">
            <p className="text-muted-foreground text-sm">
              Hold only the disputed part of this milestone. The rest keeps its status and can be
              approved and paid.
            </p>
            <SplitDisputeForm paymentId={p.id} amount={p.amount} />
          </CardContent>
        </Card>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle>
            <h2>Internal notes</h2>
          </CardTitle>
        </CardHeader>
        <CardContent className="grid gap-4">
          <PaymentNoteForm paymentId={p.id} />
          <PaymentNotes notes={p.notes} />
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>
            <h2>History</h2>
          </CardTitle>
        </CardHeader>
        <CardContent>
          <PaymentHistory activity={p.activity} />
        </CardContent>
      </Card>
    </AreaShell>
  );
}
