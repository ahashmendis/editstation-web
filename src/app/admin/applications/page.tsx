import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { SignOutButton } from "@/components/sign-out-button";
import { Card, CardContent } from "@/components/ui/card";
import { formatDateTime, StatusBadge } from "@/features/applications/components/status-badge";
import { listApplications, type ApplicationFilter } from "@/features/applications/queries";
import { requireAdmin } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Applications · Admin · EDITSTATION" };

const FILTERS: { value: ApplicationFilter; label: string }[] = [
  { value: "open", label: "Needs attention" },
  { value: "decided", label: "Decided" },
  { value: "drafts", label: "Reopened drafts" },
  { value: "all", label: "All" },
];

export default function ApplicationsPage({ searchParams }: PageProps<"/admin/applications">) {
  return (
    <Suspense fallback={<Loading />}>
      <ApplicationsContent searchParams={searchParams} />
    </Suspense>
  );
}

async function ApplicationsContent({
  searchParams,
}: {
  searchParams: PageProps<"/admin/applications">["searchParams"];
}) {
  await requireAdmin();
  const params = await searchParams;
  const requested = typeof params.filter === "string" ? params.filter : "open";
  const filter = FILTERS.some((f) => f.value === requested)
    ? (requested as ApplicationFilter)
    : "open";
  const rows = await listApplications(filter);

  return (
    <AreaShell title="Editor applications" actions={<SignOutButton />}>
      <nav aria-label="Filter applications" className="flex flex-wrap gap-2 text-sm">
        {FILTERS.map((f) => (
          <Link
            key={f.value}
            href={`/admin/applications?filter=${f.value}`}
            aria-current={f.value === filter ? "page" : undefined}
            className={
              f.value === filter
                ? "bg-primary text-primary-foreground rounded-md px-3 py-1"
                : "hover:bg-muted rounded-md px-3 py-1"
            }
          >
            {f.label}
          </Link>
        ))}
      </nav>
      <Card>
        <CardContent className="overflow-x-auto pt-6">
          {rows.length === 0 ? (
            <p className="text-muted-foreground text-sm">No applications here.</p>
          ) : (
            <table className="w-full text-left text-sm">
              <thead className="text-muted-foreground">
                <tr>
                  <th className="py-2 pr-4 font-medium">Applicant</th>
                  <th className="py-2 pr-4 font-medium">Status</th>
                  <th className="py-2 pr-4 font-medium">Submitted</th>
                  <th className="py-2 font-medium">Attempt</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((row) => (
                  <tr key={row.id} className="border-t">
                    <td className="py-2 pr-4">
                      <Link href={`/admin/applications/${row.id}`} className="underline">
                        {row.person?.full_name ?? row.person?.email ?? "Unknown"}
                      </Link>
                      <div className="text-muted-foreground text-xs">{row.person?.email}</div>
                    </td>
                    <td className="py-2 pr-4">
                      <StatusBadge status={row.status} />
                    </td>
                    <td className="py-2 pr-4 tabular-nums">{formatDateTime(row.submitted_at)}</td>
                    <td className="py-2 tabular-nums">{row.attempt}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </CardContent>
      </Card>
    </AreaShell>
  );
}
