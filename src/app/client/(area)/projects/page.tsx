import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { EmptyState } from "@/components/empty-state";
import { Card, CardContent } from "@/components/ui/card";
import { formatDateTime } from "@/features/applications/components/status-badge";
import { ClientStatusPill } from "@/features/client-area/components/client-ui";
import { listClientProjects } from "@/features/client-area/queries";
import { requireClient } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Projects · Client · EDITSTATION" };

export default function ClientProjectsPage() {
  return (
    <Suspense fallback={<Loading />}>
      <ProjectsList />
    </Suspense>
  );
}

async function ProjectsList() {
  await requireClient();
  const projects = await listClientProjects();

  return (
    <AreaShell title="Projects" subtitle="Every project you have with the studio.">
      <Card>
        <CardContent>
          {projects.length === 0 ? (
            <EmptyState title="No projects yet">
              Projects the studio is working on for you appear here, with their status and updates.
            </EmptyState>
          ) : (
            <ul className="divide-y">
              {projects.map((p) => {
                return (
                  <li key={p.id} className="flex flex-wrap items-start justify-between gap-3 py-3">
                    <div className="grid min-w-0 flex-1 gap-0.5">
                      <Link
                        href={`/client/projects/${p.id}`}
                        className="text-sm font-medium break-words underline-offset-4 hover:underline"
                      >
                        {p.title}
                      </Link>
                      <p className="text-muted-foreground text-xs">
                        {p.last_update_at
                          ? `Last update ${formatDateTime(p.last_update_at)}`
                          : "No updates yet"}
                      </p>
                    </div>
                    <ClientStatusPill status={p.client_status} />
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
