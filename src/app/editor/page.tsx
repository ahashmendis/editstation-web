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
import { listNotifications } from "@/features/notifications/queries";
import {
  QuickActions,
  RecentNotifications,
  WorkSummary,
} from "@/features/workspace/components/dashboard-sections";
import { getEditorWorkspace } from "@/features/workspace/queries";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { requireActiveEditor } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Editor dashboard · EDITSTATION" };

// "Today" for overdue deadlines, in the studio's time zone (same zone as the earnings figures).
const TODAY = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Colombo" });

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
  // The workspace summary and notifications fail on their own, without hiding the offers.
  const [{ opportunities, truncated, limit }, workspace, notifications] = await Promise.all([
    getEditorDashboard(),
    getEditorWorkspace().catch(() => null),
    listNotifications(5).catch(() => null),
  ]);

  return (
    <AreaShell
      title="Editor dashboard"
      subtitle={access.email ?? undefined}
      actions={<SignOutButton />}
    >
      <QuickActions />
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

      {workspace === null ? (
        <Alert variant="destructive" role="alert">
          <AlertDescription>
            Your work summary could not be loaded. Reload the page to try again.
          </AlertDescription>
        </Alert>
      ) : (
        <WorkSummary workspace={workspace} today={TODAY.format(new Date())} />
      )}

      <RecentNotifications rows={notifications} />
    </AreaShell>
  );
}
