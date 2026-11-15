import type { StatusTone } from "@/components/status-pill";
import type { Database } from "@/lib/supabase/database.types";

export const PAYMENT_STATUSES = [
  "not_due",
  "pending_approval",
  "approved",
  "processing",
  "paid",
  "on_hold",
  "cancelled",
] as const;
export type PaymentStatus = (typeof PAYMENT_STATUSES)[number];
export type PaymentKind = "assignment" | "reversal";

export const PAYMENT_STATUS_LABEL: Record<PaymentStatus, string> = {
  not_due: "Not due",
  pending_approval: "Pending approval",
  approved: "Approved",
  processing: "Processing",
  paid: "Paid",
  on_hold: "On hold",
  cancelled: "Cancelled",
};

export const PAYMENT_STATUS_TONE: Record<PaymentStatus, StatusTone> = {
  not_due: "neutral",
  pending_approval: "warning",
  approved: "info",
  processing: "info",
  paid: "success",
  on_hold: "danger",
  cancelled: "neutral",
};

export const UNPAID_STATUSES: readonly PaymentStatus[] = [
  "not_due",
  "pending_approval",
  "approved",
  "processing",
];
export const COMMITTED_STATUSES: readonly PaymentStatus[] = UNPAID_STATUSES;
export const AWAITING_TRANSFER_STATUSES: readonly PaymentStatus[] = ["approved", "processing"];

export type AdminPaymentAction =
  | "to_pending_approval"
  | "approve"
  | "to_processing"
  | "mark_paid"
  | "hold"
  | "release"
  | "set_due_date"
  | "reverse";

/** Which admin actions to offer. A UI hint only: the database decides what is allowed. */
export function nextAdminActions(
  status: PaymentStatus,
  kind: PaymentKind,
  hasReversal: boolean,
): AdminPaymentAction[] {
  if (kind === "reversal") return [];
  switch (status) {
    case "not_due":
      // Payable only through the milestone rules (client money verified, approval, late balance).
      return ["hold", "set_due_date"];
    case "pending_approval":
      return ["approve", "hold", "set_due_date"];
    case "approved":
      return ["to_processing", "mark_paid", "hold", "set_due_date"];
    case "processing":
      return ["mark_paid", "hold", "set_due_date"];
    case "on_hold":
      return ["release", "set_due_date"];
    case "paid":
      return hasReversal ? [] : ["reverse"];
    case "cancelled":
      // Final: voided by a cancellation settlement.
      return [];
  }
}

export const HOLD_REASON_HINT =
  "Admins only. The editor sees a fixed label (Under review), never this reason.";

export type PayableReason = Database["public"]["Enums"]["payment_payable_reason"];
export type HoldLabel = Database["public"]["Enums"]["payment_hold_label"];

/** Why a milestone became payable (admin view only: it can reveal the client's payment state). */
export const PAYABLE_REASON_LABEL: Record<PayableReason, string> = {
  client_deposit_verified: "Client deposit verified",
  client_balance_verified: "Client balance verified",
  late_balance_protection: "Late-balance protection",
  adjustment_accepted: "Extra pay accepted",
  cancellation_settlement: "Cancellation settlement",
};

/** The only hold/wait wording an editor sees (KB9a-5): fixed labels, never the admin's reason. */
export const HOLD_LABEL: Record<HoldLabel, string> = {
  under_review: "Under review",
  assignment_ended: "Assignment ended. Lenscape will contact you about this payment.",
  waiting_for_client_payment: "Waiting for client payment",
};

export const milestoneLabel = (seq: number | null) =>
  seq === null ? "Extra line" : `Milestone ${seq}`;

/** What an editor's payment row pays (editor_list_payments.line_kind): fixed labels only. */
export const LINE_KINDS = [
  "milestone",
  "extra_round",
  "scope_change",
  "cancellation_extra",
  "cancellation_settlement",
  "cancellation_reconciliation",
] as const;
export type LineKind = (typeof LINE_KINDS)[number];

const LINE_KIND_LABEL: Record<Exclude<LineKind, "milestone">, string> = {
  extra_round: "Extra round pay",
  scope_change: "Scope change pay",
  cancellation_extra: "Extra cancellation pay",
  cancellation_settlement: "Cancellation settlement",
  cancellation_reconciliation: "Cancellation reconciliation",
};

export const isLineKind = (value: unknown): value is LineKind =>
  typeof value === "string" && (LINE_KINDS as readonly string[]).includes(value);

export function lineLabel(lineKind: LineKind, seq: number | null): string {
  return lineKind === "milestone" ? milestoneLabel(seq) : LINE_KIND_LABEL[lineKind];
}

/** Admin label for a row: the milestone, or the extra line it belongs to. */
export function adminLineLabel(p: {
  milestoneSeq: number | null;
  adjustmentId: string | null;
  settlementId: string | null;
}): string {
  if (p.adjustmentId) return "Extra pay";
  if (p.settlementId && p.milestoneSeq === null) return "Cancellation settlement";
  if (p.settlementId) return `${milestoneLabel(p.milestoneSeq)} · settlement reconciliation`;
  return milestoneLabel(p.milestoneSeq);
}

/** Largest disputed part of a payment (one cent less than it), as a form value. */
export function maxDisputedAmount(amount: number): string {
  return (Math.round(amount * 100 - 1) / 100).toFixed(2);
}

/** A dispute split is offered for an unsplit, unpaid milestone (not an extra line) that is not on hold or cancelled. */
export function canSplitForDispute(p: {
  kind: PaymentKind;
  status: PaymentStatus;
  milestoneSeq: number | null;
  splitFromPaymentId: string | null;
  amountBeforeSplit: number | null;
}): boolean {
  return (
    p.kind === "assignment" &&
    p.status !== "paid" &&
    p.status !== "on_hold" &&
    p.status !== "cancelled" &&
    p.milestoneSeq !== null &&
    p.splitFromPaymentId === null &&
    p.amountBeforeSplit === null
  );
}
export const REVERSAL_LABEL = "Correction";

export const isPaymentStatus = (value: unknown): value is PaymentStatus =>
  typeof value === "string" && (PAYMENT_STATUSES as readonly string[]).includes(value);
