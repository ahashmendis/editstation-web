import Link from "next/link";
import type { ReactNode } from "react";

import { EmptyState } from "@/components/empty-state";
import { StatusPill } from "@/components/status-pill";
import { buttonVariants } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { formatDateTime } from "@/features/applications/components/status-badge";
import { notificationHref, type NotificationRow } from "@/features/notifications/constants";
import { Money } from "@/features/payments/components/money";
import { PaymentStatusPill } from "@/features/payments/components/payment-status-pill";
import { lineLabel } from "@/features/payments/constants";
import {
  OUTCOME_LABEL,
  OUTCOME_TONE,
  REVISION_STATUS_LABEL,
  REVISION_STATUS_TONE,
  REVISION_TYPE_LABEL,
} from "@/features/submissions/constants";

import { feedbackGroupOf, isActiveStage, outstandingPayments, upcomingDeadlines } from "../model";
import type { EditorWorkspace } from "../queries";
import { ActionText, StagePill } from "./workspace-ui";

const LIMIT = 5;

function SectionLink({ href, children }: { href: string; children: ReactNode }) {
  return (
    <Link
      href={href}
      className="focus-visible:ring-ring w-fit rounded-sm text-sm underline focus-visible:ring-2 focus-visible:outline-none"
    >
      {children}
    </Link>
  );
}

/** Links to existing editor pages only. */
export function QuickActions() {
  const links = [
    { href: "/editor/projects", label: "My projects" },
    { href: "/editor/feedback", label: "Feedback & revisions" },
    { href: "/editor/opportunities", label: "Open opportunities" },
    { href: "/editor/earnings", label: "Earnings" },
  ];
  return (
    <nav aria-label="Quick actions" className="flex flex-wrap gap-2">
      {links.map((l) => (
        <Link key={l.href} href={l.href} className={buttonVariants({ variant: "outline" })}>
          {l.label}
        </Link>
      ))}
    </nav>
  );
}

export function RecentNotifications({ rows }: { rows: NotificationRow[] | null }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Recent notifications</CardTitle>
      </CardHeader>
      <CardContent className="grid gap-3">
        {rows === null ? (
          <p role="alert" className="text-sm">
            Notifications could not be loaded. Reload the page to try again.
          </p>
        ) : rows.length === 0 ? (
          <EmptyState title="No notifications yet" />
        ) : (
          <ul className="grid gap-3">
            {rows.map((n) => (
              <li key={n.id} className="grid gap-0.5 text-sm">
                <span className="flex flex-wrap items-center gap-2">
                  {n.read_at === null ? <StatusPill tone="info">Unread</StatusPill> : null}
                  <Link href={notificationHref(n)} className="break-words underline">
                    {n.title}
                  </Link>
                </span>
                <span className="text-muted-foreground text-xs tabular-nums">
                  {formatDateTime(n.created_at)}
                </span>
              </li>
            ))}
          </ul>
        )}
        <SectionLink href="/notifications">All notifications</SectionLink>
      </CardContent>
    </Card>
  );
}

