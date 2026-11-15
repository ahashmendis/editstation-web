import { EmptyState } from "@/components/empty-state";
import { StatusPill } from "@/components/status-pill";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { editorGateNotice, type RevisionGate } from "@/features/adjustments/constants";
import { formatDateTime } from "@/features/applications/components/status-badge";

import {
  OPEN_REVISION_STATUSES,
  OUTCOME_LABEL,
  OUTCOME_TONE,
  REVISION_STATUS_LABEL,
  REVISION_STATUS_TONE,
  REVISION_TYPE_LABEL,
  roundsSummary,
} from "../constants";
import type { RevisionRow, SubmissionData, SubmissionRow } from "../queries";
import {
  AcknowledgeRevisionForm,
  ApproveSubmissionForm,
  ClassifyRevisionForm,
  CompleteProjectForm,
  ReviewSubmissionForm,
  SubmitWorkForm,
} from "./forms";

function SubmissionItem({ s }: { s: SubmissionRow }) {
  return (
    <li className="grid gap-1 border-t pt-3 first:border-t-0 first:pt-0">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-sm font-medium">Version {s.version}</span>
        {s.outcome ? (
          <StatusPill tone={OUTCOME_TONE[s.outcome]}>{OUTCOME_LABEL[s.outcome]}</StatusPill>
        ) : (
          <StatusPill tone="info">Waiting for review</StatusPill>
        )}
        {s.isLate ? <StatusPill tone="warning">Late</StatusPill> : null}
      </div>
      <p className="text-muted-foreground text-xs">
        Submitted {formatDateTime(s.submittedAt)} · confirmed deadline {s.confirmedDeadline}
      </p>
      <a
        href={s.link}
        target="_blank"
        rel="noopener noreferrer"
        className="text-sm break-all underline"
      >
        {s.link}
      </a>
      {s.notes ? <p className="text-sm whitespace-pre-wrap">{s.notes}</p> : null}
      {s.exportDetails ? (
        <p className="text-muted-foreground text-sm whitespace-pre-wrap">
          Export: {s.exportDetails}
        </p>
      ) : null}
      {s.feedback ? (
        <p className="text-sm whitespace-pre-wrap">
          <span className="font-medium">Feedback: </span>
          {s.feedback}
        </p>
      ) : null}
    </li>
  );
}

function SubmissionHistory({ rows }: { rows: SubmissionRow[] }) {
  if (rows.length === 0)
    return <EmptyState title="No submissions yet">Submitted versions appear here.</EmptyState>;
  return (
    <ul className="grid gap-3">
      {rows.map((s) => (
        <SubmissionItem key={s.id} s={s} />
      ))}
    </ul>
  );
}

function RevisionHeading({ r }: { r: RevisionRow }) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      <span className="text-sm font-medium">{REVISION_TYPE_LABEL[r.type]}</span>
      {r.roundNumber ? <span className="text-sm">· round {r.roundNumber}</span> : null}
      <StatusPill tone={REVISION_STATUS_TONE[r.status]}>
        {REVISION_STATUS_LABEL[r.status]}
      </StatusPill>
      {r.beyondAllowance ? <StatusPill tone="warning">Beyond included rounds</StatusPill> : null}
      {!r.countsAgainstAllowance ? (
        <span className="text-muted-foreground text-xs">Does not use an included round</span>
      ) : null}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Editor
// ---------------------------------------------------------------------------

