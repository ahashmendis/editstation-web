import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { EmptyState } from "@/components/empty-state";
import { SignOutButton } from "@/components/sign-out-button";
import { buttonVariants } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { formatDateTime } from "@/features/applications/components/status-badge";
import { ProjectStatusPill } from "@/features/projects/components/project-status-pill";
import {
  BRIEF_TYPE_LABEL,
  PROJECT_FILTERS,
  type BriefType,
  type ProjectFilter,
  type ProjectStatus,
} from "@/features/projects/constants";
import { listProjects } from "@/features/projects/queries";
import { requireAdmin } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Projects · Admin · EDITSTATION" };

export default function ProjectsPage({ searchParams }: PageProps<"/admin/projects">) {
  return (
    <Suspense fallback={<Loading />}>
      <ProjectsContent searchParams={searchParams} />
    </Suspense>
  );
}

async function ProjectsContent({
  searchParams,
}: {
  searchParams: PageProps<"/admin/projects">["searchParams"];
}) {
  await requireAdmin();
  const params = await searchParams;
  const requested = typeof params.filter === "string" ? params.filter : "active";
  const filter = PROJECT_FILTERS.some((f) => f.value === requested)
    ? (requested as ProjectFilter)
    : "active";
  const rows = await listProjects(filter);

  return (
    <AreaShell
      title="Projects"
      subtitle="Create a project from a confirmed inquiry, or start one by hand."
      actions={
        <div className="flex items-center gap-2">
          <Link href="/admin/projects/new" className={buttonVariants()}>
            New project
          </Link>
          <SignOutButton />
        </div>
      }
    >
      <nav aria-label="Filter projects" className="flex flex-wrap gap-2 text-sm">
        {PROJECT_FILTERS.map((f) => (
          <Link
            key={f.value}
            href={`/admin/projects?filter=${f.value}`}
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
            <EmptyState
              title="No projects in this view"
              action={
                <Link href="/admin/projects/new" className={buttonVariants({ variant: "outline" })}>
                  New project
                </Link>
              }
            >
              Try another filter, or create a project.
            </EmptyState>
          ) : (
            <table className="w-full text-left text-sm">
              <thead className="text-muted-foreground">
                <tr>
                  <th className="py-2 pr-4 font-medium">Project</th>
                  <th className="py-2 pr-4 font-medium">Status</th>
                  <th className="py-2 pr-4 font-medium">Deadline</th>
                  <th className="py-2 font-medium">Updated</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((row) => (
                  <tr key={row.id} className="border-t">
                    <td className="py-2 pr-4">
                      <Link href={`/admin/projects/${row.id}`} className="underline">
                        {row.title}
                      </Link>
                      <div className="text-muted-foreground text-xs">
                        {BRIEF_TYPE_LABEL[row.brief_type as BriefType]} · brief v
                        {row.current_brief_version}
                        {row.archived_at ? " · Archived" : ""}
                      </div>
                    </td>
                    <td className="py-2 pr-4">
                      <ProjectStatusPill status={row.status as ProjectStatus} />
                    </td>
                    <td className="py-2 pr-4 tabular-nums">{row.deadline ?? "—"}</td>
                    <td className="py-2 tabular-nums">{formatDateTime(row.updated_at)}</td>
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
