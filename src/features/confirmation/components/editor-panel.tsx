import { EmptyState } from "@/components/empty-state";
import { StatusPill } from "@/components/status-pill";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { StayForm } from "@/features/access/components/stay-form";
import { formatMoney } from "@/features/access/constants";
import { formatDateTime } from "@/features/applications/components/status-badge";

import { confirmBriefAction, startWorkAction } from "../editor-actions";
import { InterpretationForm } from "./forms";
import {
  INTERPRETATION_LABEL,
  INTERPRETATION_TONE,
  driftReasons,
  gateChecklist,
  gateState,
} from "../constants";
import type { AssignmentConfirmation } from "../queries";

type Props = {
  projectId: string;
  assignmentId: string;
  assignmentStatus: "confirmed" | "in_progress";
  /** Project is archived, on hold or otherwise not workable: actions are paused. */
  paused: boolean;
  deadline: string | null;
  deliverables: { id: string; name: string }[];
  agreedAmount: number | null;
  agreedCurrency: string | null;
  data: AssignmentConfirmation;
};

function Checklist({ items }: { items: ReturnType<typeof gateChecklist> }) {
  return (
    <ul className="grid gap-2 text-sm">
      {items.map((item) => (
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
  );
}

export function EditorConfirmationPanel(props: Props) {
  const { data, assignmentStatus, paused, projectId, assignmentId } = props;
  const { gate } = data;

  if (!gate) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Before you start</CardTitle>
        </CardHeader>
        <CardContent>
          <EmptyState title="Status not available">
            Reload the page. If this stays, tell the studio.
          </EmptyState>
        </CardContent>
      </Card>
    );
  }

  const latest = data.interpretations[0] ?? null;
  const state = gateState(gate, assignmentStatus, latest?.status ?? null);
  const checklist = gateChecklist(gate, "editor");
  const drift = driftReasons(gate);
  const canInterpret =
    gate.interpretation_required &&
    !gate.interpretation_accepted &&
    latest?.status !== "submitted" &&
    !paused;
  const interpretationOk = !gate.interpretation_required || gate.interpretation_accepted;
  const canConfirm =
    !gate.brief_confirmed &&
    interpretationOk &&
    gate.compensation_approved &&
    props.deadline !== null &&
    props.agreedAmount !== null &&
    props.agreedCurrency !== null &&
    !paused;
  const started = assignmentStatus === "in_progress";
  // Everything the editor controls is done; only the client deposit (a status, never an amount).
  const waitingForDeposit =
    !gate.client_deposit_verified &&
    gate.brief_confirmed &&
    interpretationOk &&
    gate.compensation_approved;

  return (
    <>
      <Card>
        <CardHeader>
          <div className="flex flex-wrap items-center gap-3">
            <CardTitle>{started ? "Work in progress" : "Before you start"}</CardTitle>
            <StatusPill tone={state.tone}>{state.label}</StatusPill>
          </div>
          <CardDescription>
            {started
              ? "If the brief, deadline or pay changes, you will be asked to confirm again before you continue."
              : "Work starts when the pay is approved, you have confirmed the brief, your interpretation is accepted where asked, and the studio has confirmed the client deposit."}
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4">
          {drift.length > 0 ? (
            <div role="status" className="grid gap-1 rounded-lg border p-3 text-sm">
              <p className="font-medium">Please confirm again</p>
              <ul className="text-muted-foreground list-disc pl-5">
                {drift.map((reason) => (
                  <li key={reason}>{reason}</li>
                ))}
              </ul>
            </div>
          ) : null}

          <Checklist items={checklist} />

          {!started ? (
            gate.ready ? (
              <StayForm action={startWorkAction} submitLabel="Start work">
                <input type="hidden" name="projectId" value={projectId} />
                <input type="hidden" name="assignmentId" value={assignmentId} />
              </StayForm>
            ) : (
              <div className="grid gap-2">
                <button
                  type="button"
                  disabled
                  className="bg-muted text-muted-foreground h-9 justify-self-start rounded-lg px-4 text-sm"
                >
                  Start work
                </button>
                <p className="text-muted-foreground text-sm" role="status">
                  {waitingForDeposit
                    ? "Waiting for the client deposit. Start work unlocks once the studio confirms it."
                    : "Start work unlocks when every item above is done."}
                </p>
              </div>
            )
          ) : null}
          {!started && gate.ready && paused ? (
            <p className="text-muted-foreground text-sm">
              Starting is paused while the project is on hold.
            </p>
          ) : null}
        </CardContent>
      </Card>

      {gate.interpretation_required ? (
        <Card>
          <CardHeader>
            <div className="flex flex-wrap items-center gap-3">
              <CardTitle>Your interpretation</CardTitle>
              {latest ? (
                <StatusPill tone={INTERPRETATION_TONE[latest.status]}>
                  {INTERPRETATION_LABEL[latest.status]}
                </StatusPill>
              ) : null}
            </div>
            <CardDescription>
              The studio asks for a short note on how you will use the references before you start.
            </CardDescription>
          </CardHeader>
          <CardContent className="grid gap-5">
            {latest?.status === "changes_requested" && latest.adminFeedback ? (
              <div role="status" className="grid gap-1 rounded-lg border p-3 text-sm">
                <p className="font-medium">The studio asked for changes</p>
                <p className="whitespace-pre-line">{latest.adminFeedback}</p>
              </div>
            ) : null}
            {latest?.status === "submitted" ? (
              <p className="text-muted-foreground text-sm">
                Sent {formatDateTime(latest.submittedAt)}. The studio will reply here.
              </p>
            ) : null}
            {gate.interpretation_accepted ? (
              <p className="text-muted-foreground text-sm">
                The studio accepted your interpretation. You will be asked for a new one only if the
                brief changes in a way that needs it.
              </p>
            ) : null}
            {canInterpret ? (
              <InterpretationForm
                projectId={projectId}
                assignmentId={assignmentId}
                briefVersion={gate.current_brief_version}
                willReproduce={latest?.willReproduce ?? undefined}
                willAdapt={latest?.willAdapt ?? undefined}
                questions={latest?.questions ?? undefined}
              />
            ) : null}
            {data.interpretations.length > 1 ? (
              <details>
                <summary className="cursor-pointer text-sm font-medium">Earlier versions</summary>
                <ul className="grid gap-3 pt-3 text-sm">
                  {data.interpretations.slice(1).map((i) => (
                    <li key={i.id} className="grid gap-1 rounded-lg border p-3">
                      <div className="flex flex-wrap justify-between gap-2">
                        <span>{INTERPRETATION_LABEL[i.status]}</span>
                        <span className="text-muted-foreground tabular-nums">
                          {formatDateTime(i.submittedAt)}
                        </span>
                      </div>
                      {i.adminFeedback ? (
                        <p className="whitespace-pre-line">Studio: {i.adminFeedback}</p>
                      ) : null}
                    </li>
                  ))}
                </ul>
              </details>
            ) : null}
          </CardContent>
        </Card>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle>Confirm the brief</CardTitle>
          <CardDescription>
            By confirming you agree to deliver this brief version by this deadline for this pay.
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4">
          <dl className="grid gap-3 text-sm sm:grid-cols-3">
            <div>
              <dt className="text-muted-foreground">Brief version</dt>
              <dd>{gate.current_brief_version}</dd>
            </div>
            <div>
              <dt className="text-muted-foreground">Deadline</dt>
              <dd>{props.deadline ?? "Not set"}</dd>
            </div>
            <div>
              <dt className="text-muted-foreground">Agreed pay</dt>
              <dd className="tabular-nums">
                {props.agreedAmount === null
                  ? "Not agreed"
                  : formatMoney(props.agreedAmount, props.agreedCurrency)}
              </dd>
            </div>
          </dl>
          <div className="grid gap-1 text-sm">
            <h3 className="font-medium">Deliverables</h3>
            {props.deliverables.length === 0 ? (
              <p className="text-muted-foreground">No deliverables listed.</p>
            ) : (
              <ul className="list-disc pl-5">
                {props.deliverables.map((d) => (
                  <li key={d.id}>{d.name}</li>
                ))}
              </ul>
            )}
          </div>

          {gate.brief_confirmed ? (
            <p className="text-sm">You have confirmed version {gate.current_brief_version}.</p>
          ) : canConfirm ? (
            <StayForm
              action={confirmBriefAction}
              submitLabel={
                gate.confirmed_brief_version === null ? "Confirm the brief" : "Confirm again"
              }
              confirm="Confirm this version, deadline and pay?"
            >
              <input type="hidden" name="projectId" value={projectId} />
              <input type="hidden" name="assignmentId" value={assignmentId} />
              <input type="hidden" name="briefVersion" value={gate.current_brief_version} />
              <input type="hidden" name="deadline" value={props.deadline ?? ""} />
              <input type="hidden" name="amount" value={props.agreedAmount ?? ""} />
              <input type="hidden" name="currency" value={props.agreedCurrency ?? ""} />
            </StayForm>
          ) : (
            <p className="text-muted-foreground text-sm">
              {!interpretationOk
                ? "You can confirm once the studio accepts your interpretation."
                : props.deadline === null
                  ? "The studio has not set a deadline yet."
                  : paused
                    ? "Confirming is paused while the project is on hold."
                    : "Confirming is not available yet."}
            </p>
          )}

          {data.confirmations.length > 0 ? (
            <details>
              <summary className="cursor-pointer text-sm font-medium">Your confirmations</summary>
              <ul className="grid gap-2 pt-3 text-sm">
                {data.confirmations.map((c) => (
                  <li key={c.id} className="flex flex-wrap justify-between gap-2">
                    <span>
                      Version {c.briefVersion}
                      {c.kind === "carried_forward" ? " (carried forward)" : ""}
                    </span>
                    <span className="text-muted-foreground tabular-nums">
                      {formatDateTime(c.confirmedAt)}
                    </span>
                  </li>
                ))}
              </ul>
            </details>
          ) : null}
        </CardContent>
      </Card>
    </>
  );
}
