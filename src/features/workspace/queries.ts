import "server-only";

import { listMyPayments, type EditorPaymentRow } from "@/features/payments/queries";
import type { ProjectStatus } from "@/features/projects/constants";
import {
  OPEN_REVISION_STATUSES,
  type RevisionStatus,
  type RevisionType,
  type SubmissionOutcome,
} from "@/features/submissions/constants";
import { createClient } from "@/lib/supabase/server";

import {
  deriveStage,
  drivingAssignments,
  isWorkingAssignment,
  latest,
  paymentMilestone,
  pendingAction,
  type ProjectListRow,
} from "./model";

// Editor workspace reads. Everything goes through the signed-in editor's own RLS (or the existing
// editor_list_payments function): own assignments, own submissions and change requests, own
// confirmations and own pay. Only editor-safe columns are selected: no client data, no client
// prices, no billing, no internal notes.

function check<T>(result: { data: T | null; error: unknown }): T {
  if (result.error) throw result.error;
  if (result.data === null) throw new Error("Unexpected empty result");
  return result.data;
}

// Caps on the editor's OWN rows only (RLS also lets editors read open opportunities, so a cap on
// `projects` could drop their own work). `truncated` lets a page say so instead of hiding rows.
export const PROJECT_LIMIT = 200;
const ASSIGNMENT_LIMIT = 500;
const ROW_LIMIT = 1000;
const IN_CHUNK = 100;
/** Shown when any cap was reached (which one does not matter to the editor). */
export const TRUNCATED_NOTICE =
  "Only your most recent items are shown here; some older ones are not listed.";

export type RevisionLite = {
  id: string;
  projectId: string;
  assignmentId: string;
  submissionId: string;
  type: RevisionType;
  status: RevisionStatus;
  roundNumber: number | null;
  reason: string;
  createdAt: string;
  updatedAt: string;
};

export type SubmissionLite = {
  id: string;
  projectId: string;
  assignmentId: string;
  version: number;
  outcome: SubmissionOutcome | null;
  submittedAt: string;
  reviewedAt: string | null;
};

export type EditorWorkspace = {
  rows: ProjectListRow[];
  revisions: RevisionLite[];
  submissions: SubmissionLite[];
  payments: EditorPaymentRow[];
  titles: Map<string, string>;
  truncated: boolean;
};

/**
 * Every project this editor has an assignment on (offers included, plain opportunities excluded),
 * with its derived stage, pending action, latest submission, change-request count and the
 * editor's own pay milestone status.
 */
