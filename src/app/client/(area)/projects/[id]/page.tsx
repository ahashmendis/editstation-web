import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { z } from "zod";

import { AreaShell, Loading } from "@/components/auth-shell";
import { EmptyState } from "@/components/empty-state";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { formatDateTime } from "@/features/applications/components/status-badge";
import { clientStatus } from "@/features/client-area/constants";
import { ClientStatusPill, MilestoneList } from "@/features/client-area/components/client-ui";
import { getClientProject } from "@/features/client-area/queries";
import { requireClient } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Project · Client · EDITSTATION" };

export default function ClientProjectPage({ params }: PageProps<"/client/projects/[id]">) {
  return (
    <Suspense fallback={<Loading />}>
      <ProjectDetail params={params} />
    </Suspense>
  );
}

function deliverableDetails(d: {
  format: string | null;
  resolution: string | null;
  aspect_ratio: string | null;
  duration_seconds: number | null;
}): string {
  const parts = [d.format, d.resolution, d.aspect_ratio];
  if (d.duration_seconds !== null) {
    const m = Math.floor(d.duration_seconds / 60);
    const s = d.duration_seconds % 60;
    parts.push(m > 0 ? `${m} min ${s} s` : `${s} s`);
  }
  return parts.filter(Boolean).join(" · ");
}

async function ProjectDetail({ params }: { params: PageProps<"/client/projects/[id]">["params"] }) {
  await requireClient();
  const { id } = await params;
  if (!z.uuid().safeParse(id).success) notFound();
  // Null for a project of another client, an archived one or an unknown id (same answer).
  const project = await getClientProject(id);
  if (!project) notFound();
  const status = clientStatus(project.client_status);

  return (
    <AreaShell title={project.title}>
      <Link href="/client/projects" className="text-muted-foreground w-fit text-sm underline">
        ← All projects
      </Link>

      <Card>
        <CardHeader>
          <div className="flex flex-wrap items-center gap-3">
            <CardTitle>Status</CardTitle>
            <ClientStatusPill status={project.client_status} />
          </div>
          <CardDescription>{status.hint}</CardDescription>
        </CardHeader>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Updates from the studio</CardTitle>
        </CardHeader>
        <CardContent>
          {project.updates.length === 0 ? (
            <EmptyState title="No updates yet">
              The studio posts progress notes here as the project moves along.
            </EmptyState>
          ) : (
            <ol className="grid gap-4">
              {project.updates.map((u) => (
                <li key={u.id} className="border-l-2 pl-3">
                  <p className="text-muted-foreground text-xs tabular-nums">
                    {formatDateTime(u.published_at)}
                  </p>
                  <p className="text-sm break-words whitespace-pre-wrap">{u.body}</p>
                </li>
              ))}
            </ol>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Deliverables</CardTitle>
        </CardHeader>
        <CardContent>
          {project.deliverables.length === 0 ? (
            <EmptyState title="No deliverables listed yet">
              The studio adds the videos you will receive once the project is planned.
            </EmptyState>
          ) : (
            <ul className="divide-y">
              {project.deliverables.map((d, i) => (
                <li key={`${d.name}-${i}`} className="grid gap-0.5 py-3">
                  <span className="text-sm font-medium break-words">{d.name}</span>
                  {deliverableDetails(d) ? (
                    <span className="text-muted-foreground text-xs">{deliverableDetails(d)}</span>
                  ) : null}
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Payments</CardTitle>
          <CardDescription>
            <Link href="/client/payments" className="underline">
              Payment details and all payments
            </Link>
          </CardDescription>
        </CardHeader>
        <CardContent>
          {project.milestones.length === 0 ? (
            <EmptyState title="No payments scheduled yet">
              Payments appear here once the studio has agreed the terms with you.
            </EmptyState>
          ) : (
            <MilestoneList milestones={project.milestones} />
          )}
        </CardContent>
      </Card>
    </AreaShell>
  );
}
