/** Shape returned by public.admin_dashboard_metrics() (Phase 10 migration). */
export type StatusCounts = Record<string, number>;

export type DashboardMetrics = {
  inquiries: { by_status: StatusCounts; total: number; conversion_rate: number | null };
  applications: { by_status: StatusCounts; total: number };
  editors: { active: number; suspended: number };
  projects: { by_status: StatusCounts; total: number };
  assignments: {
    offers: number;
    acceptance_rate: number | null;
    counteroffer_rate: number | null;
    median_hours_to_assignment: number | null;
  };
  delivery: {
    submissions: number;
    on_time_rate: number | null;
    first_submission_approval_rate: number | null;
    median_hours_to_first_submission: number | null;
  };
  revisions: {
    average_client_rounds: number | null;
    editor_corrections: number;
    scope_changes: number;
  };
  payments: {
    currency: string;
    not_due: number;
    outstanding: number;
    paid: number;
    outstanding_count: number;
  }[];
  generated_at: string;
};

/** "87%" for a 0–1 fraction; an em dash when there is no data yet. */
export function formatRate(value: number | null | undefined): string {
  if (value === null || value === undefined || Number.isNaN(value)) return "—";
  return `${Math.round(value * 100)}%`;
}

/** Hours as "18 h" under two days, otherwise "3.5 days". */
export function formatHours(value: number | null | undefined): string {
  if (value === null || value === undefined || Number.isNaN(value)) return "—";
  if (value < 48) return `${Math.round(value)} h`;
  return `${(value / 24).toFixed(1)} days`;
}

export function formatAmount(value: number, currency: string): string {
  return `${currency} ${value.toLocaleString("en-US", { maximumFractionDigits: 2 })}`;
}

export type Bar = { key: string; label: string; value: number };

/** Bars in the given status order, labelled; statuses with no rows show as zero. */
export function barsFor(
  counts: StatusCounts,
  order: readonly string[],
  labels: Record<string, string>,
): Bar[] {
  return order.map((key) => ({ key, label: labels[key] ?? key, value: counts[key] ?? 0 }));
}

export const INQUIRY_ORDER = [
  "new",
  "reviewing",
  "contacted",
  "in_discussion",
  "converted",
  "declined",
  "closed",
  "spam",
] as const;
export const INQUIRY_LABEL: Record<string, string> = {
  new: "New",
  reviewing: "Reviewing",
  contacted: "Contacted",
  in_discussion: "In discussion",
  converted: "Converted",
  declined: "Declined",
  closed: "Closed",
  spam: "Spam",
};

export const APPLICATION_ORDER = [
  "submitted",
  "under_review",
  "info_requested",
  "test_requested",
  "approved",
  "rejected",
  "withdrawn",
] as const;
export const APPLICATION_LABEL: Record<string, string> = {
  submitted: "Submitted",
  under_review: "Under review",
  info_requested: "Info requested",
  test_requested: "Test requested",
  approved: "Approved",
  rejected: "Rejected",
  withdrawn: "Withdrawn",
};

export const PROJECT_ORDER = [
  "draft",
  "open",
  "assigned",
  "in_progress",
  "in_review",
  "revision_requested",
  "approved",
  "completed",
  "on_hold",
  "cancelled",
] as const;
export const PROJECT_LABEL: Record<string, string> = {
  draft: "Draft",
  open: "Open",
  assigned: "Assigned",
  in_progress: "In progress",
  in_review: "In review",
  revision_requested: "Revision requested",
  approved: "Approved",
  completed: "Completed",
  on_hold: "On hold",
  cancelled: "Cancelled",
};