/** Dashboard sections built from the editor's own workspace data. `today` is YYYY-MM-DD. */
export function WorkSummary({ workspace, today }: { workspace: EditorWorkspace; today: string }) {
  const active = workspace.rows.filter((r) => isActiveStage(r.stage));
  const deadlines = upcomingDeadlines(workspace.rows, today).slice(0, LIMIT);
  const inReview = workspace.rows.filter((r) => r.stage === "in_review");
  const openRevisions = workspace.revisions.filter((r) => {
    const group = feedbackGroupOf(r.status);
    return group === "open" || group === "in_progress";
  });
  const outstanding = outstandingPayments(workspace.payments).slice(0, LIMIT);
  const title = (id: string) => workspace.titles.get(id) ?? "Project";

  return (
    <>
      <Card>
        <CardHeader>
          <CardTitle>Active projects</CardTitle>
          <CardDescription>Projects where the studio has confirmed you.</CardDescription>
        </CardHeader>
        <CardContent className="grid gap-3">
          {active.length === 0 ? (
            <EmptyState title="No active projects">
              Once you accept an offer and the studio confirms you, the project appears here with
              its full brief.
            </EmptyState>
          ) : (
            <ul className="grid gap-3">
              {active.slice(0, LIMIT).map((r) => (
                <li key={r.id} className="grid gap-1 rounded-lg border p-3 text-sm">
                  <div className="flex flex-wrap items-start justify-between gap-2">
                    <Link
                      href={`/editor/projects/${r.id}`}
                      className="min-w-0 font-medium break-words underline"
                    >
                      {r.title}
                    </Link>
                    <StagePill stage={r.stage} />
                  </div>
                  <ActionText action={r.action} />
                </li>
              ))}
            </ul>
          )}
          <SectionLink href="/editor/projects?filter=active">All active projects</SectionLink>
        </CardContent>
      </Card>

      <div className="grid gap-6 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Upcoming deadlines</CardTitle>
            <CardDescription>Deadlines you confirmed with the brief.</CardDescription>
          </CardHeader>
          <CardContent>
            {deadlines.length === 0 ? (
              <EmptyState title="No confirmed deadlines" />
            ) : (
              <ul className="grid gap-2 text-sm">
                {deadlines.map(({ row, overdue }) => (
                  <li key={row.id} className="flex flex-wrap items-center justify-between gap-2">
                    <Link
                      href={`/editor/projects/${row.id}`}
                      className="min-w-0 break-words underline"
                    >
                      {row.title}
                    </Link>
                    <span className="flex items-center gap-2 tabular-nums">
                      {row.deadline}
                      {overdue ? <StatusPill tone="danger">Overdue</StatusPill> : null}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Awaiting review</CardTitle>
            <CardDescription>Submissions the studio is reviewing.</CardDescription>
          </CardHeader>
          <CardContent>
            {inReview.length === 0 ? (
              <EmptyState title="Nothing waiting for review" />
            ) : (
              <ul className="grid gap-2 text-sm">
                {inReview.slice(0, LIMIT).map((r) => (
                  <li key={r.id} className="break-words">
                    <Link href={`/editor/projects/${r.id}?tab=submissions`} className="underline">
                      {r.title}
                    </Link>
                    {r.latestSubmission ? (
                      <span className="text-muted-foreground">
                        {` · version ${r.latestSubmission.version}`}
                      </span>
                    ) : null}
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Open change requests</CardTitle>
          </CardHeader>
          <CardContent className="grid gap-3">
            {openRevisions.length === 0 ? (
              <EmptyState title="No open change requests" />
            ) : (
              <ul className="grid gap-3 text-sm">
                {openRevisions.slice(0, LIMIT).map((r) => (
                  <li key={r.id} className="grid gap-1">
                    <span className="flex flex-wrap items-center gap-2">
                      <Link
                        href={`/editor/projects/${r.projectId}?tab=feedback`}
                        className="min-w-0 break-words underline"
                      >
                        {title(r.projectId)}
                      </Link>
                      <StatusPill tone={REVISION_STATUS_TONE[r.status]}>
                        {REVISION_STATUS_LABEL[r.status]}
                      </StatusPill>
                    </span>
                    <span className="text-muted-foreground">
                      {REVISION_TYPE_LABEL[r.type]}
                      {r.roundNumber ? ` · round ${r.roundNumber}` : ""}
                    </span>
                  </li>
                ))}
              </ul>
            )}
            <SectionLink href="/editor/feedback">All feedback and revisions</SectionLink>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Recent submissions</CardTitle>
          </CardHeader>
          <CardContent>
            {workspace.submissions.length === 0 ? (
              <EmptyState title="No submissions yet" />
            ) : (
              <ul className="grid gap-3 text-sm">
                {workspace.submissions.slice(0, LIMIT).map((s) => (
                  <li key={s.id} className="grid gap-1">
                    <span className="flex flex-wrap items-center gap-2">
                      <Link
                        href={`/editor/projects/${s.projectId}?tab=submissions`}
                        className="min-w-0 break-words underline"
                      >
                        {title(s.projectId)}
                      </Link>
                      <span>version {s.version}</span>
                      {s.outcome ? (
                        <StatusPill tone={OUTCOME_TONE[s.outcome]}>
                          {OUTCOME_LABEL[s.outcome]}
                        </StatusPill>
                      ) : (
                        <StatusPill tone="info">Waiting for review</StatusPill>
                      )}
                    </span>
                    <span className="text-muted-foreground text-xs tabular-nums">
                      {formatDateTime(s.submittedAt)}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Outstanding pay</CardTitle>
          <CardDescription>Your own pay milestones that are not paid yet.</CardDescription>
        </CardHeader>
        <CardContent className="grid gap-3">
          {outstanding.length === 0 ? (
            <EmptyState title="Nothing outstanding" />
          ) : (
            <ul className="grid gap-3 text-sm">
              {outstanding.map((p) => (
                <li key={p.id} className="flex flex-wrap items-center justify-between gap-2">
                  <span className="min-w-0 break-words">
                    {p.projectTitle}
                    <span className="text-muted-foreground">
                      {` · ${lineLabel(p.lineKind, p.milestoneSeq)}`}
                      {p.dueDate ? ` · due ${p.dueDate}` : ""}
                    </span>
                  </span>
                  <span className="flex items-center gap-2">
                    <Money amount={p.amount} currency={p.currency} />
                    <PaymentStatusPill status={p.status} kind={p.kind} />
                  </span>
                </li>
              ))}
            </ul>
          )}
          <SectionLink href="/editor/earnings">Earnings</SectionLink>
        </CardContent>
      </Card>
    </>
  );
}
