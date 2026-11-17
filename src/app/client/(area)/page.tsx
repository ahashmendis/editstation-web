import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { EmptyState } from "@/components/empty-state";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  formatAmount,
  formatDay,
  isClosedStatus,
  isPaymentDue,
} from "@/features/client-area/constants";
import { ClientStatusPill } from "@/features/client-area/components/client-ui";
import { getClientPaymentInfo, listClientProjects } from "@/features/client-area/queries";
import { requireClient } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Overview · Client · EDITSTATION" };

export default function ClientOverviewPage() {
  return (
    <Suspense fallback={<Loading />}>
      <Overview />
    </Suspense>
  );
}

async function Overview() {
  await requireClient();
  const [projects, payments] = await Promise.all([listClientProjects(), getClientPaymentInfo()]);
  const active = projects.filter((p) => !isClosedStatus(p.client_status));
  const due = payments.projects.flatMap((p) =>
    p.milestones
      .filter((m) => isPaymentDue(m.payment_status))
      .map((m) => ({ ...m, title: p.title })),
  );

  return (
    <AreaShell title="Overview" subtitle="Your projects with the studio at a glance.">
      <div className="grid gap-4 sm:grid-cols-2">
        <Card>
          <CardHeader>
            <CardDescription>Active projects</CardDescription>
            <CardTitle className="text-3xl tabular-nums">{active.length}</CardTitle>
          </CardHeader>
        </Card>
        <Card>
          <CardHeader>
            <CardDescription>Payments awaiting</CardDescription>
            <CardTitle className="text-3xl tabular-nums">{due.length}</CardTitle>
          </CardHeader>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Projects in progress</CardTitle>
        </CardHeader>
        <CardContent>
          {active.length === 0 ? (
            <EmptyState
              title="No projects in progress"
              action={
                <Link href="/client/projects" className="text-sm underline">
                  See all projects
                </Link>
              }
            >
              When the studio starts a project for you, it appears here.
            </EmptyState>
          ) : (
            <ul className="divide-y">
              {active.map((p) => (
                <li key={p.id} className="flex flex-wrap items-center justify-between gap-3 py-3">
                  <Link
                    href={`/client/projects/${p.id}`}
                    className="min-w-0 text-sm font-medium break-words underline-offset-4 hover:underline"
                  >
                    {p.title}
                  </Link>
                  <ClientStatusPill status={p.client_status} />
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>

      {due.length > 0 ? (
        <Card>
          <CardHeader>
            <CardTitle>Payments awaiting</CardTitle>
            <CardDescription>
              <Link href="/client/payments" className="underline">
                See all payments
              </Link>
            </CardDescription>
          </CardHeader>
          <CardContent>
            <ul className="divide-y">
              {due.map((m) => (
                <li key={m.id} className="grid gap-0.5 py-3 text-sm">
                  <span className="font-medium break-words">{m.title}</span>
                  <span className="text-muted-foreground tabular-nums">
                    {formatAmount(m.amount, m.currency)}
                    {m.due_date ? ` · due ${formatDay(m.due_date)}` : ""}
                  </span>
                </li>
              ))}
            </ul>
          </CardContent>
        </Card>
      ) : null}
    </AreaShell>
  );
}
