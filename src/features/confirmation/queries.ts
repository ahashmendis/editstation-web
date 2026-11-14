import "server-only";

import { createClient } from "@/lib/supabase/server";

import type { ConfirmationKind, GateRow, InterpretationStatus } from "./constants";

export type InterpretationRow = {
  id: string;
  assignmentId: string;
  briefVersion: number;
  willReproduce: string | null;
  willAdapt: string | null;
  questions: string | null;
  status: InterpretationStatus;
  adminFeedback: string | null;
  submittedAt: string;
  reviewedAt: string | null;
};

export type ConfirmationRow = {
  id: string;
  assignmentId: string;
  briefVersion: number;
  kind: ConfirmationKind;
  deadline: string;
  deliverableCount: number;
  amount: number;
  currency: string;
  confirmedAt: string;
};

export type AssignmentConfirmation = {
  assignmentId: string;
  gate: GateRow | null;
  interpretations: InterpretationRow[];
  confirmations: ConfirmationRow[];
};

type RawInterpretation = {
  id: string;
  assignment_id: string;
  brief_version_id: string;
  will_reproduce: string | null;
  will_adapt: string | null;
  questions_limitations: string | null;
  status: InterpretationStatus;
  admin_feedback: string | null;
  submitted_at: string;
  reviewed_at: string | null;
};

type RawConfirmation = {
  id: string;
  assignment_id: string;
  brief_version: number;
  kind: ConfirmationKind;
  confirmed_deadline: string;
  confirmed_deliverables: unknown;
  confirmed_amount: number | string;
  confirmed_currency: string;
  confirmed_at: string;
};

/**
 * Gate, interpretations and confirmations for the given assignments. RLS limits an editor to
 * their own rows and an admin (aal2) to all of them.
 */
export async function getConfirmationData(
  assignmentIds: string[],
): Promise<Map<string, AssignmentConfirmation>> {
  const result = new Map<string, AssignmentConfirmation>();
  if (assignmentIds.length === 0) return result;
  const supabase = await createClient();

  const [gates, interpretations, confirmations] = await Promise.all([
    Promise.all(
      assignmentIds.map(async (id) => {
        const { data, error } = await supabase.rpc("get_assignment_gate", {
          p_assignment_id: id,
        });
        if (error) throw error;
        const row = (Array.isArray(data) ? data[0] : data) as GateRow | null | undefined;
        return [id, row ?? null] as const;
      }),
    ),
    supabase
      .from("editor_interpretations")
      .select(
        "id, assignment_id, brief_version_id, will_reproduce, will_adapt, questions_limitations, status, admin_feedback, submitted_at, reviewed_at",
      )
      .in("assignment_id", assignmentIds)
      .order("submitted_at", { ascending: false }),
    supabase
      .from("brief_confirmations")
      .select(
        "id, assignment_id, brief_version, kind, confirmed_deadline, confirmed_deliverables, confirmed_amount, confirmed_currency, confirmed_at",
      )
      .in("assignment_id", assignmentIds)
      .order("confirmed_at", { ascending: false }),
  ]);
  if (interpretations.error) throw interpretations.error;
  if (confirmations.error) throw confirmations.error;

  const rawI = (interpretations.data ?? []) as unknown as RawInterpretation[];
  const rawC = (confirmations.data ?? []) as unknown as RawConfirmation[];

  const versionIds = Array.from(new Set(rawI.map((i) => i.brief_version_id)));
  const versionOf = new Map<string, number>();
  if (versionIds.length > 0) {
    const { data, error } = await supabase
      .from("brief_versions")
      .select("id, version")
      .in("id", versionIds);
    if (error) throw error;
    for (const v of (data ?? []) as unknown as { id: string; version: number }[]) {
      versionOf.set(v.id, v.version);
    }
  }

  for (const [id, gate] of gates) {
    result.set(id, {
      assignmentId: id,
      gate,
      interpretations: rawI
        .filter((i) => i.assignment_id === id)
        .map((i) => ({
          id: i.id,
          assignmentId: i.assignment_id,
          briefVersion: versionOf.get(i.brief_version_id) ?? 0,
          willReproduce: i.will_reproduce,
          willAdapt: i.will_adapt,
          questions: i.questions_limitations,
          status: i.status,
          adminFeedback: i.admin_feedback,
          submittedAt: i.submitted_at,
          reviewedAt: i.reviewed_at,
        })),
      confirmations: rawC
        .filter((c) => c.assignment_id === id)
        .map((c) => ({
          id: c.id,
          assignmentId: c.assignment_id,
          briefVersion: c.brief_version,
          kind: c.kind,
          deadline: c.confirmed_deadline,
          deliverableCount: Array.isArray(c.confirmed_deliverables)
            ? c.confirmed_deliverables.length
            : 0,
          amount: Number(c.confirmed_amount),
          currency: c.confirmed_currency,
          confirmedAt: c.confirmed_at,
        })),
    });
  }
  return result;
}
