import "server-only";

import { createClient } from "@/lib/supabase/server";

import type { RevisionStatus, RevisionType, SubmissionOutcome } from "./constants";

export type SubmissionRow = {
  id: string;
  assignmentId: string;
  version: number;
  link: string;
  notes: string | null;
  exportDetails: string | null;
  revisionRequestId: string | null;
  confirmedDeadline: string;
  isLate: boolean;
  submittedAt: string;
  outcome: SubmissionOutcome | null;
  feedback: string | null;
  reviewedAt: string | null;
};

export type RevisionRow = {
  id: string;
  assignmentId: string;
  submissionId: string;
  type: RevisionType;
  countsAgainstAllowance: boolean;
  roundNumber: number | null;
  beyondAllowance: boolean;
  /** The admin requires extra editor pay to be accepted before this client revision begins. */
  adjustmentRequired: boolean;
  reason: string;
  status: RevisionStatus;
  createdAt: string;
};

export type SubmissionData = { submissions: SubmissionRow[]; revisions: RevisionRow[] };

/**
 * Submissions and change requests of one project, newest first. RLS decides what is returned:
 * everything for an admin (aal2), only the editor's own assignment for an active editor.
 */
export async function getSubmissionData(projectId: string): Promise<SubmissionData> {
  const supabase = await createClient();
  const [subs, revs] = await Promise.all([
    supabase
      .from("submissions")
      .select(
        "id, assignment_id, version, link, notes, export_details, revision_request_id, confirmed_deadline, is_late, submitted_at, outcome, feedback, reviewed_at",
      )
      .eq("project_id", projectId)
      .order("version", { ascending: false }),
    supabase
      .from("revision_requests")
      .select(
        "id, assignment_id, submission_id, type, counts_against_allowance, round_number, beyond_allowance, adjustment_required, reason, status, created_at",
      )
      .eq("project_id", projectId)
      .order("created_at", { ascending: false }),
  ]);
  if (subs.error) throw new Error("Could not load submissions.");
  if (revs.error) throw new Error("Could not load change requests.");
  return {
    submissions: (subs.data ?? []).map((s) => ({
      id: s.id,
      assignmentId: s.assignment_id,
      version: s.version,
      link: s.link,
      notes: s.notes,
      exportDetails: s.export_details,
      revisionRequestId: s.revision_request_id,
      confirmedDeadline: s.confirmed_deadline,
      isLate: s.is_late,
      submittedAt: s.submitted_at,
      outcome: s.outcome,
      feedback: s.feedback,
      reviewedAt: s.reviewed_at,
    })),
    revisions: (revs.data ?? []).map((r) => ({
      id: r.id,
      assignmentId: r.assignment_id,
      submissionId: r.submission_id,
      type: r.type,
      countsAgainstAllowance: r.counts_against_allowance ?? r.type === "client_revision",
      roundNumber: r.round_number,
      beyondAllowance: r.beyond_allowance,
      adjustmentRequired: r.adjustment_required,
      reason: r.reason,
      status: r.status,
      createdAt: r.created_at,
    })),
  };
}