export function EditorSubmissionsPanel({
  projectId,
  assignmentId,
  projectStatus,
  data,
  gates = {},
}: {
  projectId: string;
  assignmentId: string;
  projectStatus: string;
  data: SubmissionData;
  /** Gate codes of requests not yet begun (extra pay or scope approval pending). */
  gates?: Record<string, RevisionGate | "unknown">;
}) {
  const submissions = data.submissions.filter((s) => s.assignmentId === assignmentId);
  const revisions = data.revisions.filter((r) => r.assignmentId === assignmentId);
  const pending = submissions.some((s) => s.outcome === null);
  const open = revisions.find((r) => OPEN_REVISION_STATUSES.includes(r.status));
  const openGate = open?.status === "requested" ? (gates[open.id] ?? "ok") : "ok";
  const canSubmit =
    (projectStatus === "in_progress" || projectStatus === "revision_requested") &&
    !pending &&
    open?.status !== "disputed" &&
    openGate === "ok";

  return (
    <Card>
      <CardHeader>
        <CardTitle>Submissions</CardTitle>
        <CardDescription>
          Each submission is kept as a numbered version with the studio&apos;s feedback.
        </CardDescription>
      </CardHeader>
      <CardContent className="grid gap-6">
        {projectStatus === "approved" || projectStatus === "completed" ? (
          <p className="text-sm">
            {projectStatus === "approved"
              ? "The studio approved your work."
              : "This project is completed."}
          </p>
        ) : null}
        {pending ? (
          <p className="text-muted-foreground text-sm">
            Your latest submission is waiting for review.
          </p>
        ) : null}
        {open?.status === "disputed" ? (
          <p className="text-muted-foreground text-sm">
            The studio is discussing the last review. You can resubmit once it is classified.
          </p>
        ) : null}
        {canSubmit ? (
          <section className="grid gap-3">
            <h3 className="text-sm font-medium">
              {open ? "Submit your revised work" : "Submit work"}
            </h3>
            <SubmitWorkForm projectId={projectId} assignmentId={assignmentId} />
          </section>
        ) : null}

        <section className="grid gap-3">
          <h3 className="text-sm font-medium">Change requests</h3>
          {revisions.length === 0 ? (
            <p className="text-muted-foreground text-sm">No change requests.</p>
          ) : (
            <ul className="grid gap-4">
              {revisions.map((r) => (
                <li key={r.id} className="grid gap-2">
                  <RevisionHeading r={r} />
                  <p className="text-sm whitespace-pre-wrap">{r.reason}</p>
                  {r.status === "requested" && editorGateNotice(gates[r.id]) ? (
                    <p role="status" className="bg-muted rounded-md p-3 text-sm">
                      {editorGateNotice(gates[r.id])}
                    </p>
                  ) : r.status === "requested" || r.status === "acknowledged" ? (
                    <div className="flex flex-wrap gap-2">
                      {r.status === "requested" ? (
                        <AcknowledgeRevisionForm
                          projectId={projectId}
                          revisionId={r.id}
                          start={false}
                        />
                      ) : null}
                      <AcknowledgeRevisionForm projectId={projectId} revisionId={r.id} start />
                    </div>
                  ) : null}
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="grid gap-3">
          <h3 className="text-sm font-medium">History</h3>
          <SubmissionHistory rows={submissions} />
        </section>
      </CardContent>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Admin
// ---------------------------------------------------------------------------

export function AdminReviewPanel({
  projectId,
  projectStatus,
  revisionAllowance,
  data,
}: {
  projectId: string;
  projectStatus: string;
  revisionAllowance: number;
  data: SubmissionData;
}) {
  const pending = projectStatus === "in_review" ? data.submissions.find((s) => !s.outcome) : null;
  const open = data.revisions.filter((r) => OPEN_REVISION_STATUSES.includes(r.status));
  const rounds = roundsSummary(data.revisions, revisionAllowance);
  const corrections = data.revisions.filter((r) => r.type === "editor_correction").length;
  const scopeChanges = data.revisions.filter((r) => r.type === "scope_change").length;
  const lateCount = data.submissions.filter((s) => s.isLate).length;

  return (
    <Card>
      <CardHeader>
        <CardTitle>Review</CardTitle>
        <CardDescription>
          Review each version against the brief. Only client revisions use the included rounds.
        </CardDescription>
      </CardHeader>
      <CardContent className="grid gap-6">
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span>
            Client rounds used:{" "}
            <strong className="tabular-nums">
              {rounds.used}/{rounds.allowance}
            </strong>
          </span>
          {rounds.beyond > 0 ? (
            <StatusPill tone="warning">{`Beyond included rounds (+${rounds.beyond})`}</StatusPill>
          ) : null}
          <span className="text-muted-foreground">
            · {corrections} editor correction{corrections === 1 ? "" : "s"} · {scopeChanges} scope
            change{scopeChanges === 1 ? "" : "s"}
            {lateCount > 0 ? ` · ${lateCount} late submission${lateCount === 1 ? "" : "s"}` : ""}
          </span>
        </div>
        {rounds.beyond > 0 ? (
          <p className="text-muted-foreground text-sm">
            Charge chargeable rounds to the client and offer extra editor pay under Extra pay and
            client charges below.
          </p>
        ) : null}

        {pending ? (
          <section className="grid gap-3">
            <h3 className="text-sm font-medium">Waiting for review</h3>
            <ul>
              <SubmissionItem s={pending} />
            </ul>
            <ApproveSubmissionForm projectId={projectId} submissionId={pending.id} />
            <ReviewSubmissionForm projectId={projectId} submissionId={pending.id} />
          </section>
        ) : null}

        {open.length > 0 ? (
          <section className="grid gap-4">
            <h3 className="text-sm font-medium">Open change requests</h3>
            {open.map((r) => (
              <div key={r.id} className="grid gap-2">
                <RevisionHeading r={r} />
                <p className="text-sm whitespace-pre-wrap">{r.reason}</p>
                <ClassifyRevisionForm projectId={projectId} revisionId={r.id} current={r.type} />
              </div>
            ))}
          </section>
        ) : null}

        {projectStatus === "approved" ? <CompleteProjectForm projectId={projectId} /> : null}

        <details>
          <summary className="cursor-pointer text-sm font-medium">
            All submissions ({data.submissions.length}) and change requests ({data.revisions.length}
            )
          </summary>
          <div className="grid gap-4 pt-3">
            <SubmissionHistory rows={data.submissions} />
            {data.revisions.length > 0 ? (
              <ul className="grid gap-3">
                {data.revisions.map((r) => (
                  <li key={r.id} className="grid gap-1">
                    <RevisionHeading r={r} />
                    <p className="text-muted-foreground text-sm whitespace-pre-wrap">{r.reason}</p>
                  </li>
                ))}
              </ul>
            ) : null}
          </div>
        </details>
      </CardContent>
    </Card>
  );
}
