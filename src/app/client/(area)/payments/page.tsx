import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { EmptyState } from "@/components/empty-state";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { BankDetailsPanel, MilestoneList } from "@/features/client-area/components/client-ui";
import { getClientPaymentInfo } from "@/features/client-area/queries";
import { requireClient } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Payments · Client · EDITSTATION" };

export default function ClientPaymentsPage() {
  return (
    <Suspense fallback={<Loading />}>
      <Payments />
    </Suspense>
  );
}

async function Payments() {
  await requireClient();
  const info = await getClientPaymentInfo();
  const withPayments = info.projects.filter((p) => p.milestones.length > 0);

  return (
    <AreaShell title="Payments" subtitle="What you have paid and what is due, by project.">
      {/* Shown only once the studio has entered its bank details (never invented). */}
      {info.bank_details ? (
        <Card>
          <CardHeader>
            <CardTitle>How to pay</CardTitle>
          </CardHeader>
          <CardContent>
            <BankDetailsPanel details={info.bank_details} />
          </CardContent>
        </Card>
      ) : null}

      {withPayments.length === 0 ? (
        <Card>
          <CardContent>
            <EmptyState title="No payments yet">
              Payments appear here once the studio has agreed the terms of a project with you.
            </EmptyState>
          </CardContent>
        </Card>
      ) : (
        withPayments.map((p) => (
          <Card key={p.project_id}>
            <CardHeader>
              <CardTitle className="break-words">
                <Link
                  href={`/client/projects/${p.project_id}`}
                  className="underline-offset-4 hover:underline"
                >
                  {p.title}
                </Link>
              </CardTitle>
            </CardHeader>
            <CardContent>
              <MilestoneList milestones={p.milestones} />
            </CardContent>
          </Card>
        ))
      )}
    </AreaShell>
  );
}
