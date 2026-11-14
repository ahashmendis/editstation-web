import type { Metadata } from "next";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { EmptyState } from "@/components/empty-state";
import { SignOutButton } from "@/components/sign-out-button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { AdminFilters } from "@/features/payments/components/admin-filters";
import { AdminPaymentsTable } from "@/features/payments/components/admin-payments-table";
import { EditorBreakdown } from "@/features/payments/components/editor-breakdown";
import {
  ProjectMarginTable,
  type ProjectMarginRow,
} from "@/features/payments/components/project-margin-table";
import { SummaryCards, type SummaryCardSpec } from "@/features/payments/components/summary-cards";
import { listAdminPayments, listProjectPrices } from "@/features/payments/queries";
import { parseAdminEarningsFilter } from "@/features/payments/schemas";
import { projectMargin, summariseByCurrency, summariseByEditor } from "@/features/payments/summary";
import { requireAdmin } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Earnings · Admin · EDITSTATION" };

const CARDS: SummaryCardSpec[] = [
  { key: "committed", label: "Outstanding liabilities" },
  { key: "awaitingTransfer", label: "Approved, awaiting transfer" },
  { key: "onHold", label: "On hold" },
  { key: "paidThisMonth", label: "Paid this month" },
  { key: "paidAllTime", label: "Paid all time" },
];

export default function AdminEarningsPage({ searchParams }: PageProps<"/admin/earnings">) {
  return (
    <Suspense fallback={<Loading />}>
      <EarningsContent searchParams={searchParams} />
    </Suspense>
  );
}

async function EarningsContent({
  searchParams,
}: {
  searchParams: PageProps<"/admin/earnings">["searchParams"];
}) {
  await requireAdmin();
  const filter = parseAdminEarningsFilter(await searchParams);
  const filtered = filter.status !== null || filter.editor !== null || filter.currency !== null;
  const [all, shown] = await Promise.all([
    listAdminPayments(),
    filtered ? listAdminPayments(filter) : Promise.resolve(null),
  ]);
  const rows = shown ?? all;
  const now = new Date();

  const names = new Map(all.map((r) => [r.editorId, r.editorName]));
  const editors = [...names.entries()]
    .map(([id, name]) => ({ id, name }))
    .sort((a, b) => a.name.localeCompare(b.name));
  const currencies = [...new Set(all.map((r) => r.currency))].sort();

  const prices = await listProjectPrices(all.map((r) => r.projectId));
  const margins: ProjectMarginRow[] = prices.map((p) => ({
    projectId: p.projectId,
    title: p.title,
    margin: projectMargin({
      clientPrice: p.clientPrice,
      clientCurrency: p.clientCurrency,
      rows: all.filter((r) => r.projectId === p.projectId),
    }),
  }));

  return (
    <AreaShell
      title="Earnings"
      subtitle="What Lenscape owes and has paid editors."
      actions={<SignOutButton />}
    >
      {all.length === 0 ? (
        <Card>
          <CardContent>
            <EmptyState title="No payments yet">
              A payment record is created when you confirm an editor.
            </EmptyState>
          </CardContent>
        </Card>
      ) : (
        <>
          <SummaryCards summary={summariseByCurrency(all, now)} cards={CARDS} />

          <Card>
            <CardHeader>
              <CardTitle>
                <h2>Payments</h2>
              </CardTitle>
            </CardHeader>
            <CardContent className="grid gap-4">
              <AdminFilters filter={filter} editors={editors} currencies={currencies} />
              {rows.length === 0 ? (
                <EmptyState title="No payments match these filters.">
                  Clear the filters to see every payment.
                </EmptyState>
              ) : (
                <AdminPaymentsTable rows={rows} now={now} />
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>
                <h2>By editor</h2>
              </CardTitle>
            </CardHeader>
            <CardContent>
              <EditorBreakdown rows={summariseByEditor(all, now)} names={names} />
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>
                <h2>Project margin</h2>
              </CardTitle>
              <CardDescription>Admin only: client price minus editor pay.</CardDescription>
            </CardHeader>
            <CardContent>
              {margins.length === 0 ? (
                <EmptyState title="No projects with payments yet." />
              ) : (
                <ProjectMarginTable rows={margins} />
              )}
            </CardContent>
          </Card>
        </>
      )}
    </AreaShell>
  );
}
