import type { StatusTone } from "@/components/status-pill";

export const PAYMENT_STATUSES = [
  "not_due",
  "pending_approval",
  "approved",
  "processing",
  "paid",
  "on_hold",
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
};

export const PAYMENT_STATUS_TONE: Record<PaymentStatus, StatusTone> = {
  not_due: "neutral",
  pending_approval: "warning",
  approved: "info",
  processing: "info",
  paid: "success",
  on_hold: "danger",
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
      return ["to_pending_approval", "hold", "set_due_date"];
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
  }
}

export const HOLD_REASON_HINT = "The editor can see this reason.";
export const REVERSAL_LABEL = "Correction";

export const isPaymentStatus = (value: unknown): value is PaymentStatus =>
  typeof value === "string" && (PAYMENT_STATUSES as readonly string[]).includes(value);
