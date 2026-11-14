import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { EmptyState } from "@/components/empty-state";
import { SignOutButton } from "@/components/sign-out-button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { AssignmentPill } from "@/features/access/components/assignment-pill";
import { formatMoney } from "@/features/access/constants";
import { getEditorDashboard } from "@/features/access/queries";
import {
  BRIEF_TYPE_LABEL,
  PROJECT_STATUS_LABEL,
  type BriefType,
  type ProjectStatus,
} from "@/features/projects/constants";
import { requireActiveEditor } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Editor dashboard · EDITSTATION" };

// Own Suspense boundary: per-request data must not block navigation into this page.
export default function EditorPage() {
  return (
    <Suspense fallback={<Loading />}>
      <EditorContent />
    </Suspense>
  );
}

type ProjectCard = Awaited<ReturnType<typeof getEditorDashboard>>["opportunities"][number];

function ProjectList({
  items,
  empty,
}: {
  items: ProjectCard[];
  empty: { title: string; body: string };
}) {
  if (items.length === 0) return <EmptyState title={empty.title}>{empty.body}</EmptyState>;
  return (
    <ul className="grid gap-3">
      {items.map((p) => (
        <li key={p.id} className="rounded-lg border p-3">
          <div className="flex flex-wrap items-start justify-between gap-2">
            <Link href={`/editor/projects/${p.id}`} className="font-medium underline">
              {p.title}
            </Link>
            {p.offer ? <AssignmentPill status={p.offer.status} viewer="editor" /> : null}
          </div>
          <p className="text-muted-foreground pt-1 text-sm">
            {BRIEF_TYPE_LABEL[p.briefType as BriefType]}
            {p.deadline ? ` · Deadline ${p.deadline}` : ""}
            {p.status !== "open" && p.status !== "assigned"
              ? ` · ${PROJECT_STATUS_LABEL[p.status as ProjectStatus]}`
              : ""}
          </p>
          {p.offer?.live ? (
            <p className="pt-1 text-sm">
              Current offer:{" "}
              <strong className="tabular-nums">
                {formatMoney(p.offer.amount, p.offer.currency)}
              </strong>
            </p>
          ) : p.offer ? (
            <p className="text-muted-foreground pt-1 text-sm">
              This offer is closed. A new one will show here if the studio sends it.
            </p>
          ) : p.baseline ? (
            <p className="text-muted-foreground pt-1 text-sm">
              Proposed pay: {formatMoney(p.baseline.amount, p.baseline.currency)}. Not agreed until
              you accept an offer.
            </p>
          ) : null}
        </li>
      ))}
    </ul>
  );
}

async function EditorContent() {
  const access = await requireActiveEditor();
  const { opportunities, myProjects, truncated, limit } = await getEditorDashboard();

  return (
    <AreaShell
      title="Editor dashboard"
      subtitle={access.email ?? undefined}
      actions={<SignOutButton />}
    >
      {truncated ? (
        <p className="text-muted-foreground text-sm">Showing the most recent {limit} projects.</p>
      ) : null}
      <Card>
        <CardHeader>
          <CardTitle>Opportunities</CardTitle>
          <CardDescription>
            Projects the studio has invited you to. Open one to see the summary and reply to an
            offer. Nothing starts until the pay is agreed and the studio confirms you.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <ProjectList
            items={opportunities}
            empty={{
              title: "No opportunities right now",
              body: "When the studio invites you to a project, it will show up here.",
            }}
          />
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>My projects</CardTitle>
          <CardDescription>Projects where the studio has confirmed you.</CardDescription>
        </CardHeader>
        <CardContent>
          <ProjectList
            items={myProjects}
            empty={{
              title: "No confirmed projects yet",
              body: "Once you accept an offer and the studio confirms you, the project appears here with its full brief.",
            }}
          />
        </CardContent>
      </Card>
    </AreaShell>
  );
}