export async function getEditorWorkspace(): Promise<EditorWorkspace> {
  const supabase = await createClient();
  // The editor's own assignments first; projects are then fetched by id, so an own project is
  // never pushed out by other visible projects.
  const assignmentRows = check(
    await supabase
      .from("assignments")
      .select("id, project_id, status, created_at, confirmed_at")
      .order("created_at", { ascending: false })
      .order("id")
      .limit(ASSIGNMENT_LIMIT),
  );
  const { current, projectIds } = drivingAssignments(assignmentRows, PROJECT_LIMIT);
  const chunks: string[][] = [];
  for (let i = 0; i < projectIds.length; i += IN_CHUNK) {
    chunks.push(projectIds.slice(i, i + IN_CHUNK));
  }

  const [projectChunks, submissions, revisions, confirmations, payments] = await Promise.all([
    Promise.all(
      chunks.map(async (ids) =>
        check(
          await supabase
            .from("projects")
            .select("id, title, status, deadline, updated_at")
            .in("id", ids),
        ),
      ),
    ),
    supabase
      .from("submissions")
      .select("id, project_id, assignment_id, version, outcome, submitted_at, reviewed_at")
      .order("submitted_at", { ascending: false })
      .limit(ROW_LIMIT),
    supabase
      .from("revision_requests")
      .select(
        "id, project_id, assignment_id, submission_id, type, status, round_number, reason, created_at, updated_at",
      )
      .order("created_at", { ascending: false })
      .limit(ROW_LIMIT),
    supabase
      .from("brief_confirmations")
      .select("assignment_id, confirmed_deadline, confirmed_at")
      .order("confirmed_at", { ascending: false })
      .limit(ROW_LIMIT),
    listMyPayments(),
  ]);
  const projectRows = projectChunks.flat();
  const submissionRows: SubmissionLite[] = check(submissions).map((s) => ({
    id: s.id,
    projectId: s.project_id,
    assignmentId: s.assignment_id,
    version: s.version,
    outcome: s.outcome,
    submittedAt: s.submitted_at,
    reviewedAt: s.reviewed_at,
  }));
  const revisionRows: RevisionLite[] = check(revisions).map((r) => ({
    id: r.id,
    projectId: r.project_id,
    assignmentId: r.assignment_id,
    submissionId: r.submission_id,
    type: r.type,
    status: r.status,
    roundNumber: r.round_number,
    reason: r.reason,
    createdAt: r.created_at,
    updatedAt: r.updated_at,
  }));
  const confirmationRows = check(confirmations);
  const truncated =
    assignmentRows.length >= ASSIGNMENT_LIMIT ||
    projectIds.length >= PROJECT_LIMIT ||
    [submissionRows, revisionRows, confirmationRows].some((rows) => rows.length >= ROW_LIMIT);

  const confirmedDeadline = new Map<string, string>();
  for (const c of confirmationRows) {
    if (!confirmedDeadline.has(c.assignment_id)) {
      confirmedDeadline.set(c.assignment_id, c.confirmed_deadline);
    }
  }

  const rows: ProjectListRow[] = [];
  for (const p of projectRows) {
    const a = current.get(p.id);
    if (!a) continue; // An opportunity without an offer belongs on the Opportunities page.
    const status = p.status as ProjectStatus;
    const stage = deriveStage(status, a.status);
    // An editor can hold several assignments on one project over time (only one live at a time,
    // `assignments_live_key`), e.g. declined then offered again. Counts, the latest submission and
    // the open request follow the driving assignment; /editor/feedback still lists them all.
    const subs = submissionRows.filter((s) => s.assignmentId === a.id);
    const revs = revisionRows.filter((r) => r.assignmentId === a.id);
    const open = revs.find((r) => OPEN_REVISION_STATUSES.includes(r.status));
    const confirmed = isWorkingAssignment(a.status) ? confirmedDeadline.get(a.id) : undefined;
    const top = subs[0];
    rows.push({
      id: p.id,
      title: p.title,
      stage,
      projectStatus: status,
      deadline: confirmed ?? p.deadline,
      deadlineConfirmed: Boolean(confirmed),
      lastActivity: latest(
        p.updated_at,
        a.created_at,
        a.confirmed_at,
        top?.submittedAt,
        top?.reviewedAt,
        ...revs.map((r) => r.updatedAt),
      ),
      action: pendingAction({
        stage,
        assignmentStatus: a.status,
        projectStatus: status,
        openRevisionStatus: open?.status ?? null,
      }),
      latestSubmission: top ? { version: top.version, outcome: top.outcome } : null,
      revisionCount: revs.length,
      payment: paymentMilestone(payments.filter((x) => x.projectId === p.id)),
    });
  }

  return {
    rows,
    revisions: revisionRows,
    submissions: submissionRows,
    payments,
    titles: new Map(projectRows.map((p) => [p.id, p.title])),
    truncated,
  };
}

/** Change-request timestamps of one project for the Activity tab (RLS: own rows only). */
export async function listRevisionTimeline(projectId: string) {
  const supabase = await createClient();
  const rows = check(
    await supabase
      .from("revision_requests")
      .select("id, type, round_number, created_at, acknowledged_at, resubmitted_at, resolved_at")
      .eq("project_id", projectId)
      .order("created_at", { ascending: false }),
  );
  return rows.map((r) => ({
    id: r.id,
    type: r.type as RevisionType,
    roundNumber: r.round_number,
    createdAt: r.created_at,
    acknowledgedAt: r.acknowledged_at,
    resubmittedAt: r.resubmitted_at,
    resolvedAt: r.resolved_at,
  }));
}

/** The editor's own brief confirmations on one project, for the Activity tab (no amounts). */
export async function listConfirmationTimeline(projectId: string) {
  const supabase = await createClient();
  const rows = check(
    await supabase
      .from("brief_confirmations")
      .select("id, brief_version, confirmed_deadline, confirmed_at")
      .eq("project_id", projectId)
      .order("confirmed_at", { ascending: false }),
  );
  return rows.map((c) => ({
    id: c.id,
    briefVersion: c.brief_version,
    deadline: c.confirmed_deadline,
    confirmedAt: c.confirmed_at,
  }));
}
