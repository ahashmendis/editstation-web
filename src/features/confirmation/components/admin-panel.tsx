import { EmptyState } from "@/components/empty-state";
import { StatusPill } from "@/components/status-pill";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { StayForm } from "@/features/access/components/stay-form";
import { formatMoney } from "@/features/access/constants";
import { formatDateTime } from "@/features/applications/components/status-badge";

import { adminStartWorkAction, reviewInterpretationAction } from "../admin-actions";
import {
  CONFIRMATION_KIND_LABEL,
  INTERPRETATION_LABEL,
  INTERPRETATION_TONE,
  driftReasons,
  gateChecklist,
  gateState,
} from "../constants";
import type { AssignmentConfirmation } from "../queries";
import { RequestChangesForm } from "./forms";

export type AdminConfirmationEntry = {
  assignmentId: string;
  editorName: string;
  assignmentStatus: "confirmed" | "in_progress";
  data: AssignmentConfirmation;
};

/** One card per confirmed or in-progress assignment: gate, interpretation, confirmations. */
export function AdminConfirmationPanel({
  projectId,
  entries,
  startable,
}: {
  projectId: string;
  entries: AdminConfirmationEntry[];
  /** Project is open to action (not archived, cancelled or on hold). */
  startable: boolean;
}) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Confirmation and start</CardTitle>
        <CardDescription>
          The confirmed editor interprets the brief where required, confirms it, and then work can
          start. The database refuses a start until every check below is done.
        </CardDescription>
      </CardHeader>
      <CardContent className="grid gap-6">
        {entries.length === 0 ? (
          <EmptyState title="No confirmed editor yet">
            This section fills in after you confirm an editor.
          </EmptyState>
        ) : (
          entries.map((e) => (
            <EditorEntry
              key={e.assignmentId}
              projectId={projectId}
              entry={e}
              startable={startable}
            />
          ))
        )}
      </CardContent>
    </Card>
  );
}

