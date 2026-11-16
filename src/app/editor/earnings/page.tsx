import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { EmptyState } from "@/components/empty-state";
import { SignOutButton } from "@/components/sign-out-button";
import { buttonVariants } from "@/components/ui/button";
import { EditorAdjustmentOffers } from "@/features/adjustments/components/panels";
import { listMyAdjustments } from "@/features/adjustments/queries";
import { EditorPaymentList } from "@/features/payments/components/editor-payment-list";
import { StatusFilter } from "@/features/payments/components/status-filter";
import { SummaryCards, type SummaryCardSpec } from "@/features/payments/components/summary-cards";
import { listMyPayments } from "@/features/payments/queries";
import { parseEditorEarningsFilter } from "@/features/payments/schemas";
import { EditorPayoutCard } from "@/features/payouts/components/payout-cards";
import { getMyPayout } from "@/features/payouts/queries";
import { summariseByCurrency } from "@/features/payments/summary";
import { requireActiveEditor } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Earnings · EDITSTATION" };

const CARDS: SummaryCardSpec[] = [
  { key: "committed", label: "Committed" },
  { key: "awaitingTransfer", label: "Approved" },
  { key: "paidThisMonth", label: "Paid this month" },
  { key: "paidAllTime", label: "Paid all time" },
  { key: "onHold", label: "On hold", hideWhenZero: true },
];

export default function EditorEarningsPage({ searchParams }: PageProps<"/editor/earnings">) {
  return (
    <Suspense fallback={<Loading />}>
      <EarningsContent searchParams={searchParams} />
    </Suspense>
  );
}

async function EarningsContent({
  searchParams,
}: {
  searchParams: PageProps<"/editor/earnings">["searchParams"];
}) {
  await requireActiveEditor();
  const filter = parseEditorEarningsFilter(await searchParams);
  const [rows, offers, payout] = await Promise.all([
    listMyPayments(),
    listMyAdjustments(),
    getMyPayout(),
  ]);
  const openOffers = offers.filter((o) => o.status === "offered");
  const shown = filter.status ? rows.filter((r) => r.status === filter.status) : rows;

  return (
    <AreaShell
      title="Earnings"
      subtitle="What Lenscape has committed to pay you and what has been paid."
      actions={<SignOutButton />}
    >
      <EditorAdjustmentOffers offers={openOffers} showProject />
      <EditorPayoutCard payout={payout} />
      {rows.length === 0 ? (
        <EmptyState title="No earnings yet">
          Pay appears here once an admin confirms you on a project.
        </EmptyState>
      ) : (
        <>
          <SummaryCards summary={summariseByCurrency(rows, new Date())} cards={CARDS} />
          <StatusFilter basePath="/editor/earnings" current={filter.status} />
          {shown.length === 0 ? (
            <EmptyState
              title="No payments with this status."
              action={
                <Link href="/editor/earnings" className={buttonVariants({ variant: "outline" })}>
                  Show all payments
                </Link>
              }
            />
          ) : (
            <EditorPaymentList rows={shown} />
          )}
        </>
      )}
    </AreaShell>
  );
}
