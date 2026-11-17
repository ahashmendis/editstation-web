import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { EmptyState } from "@/components/empty-state";
import { SignOutButton } from "@/components/sign-out-button";
import { StatusPill } from "@/components/status-pill";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Card, CardContent } from "@/components/ui/card";
import { formatDateTime } from "@/features/applications/components/status-badge";
import {
  REVISION_STATUS_LABEL,
  REVISION_STATUS_TONE,
  REVISION_TYPE_LABEL,
} from "@/features/submissions/constants";
import { FilterChips, Pager } from "@/features/workspace/components/workspace-ui";
import {
  FEEDBACK_FILTERS,
  feedbackGroupOf,
  paginate,
  parseFeedbackParams,
} from "@/features/workspace/model";
import {
  getEditorWorkspace,
  TRUNCATED_NOTICE,
  type EditorWorkspace,
} from "@/features/workspace/queries";
import { requireActiveEditor } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Feedback and revisions · EDITSTATION" };

const PAGE_SIZE = 20;
const BASE = "/editor/feedback";

export default function EditorFeedbackPage({ searchParams }: PageProps<"/editor/feedback">) {
  return (
    <Suspense fallback={<Loading />}>
      <FeedbackContent searchParams={searchParams} />
    </Suspense>
  );
}

async function FeedbackContent({
  searchParams,
}: {
  searchParams: PageProps<"/editor/feedback">["searchParams"];
}) {
  await requireActiveEditor();
  const params = parseFeedbackParams(await searchParams);
  let data: EditorWorkspace | null = null;
  try {
    data = await getEditorWorkspace();
  } catch {
    data = null;
  }

  return (
    <AreaShell
      title="Feedback and revisions"
      subtitle="Change requests from the studio across your projects."
      actions={<SignOutButton />}
    >
      {data === null ? (
        <Alert variant="destructive" role="alert">
          <AlertDescription>
            Change requests could not be loaded. Reload the page to try again.
          </AlertDescription>
        </Alert>
      ) : (
        <FeedbackList data={data} params={params} />
      )}
    </AreaShell>
  );
}

function FeedbackList({
  data,
  params,
}: {
  data: EditorWorkspace;
  params: ReturnType<typeof parseFeedbackParams>;
}) {
  const versionOf = new Map(data.submissions.map((s) => [s.id, s.version]));
  const shown =
    params.status === "all"
      ? data.revisions
      : data.revisions.filter((r) => feedbackGroupOf(r.status) === params.status);
  const page = paginate(shown, params.page, PAGE_SIZE);
  const status = params.status === "all" ? null : params.status;

  return (
    <>
      <FilterChips
        label="Filter by status"
        basePath={BASE}
        param="status"
        options={FEEDBACK_FILTERS}
        current={params.status}
      />
      {data.truncated ? <p className="text-muted-foreground text-sm">{TRUNCATED_NOTICE}</p> : null}
      <Card>
        <CardContent>
          {data.revisions.length === 0 ? (
            <EmptyState title="No change requests">
              When the studio asks for changes to a submission, the request shows up here.
            </EmptyState>
          ) : page.total === 0 ? (
            <EmptyState
              title="Nothing in this view"
              action={
                <Link href={BASE} className="text-sm underline">
                  Show all
                </Link>
              }
            >
              No change requests have this status.
            </EmptyState>
          ) : (
            <ul className="grid gap-4">
              {page.items.map((r) => {
                const version = versionOf.get(r.submissionId);
                return (
                  <li key={r.id} className="grid gap-2 border-t pt-4 first:border-t-0 first:pt-0">
                    <div className="flex flex-wrap items-start justify-between gap-2">
                      <Link
                        href={`/editor/projects/${r.projectId}?tab=feedback`}
                        className="focus-visible:ring-ring rounded-sm font-medium break-words underline focus-visible:ring-2 focus-visible:outline-none"
                      >
                        {data.titles.get(r.projectId) ?? "Project"}
                      </Link>
                      <StatusPill tone={REVISION_STATUS_TONE[r.status]}>
                        {REVISION_STATUS_LABEL[r.status]}
                      </StatusPill>
                    </div>
                    <p className="text-muted-foreground text-sm">
                      {[
                        REVISION_TYPE_LABEL[r.type],
                        r.roundNumber ? `round ${r.roundNumber}` : null,
                        version ? `on version ${version}` : null,
                        `requested ${formatDateTime(r.createdAt)}`,
                      ]
                        .filter(Boolean)
                        .join(" · ")}
                    </p>
                    <p className="text-sm break-words whitespace-pre-wrap">{r.reason}</p>
                  </li>
                );
              })}
            </ul>
          )}
        </CardContent>
      </Card>
      <Pager basePath={BASE} page={page.page} pageCount={page.pageCount} params={{ status }} />
    </>
  );
}
