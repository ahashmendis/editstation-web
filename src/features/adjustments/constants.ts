import type { StatusTone } from "@/components/status-pill";
import { formatMoney } from "@/features/access/constants";
import type { Database } from "@/lib/supabase/database.types";

export type AdjustmentKind = Database["public"]["Enums"]["adjustment_kind"];
export type AdjustmentStatus = Database["public"]["Enums"]["adjustment_status"];
export type ScopeQuoteStatus = Database["public"]["Enums"]["scope_quote_status"];

export const ADJUSTMENT_KINDS = ["extra_round", "scope_change", "cancellation"] as const;

export const ADJUSTMENT_KIND_LABEL: Record<AdjustmentKind, string> = {
  extra_round: "Extra round",
  scope_change: "Scope change",
  cancellation: "Extra cancellation pay",
};

export const ADJUSTMENT_STATUS_LABEL: Record<AdjustmentStatus, string> = {
  offered: "Waiting for the editor",
  accepted: "Accepted",
  declined: "Declined",
  withdrawn: "Withdrawn",
};

export const ADJUSTMENT_STATUS_TONE: Record<AdjustmentStatus, StatusTone> = {
  offered: "warning",
  accepted: "success",
  declined: "danger",
  withdrawn: "neutral",
};

/** The editor's own wording for an offer's status. */
export const EDITOR_ADJUSTMENT_STATUS_LABEL: Record<AdjustmentStatus, string> = {
  offered: "Waiting for your answer",
  accepted: "Accepted",
  declined: "Declined",
  withdrawn: "Withdrawn by Lenscape",
};

export const SCOPE_QUOTE_STATUS_LABEL: Record<ScopeQuoteStatus, string> = {
  drafted: "Draft",
  sent: "Sent to the client",
  accepted: "Accepted by the client",
  declined: "Declined by the client",
};

export const SCOPE_QUOTE_STATUS_TONE: Record<ScopeQuoteStatus, StatusTone> = {
  drafted: "neutral",
  sent: "info",
  accepted: "success",
  declined: "danger",
};

/** private.revision_gate codes (public.editor_revision_gate). */
export const REVISION_GATES = ["ok", "needs_extra_pay", "waiting_for_scope_approval"] as const;
export type RevisionGate = (typeof REVISION_GATES)[number];

export const isRevisionGate = (value: unknown): value is RevisionGate =>
  typeof value === "string" && (REVISION_GATES as readonly string[]).includes(value);

/** What the editor reads while a change request is blocked (no client facts). */
export const EDITOR_GATE_MESSAGE: Record<Exclude<RevisionGate, "ok">, string> = {
  needs_extra_pay:
    "This change needs extra pay agreed first. Accept the extra pay offer above before you begin.",
  waiting_for_scope_approval:
    "Lenscape is still confirming this scope change. Please wait before you begin.",
};

/** Shown when the gate could not be checked: never offer Acknowledge/Start on a guess. */
export const EDITOR_GATE_UNKNOWN_MESSAGE =
  "We could not check whether this change can begin. Reload the page to try again.";

/** The notice an editor sees instead of the begin buttons, or null when the change can begin. */
export function editorGateNotice(gate: RevisionGate | "unknown" | undefined): string | null {
  if (gate === undefined || gate === "ok") return null;
  return gate === "unknown" ? EDITOR_GATE_UNKNOWN_MESSAGE : EDITOR_GATE_MESSAGE[gate];
}

/** Label of the settlement form's earned field, with the proposed amount and its currency. */
export function settlementEarnedLabel(proposed: number, currency: string): string {
  return `Editor earned, only to change the proposed ${formatMoney(proposed.toFixed(2), currency)}`;
}

/** Settlement stages (the project status at cancellation). */
export const SETTLEMENT_STAGE_LABEL: Record<string, string> = {
  assigned: "Assigned",
  in_progress: "In progress",
  in_review: "In review",
  revision_requested: "Revision requested",
};

/** An offer is live while it is waiting or accepted; only one live offer per change. */
export const isLiveAdjustment = (status: AdjustmentStatus) =>
  status === "offered" || status === "accepted";
