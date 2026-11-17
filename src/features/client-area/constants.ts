import type { StatusTone } from "@/components/status-pill";

// What a client is told. The database decides WHICH key applies (private.client_status_key and
// private.client_payment_status_key, the single mapping); this file only words each key. A key the
// app does not know yet falls back to a neutral label instead of leaking anything.

export const CLIENT_STATUS_KEYS = [
  "received",
  "planning",
  "in_production",
  "finalising",
  "revisions_in_progress",
  "completed",
  "on_hold",
  "cancelled",
] as const;
export type ClientStatusKey = (typeof CLIENT_STATUS_KEYS)[number];

const CLIENT_STATUS: Record<ClientStatusKey, { label: string; tone: StatusTone; hint: string }> = {
  received: {
    label: "Received",
    tone: "neutral",
    hint: "We have your project and are preparing it.",
  },
  planning: {
    label: "Planning",
    tone: "info",
    hint: "We are planning the edit and arranging the team.",
  },
  in_production: { label: "In production", tone: "info", hint: "Your video is being edited." },
  finalising: {
    label: "Finalising",
    tone: "info",
    hint: "The studio is preparing the final version.",
  },
  revisions_in_progress: {
    label: "Revisions in progress",
    tone: "info",
    hint: "We are working on the requested changes.",
  },
  completed: { label: "Completed", tone: "success", hint: "This project is finished." },
  on_hold: {
    label: "On hold",
    tone: "warning",
    hint: "Work is paused. The studio will be in touch.",
  },
  cancelled: { label: "Cancelled", tone: "danger", hint: "This project was cancelled." },
};

export function clientStatus(key: string): { label: string; tone: StatusTone; hint: string } {
  return (
    CLIENT_STATUS[key as ClientStatusKey] ?? {
      label: "In progress",
      tone: "neutral",
      hint: "The studio will share updates here.",
    }
  );
}

/** Statuses that count as finished (not shown as active on the dashboard). */
export function isClosedStatus(key: string): boolean {
  return key === "completed" || key === "cancelled";
}

export const PAYMENT_STATUS_KEYS = [
  "not_invoiced",
  "awaiting_payment",
  "confirming",
  "paid",
  "refunded",
] as const;
export type PaymentStatusKey = (typeof PAYMENT_STATUS_KEYS)[number];

const PAYMENT_STATUS: Record<PaymentStatusKey, { label: string; tone: StatusTone }> = {
  not_invoiced: { label: "Not invoiced yet", tone: "neutral" },
  awaiting_payment: { label: "Awaiting payment", tone: "warning" },
  confirming: { label: "Received, being confirmed", tone: "info" },
  paid: { label: "Paid", tone: "success" },
  refunded: { label: "Refunded", tone: "neutral" },
};

export function paymentStatus(key: string): { label: string; tone: StatusTone } {
  return PAYMENT_STATUS[key as PaymentStatusKey] ?? { label: "Pending", tone: "neutral" };
}

/** Payments the client still has to make (invoiced and not yet received). */
export function isPaymentDue(key: string): boolean {
  return key === "awaiting_payment";
}

const MILESTONE_KIND: Record<string, string> = {
  deposit: "Deposit",
  balance: "Balance",
  extra_work: "Additional work",
  refund: "Refund",
};

export function milestoneKindLabel(kind: string): string {
  return MILESTONE_KIND[kind] ?? "Payment";
}

/** "10,000.00 LKR". Amounts arrive as JSON numbers. */
export function formatAmount(amount: number, currency: string): string {
  const value = new Intl.NumberFormat("en-GB", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(amount);
  return `${value} ${currency}`;
}

/** "31 Jan 2099" for a YYYY-MM-DD date, without timezone shifts. */
export function formatDay(date: string | null): string | null {
  if (!date) return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(date);
  if (!match) return null;
  const d = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
  return new Intl.DateTimeFormat("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
    timeZone: "UTC",
  }).format(d);
}
