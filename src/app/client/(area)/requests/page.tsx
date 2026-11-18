import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { EmptyState } from "@/components/empty-state";
import { Card, CardContent } from "@/components/ui/card";
import { formatDateTime } from "@/features/applications/components/status-badge";
import { formatDay, requestStatus } from "@/features/client-area/constants";
import { NewProjectActions, RequestStatusPill } from "@/features/client-area/components/client-ui";
import { listClientRequests } from "@/features/client-area/queries";
import { requireClient } from "@/lib/auth/access";

export const metadata: Metadata = { title: "My requests · Client · EDITSTATION" };

export default function ClientRequestsPage() {
  return (
    <Suspense fallback={<Loading />}>
      <RequestsList />
    </Suspense>
  );
}

async function RequestsList() {
  await requireClient();
  const requests = await listClientRequests();

  return (
    <AreaShell
      title="My requests"
      subtitle="Projects you asked the studio for, and where each request stands."
      actions={<NewProjectActions withRequests={false} />}
    >
      <Card>
        <CardContent>
          {requests.length === 0 ? (
            <EmptyState title="No requests yet" action={<NewProjectActions withRequests={false} />}>
              When you send the studio a new project, it appears here until it becomes a project.
            </EmptyState>
          ) : (
            <ul className="divide-y">
              {requests.map((r) => {
                const wish = formatDay(r.expected_deadline);
                return (
                  <li
                    key={r.id}
                    className="flex flex-wrap items-start justify-between gap-3 py-3"
                    data-testid="client-request"
                  >
                    <div className="grid min-w-0 flex-1 gap-1">
                      <p className="text-sm font-medium break-words">{r.service_type_label}</p>
                      <p className="text-muted-foreground line-clamp-3 text-sm break-words whitespace-pre-wrap">
                        {r.description}
                      </p>
                      <p className="text-muted-foreground text-xs">
                        Sent {formatDateTime(r.submitted_at)}
                        {wish ? ` · you asked for ${wish}` : ""}
                      </p>
                      <p className="text-muted-foreground text-xs">
                        {requestStatus(r.request_status).hint}
                      </p>
                      {r.project_id ? (
                        <Link
                          href={`/client/projects/${r.project_id}`}
                          className="text-sm underline underline-offset-4"
                        >
                          Open the project
                        </Link>
                      ) : null}
                    </div>
                    <RequestStatusPill status={r.request_status} />
                  </li>
                );
              })}
            </ul>
          )}
        </CardContent>
      </Card>
    </AreaShell>
  );
}
