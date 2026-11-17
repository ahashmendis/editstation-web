// Editor workspace (Phase 1): pure mapping, filtering, sorting and paging over data the editor
// can already read through RLS. No database access here, so it is unit-tested directly.

import type { StatusTone } from "@/components/status-pill";
import {
  NEGOTIATION_ACTION_LABEL,
  type AssignmentStatus,
  type NegotiationAction,
} from "@/features/access/constants";
import {
  UNPAID_STATUSES,
  lineLabel,
  type LineKind,
  type PaymentKind,
  type PaymentStatus,
} from "@/features/payments/constants";
import type { ProjectStatus } from "@/features/projects/constants";
import {
  OUTCOME_LABEL,
  REVISION_TYPE_LABEL,
  type RevisionStatus,
  type RevisionType,
  type SubmissionOutcome,
} from "@/features/submissions/constants";

// --- Stage: one editor-facing state per project from project + own assignment status ---------

export type WorkspaceStage =
  | "awaiting_acceptance"
  | "offer_closed"
  | "confirmed"
  | "in_progress"
  | "in_review"
  | "revision_requested"
  | "approved"
  | "completed"
  | "on_hold"
  | "cancelled";

export const STAGE_LABEL: Record<WorkspaceStage, string> = {
  awaiting_acceptance: "Awaiting acceptance",
  offer_closed: "Offer closed",
  confirmed: "Confirmed, not started",
  in_progress: "In progress",
  in_review: "Submitted, in review",
  revision_requested: "Revision requested",
  approved: "Approved",
  completed: "Completed",
  on_hold: "On hold",
  cancelled: "Cancelled",
};

export const STAGE_TONE: Record<WorkspaceStage, StatusTone> = {
  awaiting_acceptance: "info",
  offer_closed: "neutral",
  confirmed: "info",
  in_progress: "info",
  in_review: "info",
  revision_requested: "warning",
  approved: "success",
  completed: "success",
  on_hold: "warning",
  cancelled: "neutral",
};

const OFFER_OPEN: readonly AssignmentStatus[] = ["offered", "counteroffer_pending", "accepted"];
const WORKING: readonly AssignmentStatus[] = ["confirmed", "in_progress"];

export function deriveStage(
  projectStatus: ProjectStatus,
  assignmentStatus: AssignmentStatus,
): WorkspaceStage {
  if (projectStatus === "cancelled") return "cancelled";
  if (projectStatus === "on_hold") return "on_hold";
  if (OFFER_OPEN.includes(assignmentStatus)) return "awaiting_acceptance";
  if (!WORKING.includes(assignmentStatus)) return "offer_closed";
  switch (projectStatus) {
    case "in_progress":
    case "in_review":
    case "revision_requested":
    case "approved":
    case "completed":
      return projectStatus;
    default:
      return "confirmed";
  }
}

const LIVE: readonly AssignmentStatus[] = [...OFFER_OPEN, ...WORKING];

/**
 * The assignment that drives each project (the newest live one, else the newest) from the
 * editor's own assignments, newest first. `projectIds` keeps the order of first appearance
 * (most recently assigned first) and is capped at `limit` projects.
 */
export function drivingAssignments<T extends { project_id: string; status: AssignmentStatus }>(
  rows: readonly T[],
  limit: number,
): { current: Map<string, T>; projectIds: string[] } {
  const current = new Map<string, T>();
  const projectIds: string[] = [];
  for (const a of rows) {
    const seen = current.get(a.project_id);
    if (!seen) {
      if (projectIds.length >= limit) continue;
      projectIds.push(a.project_id);
      current.set(a.project_id, a);
    } else if (!LIVE.includes(seen.status) && LIVE.includes(a.status)) {
      current.set(a.project_id, a);
    }
  }
  return { current, projectIds };
}

export const isWorkingAssignment = (status: AssignmentStatus) => WORKING.includes(status);

// --- List filters (honest mapping onto stages) ------------------------------------------------

export const PROJECT_LIST_FILTERS = [
  { value: "all", label: "All" },
  { value: "awaiting_acceptance", label: "Awaiting acceptance" },
  { value: "active", label: "Active" },
  { value: "in_progress", label: "In progress" },
  { value: "in_review", label: "Submitted, in review" },
  { value: "revision_requested", label: "Revision requested" },
  { value: "completed", label: "Approved or completed" },
  { value: "on_hold", label: "On hold" },
  { value: "cancelled", label: "Cancelled" },
] as const;
export type ProjectListFilter = (typeof PROJECT_LIST_FILTERS)[number]["value"];

