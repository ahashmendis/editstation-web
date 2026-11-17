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
import { PaymentStatusPill } from "@/features/payments/components/payment-status-pill";
import { OUTCOME_LABEL, OUTCOME_TONE } from "@/features/submissions/constants";
import {
  ActionText,
  FilterChips,
  Pager,
  SearchSortForm,
  StagePill,
} from "@/features/workspace/components/workspace-ui";
import {
  PROJECT_LIST_FILTERS,
  PROJECT_SORTS,
  paginate,
  parseProjectListParams,
  queryProjectRows,
  shortRef,
  type ProjectListRow,
} from "@/features/workspace/model";
import {
  getEditorWorkspace,
  TRUNCATED_NOTICE,
  type EditorWorkspace,
} from "@/features/workspace/queries";
import { requireActiveEditor } from "@/lib/auth/access";

export const metadata: Metadata = { title: "My projects · EDITSTATION" };

const PAGE_SIZE = 20;
const BASE = "/editor/projects";

export default function EditorProjectsPage({ searchParams }: PageProps<"/editor/projects">) {
  return (
    <Suspense fallback={<Loading />}>
      <ProjectsContent searchParams={searchParams} />
    </Suspense>
  );
}

function ProjectItem({ row }: { row: ProjectListRow }) {
  return (
    <li className="grid gap-3 border-t pt-4 first:border-t-0 first:pt-0">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="grid min-w-0 gap-0.5">
          <Link
            href={`${BASE}/${row.id}`}
            className="focus-visible:ring-ring rounded-sm font-medium break-words underline focus-visible:ring-2 focus-visible:outline-none"
          >
            {row.title}
          </Link>
          <span className="text-muted-foreground font-mono text-xs">Ref {shortRef(row.id)}</span>
        </div>
        <StagePill stage={row.stage} />
      </div>
      <dl className="grid gap-x-6 gap-y-2 text-sm sm:grid-cols-2">
        <div>
          <dt className="text-muted-foreground">Deadline</dt>
          <dd className="tabular-nums">
            {row.deadline ?? "Not set"}
            {row.deadline && !row.deadlineConfirmed ? (
              <span className="text-muted-foreground"> (planned, not confirmed)</span>
            ) : null}
          </dd>
        </div>
        <div>
          <dt className="text-muted-foreground">Last activity</dt>
          <dd className="tabular-nums">{formatDateTime(row.lastActivity)}</dd>
        </div>
        <div className="sm:col-span-2">
          <dt className="text-muted-foreground">Pending action</dt>
          <dd>
            <ActionText action={row.action} />
          </dd>
        </div>
        <div>
          <dt className="text-muted-foreground">Latest submission</dt>
          <dd className="flex flex-wrap items-center gap-2">
            {row.latestSubmission ? (
              <>
                <span>Version {row.latestSubmission.version}</span>
                {row.latestSubmission.outcome ? (
                  <StatusPill tone={OUTCOME_TONE[row.latestSubmission.outcome]}>
                    {OUTCOME_LABEL[row.latestSubmission.outcome]}
                  </StatusPill>
                ) : (
                  <StatusPill tone="info">Waiting for review</StatusPill>
                )}
              </>
            ) : (
              <span className="text-muted-foreground">None yet</span>
            )}
          </dd>
        </div>
        <div>
          <dt className="text-muted-foreground">Change requests</dt>
          <dd className="tabular-nums">{row.revisionCount}</dd>
        </div>
        <div className="sm:col-span-2">
          <dt className="text-muted-foreground">Your pay</dt>
          <dd className="flex flex-wrap items-center gap-2">
            {row.payment ? (
              <>
                <span>{row.payment.label}</span>
                <PaymentStatusPill status={row.payment.status} kind="assignment" />
              </>
            ) : (
              <span className="text-muted-foreground">No pay milestones yet</span>
            )}
          </dd>
        </div>
      </dl>
    </li>
  );
}

async function ProjectsContent({
  searchParams,
}: {
  searchParams: PageProps<"/editor/projects">["searchParams"];
}) {
  await requireActiveEditor();
  const params = parseProjectListParams(await searchParams);
  let data: EditorWorkspace | null = null;
  try {
    data = await getEditorWorkspace();
  } catch {
    data = null;
  }

  return (
    <AreaShell
      title="My projects"
      subtitle="Projects you have been offered or are working on."
      actions={<SignOutButton />}
    >
      {data === null ? (
        <Alert variant="destructive" role="alert">
          <AlertDescription>
            Your projects could not be loaded. Reload the page to try again.
          </AlertDescription>
        </Alert>
      ) : (
        <ProjectResults data={data} params={params} />
      )}
    </AreaShell>
  );
}

function ProjectResults({
  data,
  params,
}: {
  data: EditorWorkspace;
  params: ReturnType<typeof parseProjectListParams>;
}) {
  const shown = queryProjectRows(data.rows, params);
  const page = paginate(shown, params.page, PAGE_SIZE);
  const filter = params.filter === "all" ? null : params.filter;
  const q = params.q || null;
  const sort = params.sort === "activity" ? null : params.sort;

  return (
    <>
      <FilterChips
        label="Filter by status"
        basePath={BASE}
        param="filter"
        options={PROJECT_LIST_FILTERS}
        current={params.filter}
        params={{ q, sort }}
      />
      <SearchSortForm
        action={BASE}
        q={params.q}
        sort={params.sort}
        sorts={PROJECT_SORTS}
        hidden={{ filter }}
      />
      {data.truncated ? <p className="text-muted-foreground text-sm">{TRUNCATED_NOTICE}</p> : null}
      <Card>
        <CardContent>
          {data.rows.length === 0 ? (
            <EmptyState
              title="No projects yet"
              action={
                <Link href="/editor/opportunities" className="text-sm underline">
                  See open opportunities
                </Link>
              }
            >
              When the studio sends you an offer, the project shows up here.
            </EmptyState>
          ) : page.total === 0 ? (
            <EmptyState
              title="No projects match"
              action={
                <Link href={BASE} className="text-sm underline">
                  Clear filters
                </Link>
              }
            >
              Try another status or search.
            </EmptyState>
          ) : (
            <>
              <p className="text-muted-foreground pb-4 text-sm">
                {page.total} project{page.total === 1 ? "" : "s"}
              </p>
              <ul className="grid gap-4">
                {page.items.map((row) => (
                  <ProjectItem key={row.id} row={row} />
                ))}
              </ul>
            </>
          )}
        </CardContent>
      </Card>
      <Pager
        basePath={BASE}
        page={page.page}
        pageCount={page.pageCount}
        params={{ filter, q, sort }}
      />
    </>
  );
}
