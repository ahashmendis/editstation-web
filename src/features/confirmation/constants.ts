import type { StatusTone } from "@/components/status-pill";

/**
 * One row of `get_assignment_gate` (Phase 7 spec section 7; Phase 12C adds the client deposit,
 * which the editor sees only as a yes/no status, never an amount).
 */
export type GateRow = {
  compensation_approved: boolean;
  interpretation_required: boolean;
  interpretation_accepted: boolean;
  current_brief_version: number;
  confirmed_brief_version: number | null;
  reacknowledgement_required: boolean;
  deadline_changed: boolean;
  amount_changed: boolean;
  deliverables_changed: boolean;
  brief_confirmed: boolean;
  client_deposit_verified: boolean;
  ready: boolean;
};

export type InterpretationStatus = "submitted" | "accepted" | "changes_requested";

export const INTERPRETATION_LABEL: Record<InterpretationStatus, string> = {
  submitted: "Waiting for review",
  accepted: "Accepted",
  changes_requested: "Changes requested",
};

export const INTERPRETATION_TONE: Record<InterpretationStatus, StatusTone> = {
  submitted: "warning",
  accepted: "success",
  changes_requested: "warning",
};

export type ConfirmationKind = "confirmed" | "carried_forward";

export const CONFIRMATION_KIND_LABEL: Record<ConfirmationKind, string> = {
  confirmed: "Confirmed by the editor",
  carried_forward: "Carried forward",
};

export type GateItem = { key: string; label: string; met: boolean; detail: string | null };

/** What must hold before work starts, in the order the editor does it. */
export function gateChecklist(gate: GateRow, role: "editor" | "admin"): GateItem[] {
  const who = role === "editor" ? "You have" : "The editor has";
  const items: GateItem[] = [
    {
      key: "pay",
      label: "Pay agreed and approved by the studio",
      met: gate.compensation_approved,
      detail: gate.compensation_approved ? null : "The studio has not approved the pay yet.",
    },
  ];
  if (gate.interpretation_required) {
    items.push({
      key: "interpretation",
      label: "Interpretation accepted by the studio",
      met: gate.interpretation_accepted,
      detail: gate.interpretation_accepted
        ? null
        : `${who} not had an interpretation accepted for the current brief.`,
    });
  }
  let briefDetail: string | null = null;
  if (!gate.brief_confirmed) {
    if (gate.confirmed_brief_version === null) {
      briefDetail = `Version ${gate.current_brief_version} is not confirmed yet.`;
    } else if (gate.reacknowledgement_required) {
      briefDetail = `The brief changed to version ${gate.current_brief_version} and needs confirming again.`;
    } else if (gate.deadline_changed) {
      briefDetail = "The deadline changed since the brief was confirmed.";
    } else if (gate.amount_changed) {
      briefDetail = "The agreed pay changed since the brief was confirmed.";
    }
  }
  items.push({
    key: "brief",
    label: `Brief confirmed for the current version (${gate.current_brief_version})`,
    met: gate.brief_confirmed,
    detail: briefDetail,
  });
  items.push({
    key: "deposit",
    label: "Client deposit confirmed by the studio",
    met: gate.client_deposit_verified,
    detail: gate.client_deposit_verified ? null : "Waiting for the client deposit.",
  });
  return items;
}

/** Why a confirmation no longer holds, in plain words. Empty when it holds. */
export function driftReasons(gate: GateRow): string[] {
  if (gate.confirmed_brief_version === null) return [];
  const reasons: string[] = [];
  if (gate.reacknowledgement_required) {
    reasons.push(
      `The brief is now version ${gate.current_brief_version}; the last confirmation was for version ${gate.confirmed_brief_version}.`,
    );
  }
  if (gate.deadline_changed) reasons.push("The deadline changed after it was confirmed.");
  if (gate.amount_changed) reasons.push("The agreed pay changed after it was confirmed.");
  if (gate.deliverables_changed) reasons.push("The deliverables changed after it was confirmed.");
  return reasons;
}

export type GateStateLabel =
  | "Awaiting interpretation"
  | "Interpretation to review"
  | "Awaiting brief confirmation"
  | "Waiting for the client deposit"
  | "Ready to start"
  | "In progress"
  | "Re-confirmation needed";

/** Derived label (decision J); never stored. */
export function gateState(
  gate: GateRow,
  assignmentStatus: "confirmed" | "in_progress",
  latestInterpretation: InterpretationStatus | null,
): { label: GateStateLabel; tone: StatusTone } {
  const interpretationOk = !gate.interpretation_required || gate.interpretation_accepted;
  if (!interpretationOk) {
    if (assignmentStatus === "in_progress") {
      return { label: "Re-confirmation needed", tone: "warning" };
    }
    return latestInterpretation === "submitted"
      ? { label: "Interpretation to review", tone: "warning" }
      : { label: "Awaiting interpretation", tone: "info" };
  }
  if (!gate.brief_confirmed) {
    return gate.confirmed_brief_version !== null
      ? { label: "Re-confirmation needed", tone: "warning" }
      : { label: "Awaiting brief confirmation", tone: "info" };
  }
  if (assignmentStatus === "in_progress") return { label: "In progress", tone: "success" };
  if (!gate.client_deposit_verified)
    return { label: "Waiting for the client deposit", tone: "info" };
  return gate.ready
    ? { label: "Ready to start", tone: "success" }
    : { label: "Awaiting brief confirmation", tone: "info" };
}