const ACTIVE: readonly WorkspaceStage[] = [
  "confirmed",
  "in_progress",
  "in_review",
  "revision_requested",
];

export function matchesFilter(stage: WorkspaceStage, filter: ProjectListFilter): boolean {
  switch (filter) {
    case "all":
      return true;
    case "active":
      return ACTIVE.includes(stage);
    case "completed":
      return stage === "approved" || stage === "completed";
    default:
      return stage === filter;
  }
}

export const isActiveStage = (stage: WorkspaceStage) => ACTIVE.includes(stage);

export const PROJECT_SORTS = [
  { value: "activity", label: "Last activity" },
  { value: "deadline", label: "Deadline" },
  { value: "title", label: "Title" },
] as const;
export type ProjectSort = (typeof PROJECT_SORTS)[number]["value"];

const first = (v: unknown): string | undefined =>
  typeof v === "string" ? v : Array.isArray(v) && typeof v[0] === "string" ? v[0] : undefined;

function parsePage(v: unknown): number {
  const n = Number(first(v));
  return Number.isInteger(n) && n >= 1 ? n : 1;
}

export const MAX_SEARCH = 100;

export function parseProjectListParams(params: Record<string, unknown>): {
  filter: ProjectListFilter;
  q: string;
  sort: ProjectSort;
  page: number;
} {
  const rawFilter = first(params.filter);
  // "Submitted" and "in review" are the same database state (submit sets the project in_review).
  const f = rawFilter === "submitted" ? "in_review" : rawFilter;
  const filter = PROJECT_LIST_FILTERS.find((x) => x.value === f)?.value ?? "all";
  const s = first(params.sort);
  const sort = PROJECT_SORTS.find((x) => x.value === s)?.value ?? "activity";
  const q = (first(params.q) ?? "").trim().slice(0, MAX_SEARCH);
  return { filter, q, sort, page: parsePage(params.page) };
}

// --- Rows -------------------------------------------------------------------------------------

export type PendingAction = { text: string; by: "you" | "studio" };

export type PaymentMilestone = { status: PaymentStatus; label: string };

export type ProjectListRow = {
  id: string;
  title: string;
  stage: WorkspaceStage;
  projectStatus: ProjectStatus;
  /** Confirmed deadline when the editor confirmed the brief, else the project's planned one. */
  deadline: string | null;
  deadlineConfirmed: boolean;
  lastActivity: string;
  action: PendingAction | null;
  latestSubmission: { version: number; outcome: SubmissionOutcome | null } | null;
  revisionCount: number;
  payment: PaymentMilestone | null;
};

