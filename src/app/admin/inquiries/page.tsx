import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { SignOutButton } from "@/components/sign-out-button";
import { Card, CardContent } from "@/components/ui/card";
import { formatDateTime } from "@/features/applications/components/status-badge";
import { InquiryStatusBadge } from "@/features/inquiries/components/inquiry-status-badge";
import { listInquiries, type InquiryFilter } from "@/features/inquiries/queries";
import { requireAdmin } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Inquiries · Admin · EDITSTATION" };

const FILTERS: { value: InquiryFilter; label: string }[] = [
  { value: "open", label: "Open" },
  { value: "closed", label: "Closed" },
  { value: "all", label: "All" },
];

export default function InquiriesPage({ searchParams }: PageProps<"/admin/inquiries">) {
  return (
    <Suspense fallback={<Loading />}>
      <InquiriesContent searchParams={searchParams} />
    </Suspense>
  );
}

async function InquiriesContent({
  searchParams,
}: {
  searchParams: PageProps<"/admin/inquiries">["searchParams"];
}) {
  await requireAdmin();
  const params = await searchParams;
  const requested = typeof params.filter === "string" ? params.filter : "open";
  const filter = FILTERS.some((f) => f.value === requested) ? (requested as InquiryFilter) : "open";
  const rows = await listInquiries(filter);

  return (
    <AreaShell
      title="Client inquiries"
      subtitle="Leads only: an inquiry never creates a project on its own."
      actions={<SignOutButton />}
    >
      <nav aria-label="Filter inquiries" className="flex flex-wrap gap-2 text-sm">
        {FILTERS.map((f) => (
          <Link
            key={f.value}
            href={`/admin/inquiries?filter=${f.value}`}
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
            <p className="text-muted-foreground text-sm">No inquiries here.</p>
          ) : (
            <table className="w-full text-left text-sm">
              <thead className="text-muted-foreground">
                <tr>
                  <th className="py-2 pr-4 font-medium">Contact</th>
                  <th className="py-2 pr-4 font-medium">Service</th>
                  <th className="py-2 pr-4 font-medium">Status</th>
                  <th className="py-2 font-medium">Received</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((row) => (
                  <tr key={row.id} className="border-t">
                    <td className="py-2 pr-4">
                      <Link href={`/admin/inquiries/${row.id}`} className="underline">
                        {row.contact_name}
                      </Link>
                      <div className="text-muted-foreground text-xs">
                        {[row.company, row.email].filter(Boolean).join(" · ")}
                      </div>
                    </td>
                    <td className="py-2 pr-4">{row.service_type_label}</td>
                    <td className="py-2 pr-4">
                      <InquiryStatusBadge status={row.status} />
                    </td>
                    <td className="py-2 tabular-nums">{formatDateTime(row.submitted_at)}</td>
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