function EditorEntry({
  projectId,
  entry,
  startable,
}: {
  projectId: string;
  entry: AdminConfirmationEntry;
  startable: boolean;
}) {
  const { data, assignmentStatus } = entry;
  const { gate } = data;
  if (!gate) {
    return (
      <div className="grid gap-2 rounded-lg border p-3">
        <p className="text-sm font-medium">{entry.editorName}</p>
        <p className="text-muted-foreground text-sm">The gate status could not be loaded.</p>
      </div>
    );
  }
  const latest = data.interpretations[0] ?? null;
  const state = gateState(gate, assignmentStatus, latest?.status ?? null);
  const drift = driftReasons(gate);
  const pending = data.interpretations.find((i) => i.status === "submitted") ?? null;

  return (
    <section className="grid gap-4 rounded-lg border p-3" aria-label={entry.editorName}>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h3 className="text-sm font-medium">{entry.editorName}</h3>
        <StatusPill tone={state.tone}>{state.label}</StatusPill>
      </div>

      {drift.length > 0 ? (
        <div role="status" className="grid gap-1 rounded-lg border p-3 text-sm">
          <p className="font-medium">Re-confirmation needed</p>
          <ul className="text-muted-foreground list-disc pl-5">
            {drift.map((r) => (
              <li key={r}>{r}</li>
            ))}
          </ul>
        </div>
      ) : null}

      <ul className="grid gap-2 text-sm">
        {gateChecklist(gate, "admin").map((item) => (
          <li key={item.key} className="flex items-start gap-2">
            <span aria-hidden className="mt-0.5 w-4 shrink-0">
              {item.met ? "✓" : "○"}
            </span>
            <span>
              <span className="font-medium">{item.label}</span>
              <span className="text-muted-foreground">
                {item.met ? " (done)" : " (missing)"}
                {item.detail ? ` ${item.detail}` : ""}
              </span>
            </span>
          </li>
        ))}
      </ul>

      {assignmentStatus === "confirmed" ? (
        gate.ready && startable ? (
          <StayForm
            action={adminStartWorkAction}
            submitLabel="Start work for the editor"
            confirm="Start work now?"
          >
            <input type="hidden" name="projectId" value={projectId} />
            <input type="hidden" name="assignmentId" value={entry.assignmentId} />
          </StayForm>
        ) : (
          <p className="text-muted-foreground text-sm">
            {gate.ready
              ? "Starting is unavailable while the project is closed or on hold."
              : "Work can start once every check is done."}
          </p>
        )
      ) : null}

      {gate.interpretation_required ? (
        <div className="grid gap-3 border-t pt-3">
          <h4 className="text-sm font-medium">Interpretation</h4>
          {data.interpretations.length === 0 ? (
            <p className="text-muted-foreground text-sm">Nothing submitted yet.</p>
          ) : (
            <ul className="grid gap-3">
              {data.interpretations.map((i) => (
                <li key={i.id} className="grid gap-2 rounded-lg border p-3 text-sm">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <span className="flex flex-wrap items-center gap-2">
                      <StatusPill tone={INTERPRETATION_TONE[i.status]}>
                        {INTERPRETATION_LABEL[i.status]}
                      </StatusPill>
                      <span className="text-muted-foreground">
                        for brief version {i.briefVersion}
                      </span>
                    </span>
                    <span className="text-muted-foreground tabular-nums">
                      {formatDateTime(i.submittedAt)}
                    </span>
                  </div>
                  <div>
                    <p className="text-muted-foreground">Will reproduce</p>
                    <p className="whitespace-pre-line">{i.willReproduce ?? "Not given"}</p>
                  </div>
                  <div>
                    <p className="text-muted-foreground">Will adapt</p>
                    <p className="whitespace-pre-line">{i.willAdapt ?? "Not given"}</p>
                  </div>
                  {i.questions ? (
                    <div>
                      <p className="text-muted-foreground">Questions or limitations</p>
                      <p className="whitespace-pre-line">{i.questions}</p>
                    </div>
                  ) : null}
                  {i.adminFeedback ? (
                    <div>
                      <p className="text-muted-foreground">Your feedback</p>
                      <p className="whitespace-pre-line">{i.adminFeedback}</p>
                    </div>
                  ) : null}
                  {pending && pending.id === i.id ? (
                    <div className="grid gap-4 border-t pt-3 sm:grid-cols-2">
                      <StayForm action={reviewInterpretationAction} submitLabel="Accept">
                        <input type="hidden" name="projectId" value={projectId} />
                        <input type="hidden" name="interpretationId" value={i.id} />
                        <input type="hidden" name="decision" value="accept" />
                      </StayForm>
                      <RequestChangesForm projectId={projectId} interpretationId={i.id} />
                    </div>
                  ) : null}
                </li>
              ))}
            </ul>
          )}
        </div>
      ) : null}

      <div className="grid gap-3 border-t pt-3">
        <h4 className="text-sm font-medium">Confirmation history</h4>
        {data.confirmations.length === 0 ? (
          <p className="text-muted-foreground text-sm">The editor has not confirmed the brief.</p>
        ) : (
          <ul className="grid gap-2 text-sm">
            {data.confirmations.map((c) => (
              <li key={c.id} className="grid gap-1 rounded-lg border p-3">
                <div className="flex flex-wrap justify-between gap-2">
                  <span className="font-medium">
                    Version {c.briefVersion} · {CONFIRMATION_KIND_LABEL[c.kind]}
                  </span>
                  <span className="text-muted-foreground tabular-nums">
                    {formatDateTime(c.confirmedAt)}
                  </span>
                </div>
                <p className="text-muted-foreground">
                  Deadline {c.deadline} · {c.deliverableCount}{" "}
                  {c.deliverableCount === 1 ? "deliverable" : "deliverables"} ·{" "}
                  {formatMoney(c.amount, c.currency)}
                </p>
              </li>
            ))}
          </ul>
        )}
      </div>
    </section>
  );
}