export function queryProjectRows(
  rows: readonly ProjectListRow[],
  opts: { filter: ProjectListFilter; q: string; sort: ProjectSort },
): ProjectListRow[] {
  const q = opts.q.toLowerCase();
  const out = rows.filter(
    (r) => matchesFilter(r.stage, opts.filter) && (!q || r.title.toLowerCase().includes(q)),
  );
  // Id is the final tie-break so paging is stable.
  const byTitle = (a: ProjectListRow, b: ProjectListRow) =>
    a.title.localeCompare(b.title, "en", { sensitivity: "base" }) ||
    (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
  out.sort((a, b) => {
    if (opts.sort === "title") return byTitle(a, b);
    if (opts.sort === "deadline") {
      if (a.deadline === b.deadline) return byTitle(a, b);
      if (a.deadline === null) return 1;
      if (b.deadline === null) return -1;
      return a.deadline < b.deadline ? -1 : 1;
    }
    return a.lastActivity === b.lastActivity
      ? byTitle(a, b)
      : a.lastActivity < b.lastActivity
        ? 1
        : -1;
  });
  return out;
}

export function paginate<T>(items: readonly T[], page: number, pageSize: number) {
  const total = items.length;
  const pageCount = Math.max(1, Math.ceil(total / pageSize));
  const current = Math.min(Math.max(1, page), pageCount);
  return {
    items: items.slice((current - 1) * pageSize, current * pageSize),
    page: current,
    pageCount,
    total,
  };
}

/** The latest of the given ISO timestamps (nulls ignored). */
export function latest(...values: (string | null | undefined)[]): string {
  return values.reduce<string>((max, v) => (v && v > max ? v : max), "");
}

export function pendingAction(input: {
  stage: WorkspaceStage;
  assignmentStatus: AssignmentStatus;
  projectStatus: ProjectStatus;
  openRevisionStatus: RevisionStatus | null;
}): PendingAction | null {
  switch (input.stage) {
    case "awaiting_acceptance":
      if (input.assignmentStatus === "offered") {
        return input.projectStatus === "open"
          ? { text: "Reply to the offer", by: "you" }
          : { text: "Replies are paused", by: "studio" };
      }
      if (input.assignmentStatus === "counteroffer_pending") {
        return { text: "Studio to reply to your counteroffer", by: "studio" };
      }
      return { text: "Studio to confirm the editor", by: "studio" };
    case "confirmed":
      return { text: "Confirm the brief to start", by: "you" };
    case "in_progress":
      return { text: "Submit your work", by: "you" };
    case "in_review":
      return { text: "Studio is reviewing your submission", by: "studio" };
    case "revision_requested":
      switch (input.openRevisionStatus) {
        case "requested":
          return { text: "Acknowledge the change request", by: "you" };
        case "acknowledged":
          return { text: "Start the revision", by: "you" };
        case "in_progress":
          return { text: "Submit the revised version", by: "you" };
        default:
          return { text: "Studio is discussing the review", by: "studio" };
      }
    case "approved":
      return { text: "Studio to complete the project", by: "studio" };
    case "on_hold":
      return { text: "Paused by the studio", by: "studio" };
    default:
      return null;
  }
}

// --- Payments (the editor's own rows from editor_list_payments; never client money) -----------

type PaymentLite = {
  kind: PaymentKind;
  status: PaymentStatus;
  milestoneSeq: number | null;
  lineKind: LineKind;
  dueDate: string | null;
  createdAt: string;
};

const OUTSTANDING: readonly PaymentStatus[] = [...UNPAID_STATUSES, "on_hold"];

/** The project's first outstanding pay milestone (status label only), "All paid", or null. */
export function paymentMilestone(rows: readonly PaymentLite[]): PaymentMilestone | null {
  const own = rows.filter((r) => r.kind === "assignment" && r.status !== "cancelled");
  if (own.length === 0) return null;
  const open = own
    .filter((r) => OUTSTANDING.includes(r.status))
    .sort(
      (a, b) =>
        (a.milestoneSeq ?? Number.MAX_SAFE_INTEGER) - (b.milestoneSeq ?? Number.MAX_SAFE_INTEGER) ||
        a.createdAt.localeCompare(b.createdAt),
    );
  const next = open[0];
  if (next) return { status: next.status, label: lineLabel(next.lineKind, next.milestoneSeq) };
  return own.every((r) => r.status === "paid") ? { status: "paid", label: "All paid" } : null;
}

/** The editor's unpaid or held pay rows, soonest due first (undated last). */
export function outstandingPayments<
  T extends { kind: PaymentKind; status: PaymentStatus; dueDate: string | null },
>(rows: readonly T[]): T[] {
  return rows
    .filter((r) => r.kind === "assignment" && OUTSTANDING.includes(r.status))
    .sort((a, b) =>
      a.dueDate === b.dueDate
        ? 0
        : a.dueDate === null
          ? 1
          : b.dueDate === null
            ? -1
            : a.dueDate < b.dueDate
              ? -1
              : 1,
    );
}

/** Confirmed deadlines of ongoing work, soonest first; `today` is YYYY-MM-DD. */
export function upcomingDeadlines(rows: readonly ProjectListRow[], today: string) {
  return rows
    .filter((r) => r.deadline && r.deadlineConfirmed && isActiveStage(r.stage))
    .sort((a, b) => (a.deadline! < b.deadline! ? -1 : a.deadline! > b.deadline! ? 1 : 0))
    .map((r) => ({ row: r, overdue: r.deadline! < today }));
}

// --- Feedback and revisions ---------------------------------------------------------------------

export const FEEDBACK_FILTERS = [
  { value: "all", label: "All" },
  { value: "open", label: "Open" },
  { value: "in_progress", label: "Acknowledged or in progress" },
  { value: "resubmitted", label: "Resubmitted" },
  { value: "resolved", label: "Resolved" },
] as const;
export type FeedbackFilter = (typeof FEEDBACK_FILTERS)[number]["value"];

export function feedbackGroupOf(status: RevisionStatus): Exclude<FeedbackFilter, "all"> {
  switch (status) {
    case "requested":
    case "disputed":
      return "open";
    case "acknowledged":
    case "in_progress":
      return "in_progress";
    case "resubmitted":
      return "resubmitted";
    default:
      return "resolved";
  }
}

export function parseFeedbackParams(params: Record<string, unknown>): {
  status: FeedbackFilter;
  page: number;
} {
  const s = first(params.status);
  return {
    status: FEEDBACK_FILTERS.find((x) => x.value === s)?.value ?? "all",
    page: parsePage(params.page),
  };
}

// --- Project workspace tabs ---------------------------------------------------------------------

export const PROJECT_TABS = [
  { value: "overview", label: "Overview" },
  { value: "brief", label: "Brief" },
  { value: "submissions", label: "Submissions" },
  { value: "feedback", label: "Feedback & revisions" },
  { value: "files", label: "Files" },
  { value: "activity", label: "Activity" },
] as const;
export type ProjectTab = (typeof PROJECT_TABS)[number]["value"];

export function parseTab(value: unknown): ProjectTab {
  const v = first(value);
  return PROJECT_TABS.find((t) => t.value === v)?.value ?? "overview";
}

/** A short, human-friendly reference derived from the project id (no separate column exists). */
export const shortRef = (id: string) => id.slice(0, 8).toUpperCase();

// --- Activity timeline (only events the editor can already see) ---------------------------------

export type ActivityEvent = { id: string; at: string; label: string };

export function buildActivity(src: {
  negotiations: {
    id: string;
    fromRole: "admin" | "editor";
    action: NegotiationAction;
    createdAt: string;
  }[];
  assignments: { id: string; confirmedAt: string | null }[];
  confirmations: { id: string; briefVersion: number; deadline: string; confirmedAt: string }[];
  submissions: {
    id: string;
    version: number;
    isLate: boolean;
    submittedAt: string;
    outcome: SubmissionOutcome | null;
    reviewedAt: string | null;
  }[];
  revisions: {
    id: string;
    type: RevisionType;
    roundNumber: number | null;
    createdAt: string;
    acknowledgedAt: string | null;
    resubmittedAt: string | null;
    resolvedAt: string | null;
  }[];
}): ActivityEvent[] {
  const events: ActivityEvent[] = [];
  for (const n of src.negotiations) {
    events.push({
      id: `n-${n.id}`,
      at: n.createdAt,
      label: `${n.fromRole === "editor" ? "You" : "The studio"} ${NEGOTIATION_ACTION_LABEL[n.action]}`,
    });
  }
  for (const a of src.assignments) {
    if (a.confirmedAt) {
      events.push({ id: `a-${a.id}`, at: a.confirmedAt, label: "The studio confirmed you" });
    }
  }
  for (const c of src.confirmations) {
    events.push({
      id: `c-${c.id}`,
      at: c.confirmedAt,
      label: `Brief version ${c.briefVersion} confirmed, deadline ${c.deadline}`,
    });
  }
  for (const s of src.submissions) {
    events.push({
      id: `s-${s.id}`,
      at: s.submittedAt,
      label: `Version ${s.version} submitted${s.isLate ? " (late)" : ""}`,
    });
    if (s.outcome && s.reviewedAt) {
      events.push({
        id: `sr-${s.id}`,
        at: s.reviewedAt,
        label: `Version ${s.version} reviewed: ${OUTCOME_LABEL[s.outcome]}`,
      });
    }
  }
  for (const r of src.revisions) {
    const name = `${REVISION_TYPE_LABEL[r.type].toLowerCase()}${r.roundNumber ? ` (round ${r.roundNumber})` : ""}`;
    events.push({ id: `r-${r.id}`, at: r.createdAt, label: `Change request: ${name}` });
    if (r.acknowledgedAt) {
      events.push({
        id: `ra-${r.id}`,
        at: r.acknowledgedAt,
        label: `You acknowledged the ${name}`,
      });
    }
    if (r.resubmittedAt) {
      events.push({
        id: `rs-${r.id}`,
        at: r.resubmittedAt,
        label: `You resubmitted for the ${name}`,
      });
    }
    if (r.resolvedAt) {
      events.push({ id: `rr-${r.id}`, at: r.resolvedAt, label: `The ${name} was resolved` });
    }
  }
  return events.sort((a, b) => (a.at === b.at ? 0 : a.at < b.at ? 1 : -1));
}
