import type { StatusTone } from "@/components/status-pill";

export const SUBMISSION_OUTCOMES = [
  "approved",
  "revision_requested",
  "rejected_needs_discussion",
  "scope_change_required",
] as const;
export type SubmissionOutcome = (typeof SUBMISSION_OUTCOMES)[number];

export const REVISION_TYPES = ["client_revision", "editor_correction", "scope_change"] as const;
export type RevisionType = (typeof REVISION_TYPES)[number];

export type RevisionStatus =
  "requested" | "acknowledged" | "in_progress" | "resubmitted" | "approved" | "disputed";

export const OUTCOME_LABEL: Record<SubmissionOutcome, string> = {
  approved: "Approved",
  revision_requested: "Revision requested",
  rejected_needs_discussion: "Needs discussion",
  scope_change_required: "Scope change required",
};

export const OUTCOME_TONE: Record<SubmissionOutcome, StatusTone> = {
  approved: "success",
  revision_requested: "warning",
  rejected_needs_discussion: "danger",
  scope_change_required: "warning",
};

export const REVISION_TYPE_LABEL: Record<RevisionType, string> = {
  client_revision: "Client revision",
  editor_correction: "Editor correction",
  scope_change: "Scope change",
};

export const REVISION_STATUS_LABEL: Record<RevisionStatus, string> = {
  requested: "Requested",
  acknowledged: "Acknowledged",
  in_progress: "In progress",
  resubmitted: "Resubmitted",
  approved: "Approved",
  disputed: "Under discussion",
};

export const REVISION_STATUS_TONE: Record<RevisionStatus, StatusTone> = {
  requested: "warning",
  acknowledged: "info",
  in_progress: "info",
  resubmitted: "info",
  approved: "success",
  disputed: "danger",
};

export const OPEN_REVISION_STATUSES: readonly RevisionStatus[] = [
  "requested",
  "acknowledged",
  "in_progress",
  "disputed",
];

/** Client rounds used against the project's allowance (facts only; extra-round pay is open question F). */
export function roundsSummary(
  revisions: readonly { type: RevisionType; roundNumber: number | null }[],
  allowance: number,
): { used: number; allowance: number; beyond: number } {
  const used = revisions.reduce(
    (max, r) =>
      r.type === "client_revision" && r.roundNumber ? Math.max(max, r.roundNumber) : max,
    0,
  );
  return { used, allowance, beyond: Math.max(0, used - allowance) };
}
