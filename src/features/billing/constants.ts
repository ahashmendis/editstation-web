import type { StatusTone } from "@/components/status-pill";
import type { Database } from "@/lib/supabase/database.types";

export type ClientMilestoneKind = Database["public"]["Enums"]["client_milestone_kind"];
export type ClientVerificationStatus = Database["public"]["Enums"]["client_verification_status"];

export const MILESTONE_KIND_LABEL: Record<ClientMilestoneKind, string> = {
  deposit: "Deposit",
  balance: "Balance",
  extra_work: "Extra work",
  refund: "Refund",
};

export const VERIFICATION_LABEL: Record<ClientVerificationStatus, string> = {
  expected: "Expected",
  received_unverified: "Received, not verified",
  verified: "Verified",
};

export const VERIFICATION_TONE: Record<ClientVerificationStatus, StatusTone> = {
  expected: "neutral",
  received_unverified: "warning",
  verified: "success",
};

export type MilestoneRow = {
  id: string;
  seq: number;
  kind: ClientMilestoneKind;
  share_percent: number | null;
  amount: number;
  currency: string;
  invoice_issued_at: string | null;
  due_date: string | null;
  received_at: string | null;
  transfer_reference: string | null;
  verification_status: ClientVerificationStatus;
  verified_at: string | null;
  auto_held_at: string | null;
  due_change_reason: string | null;
  correction_reason: string | null;
};

/** Which admin actions a milestone offers now (the database still decides). */
export function milestoneActions(m: MilestoneRow, workStarted: boolean, cancelled = false) {
  const invoiceable = m.kind === "deposit" || m.kind === "balance";
  return {
    issue: invoiceable && m.invoice_issued_at === null && !cancelled,
    record: m.verification_status !== "verified",
    verify: m.verification_status === "received_unverified",
    extend:
      !cancelled &&
      m.kind === "deposit" &&
      m.invoice_issued_at !== null &&
      m.verification_status !== "verified",
    correct: m.verification_status === "verified" && !(m.kind === "deposit" && workStarted),
  };
}

/** Overdue in business calendar days: the due date has passed and the money is not verified. */
export function isOverdue(
  m: Pick<MilestoneRow, "due_date" | "verification_status">,
  today: string,
) {
  return m.due_date !== null && m.verification_status !== "verified" && m.due_date < today;
}

/** Call 4 default (owner to confirm). */
export const DEFAULT_BUSINESS_TIMEZONE = "Asia/Colombo";

/** Today's calendar date (YYYY-MM-DD) in a timezone; falls back to the default zone. */
export function businessToday(timezone: string, now: Date = new Date()): string {
  try {
    return new Intl.DateTimeFormat("en-CA", { timeZone: timezone }).format(now);
  } catch {
    return new Intl.DateTimeFormat("en-CA", { timeZone: DEFAULT_BUSINESS_TIMEZONE }).format(now);
  }
}
