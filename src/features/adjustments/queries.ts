import "server-only";

import { userMessageFromDbError } from "@/features/applications/db-errors";
import { createClient } from "@/lib/supabase/server";

import {
  isRevisionGate,
  type AdjustmentKind,
  type AdjustmentStatus,
  type RevisionGate,
  type ScopeQuoteStatus,
} from "./constants";

export type AdminAdjustment = {
  id: string;
  assignmentId: string;
  kind: AdjustmentKind;
  amount: number;
  currency: string;
  revisionRequestId: string | null;
  scopeQuoteId: string | null;
  status: AdjustmentStatus;
  note: string | null;
  offeredAt: string;
};

export type ScopeQuote = {
  id: string;
  revisionRequestId: string;
  description: string;
  amount: number;
  currency: string;
  status: ScopeQuoteStatus;
};

export type RoundCharge = {
  id: string;
  revisionRequestId: string;
  amount: number;
  currency: string;
  dueDate: string | null;
};

export type Settlement = {
  id: string;
  assignmentId: string;
  stage: string;
  editorEarnedPercent: number;
  clientChargePercent: number;
  agreedAmount: number;
  editorCurrency: string;
  computedEditorEarned: number;
  editorEarned: number;
  adjustmentReason: string | null;
  editorExtraPay: number;
  editorPaidBefore: number;
  editorSettlementAmount: number;
  editorOverpayment: number;
  cancelledPaymentCount: number;
  clientBase: number;
  clientCurrency: string | null;
  clientReceived: number;
  clientCharge: number;
  clientRefund: number;
  clientOwes: number;
  settledAt: string;
};

/** The proposed figures (admin_preview_cancellation_settlement). */
export type SettlementPreview = {
  stage: string;
  editorEarnedPercent: number;
  clientChargePercent: number;
  agreedAmount: number;
  editorCurrency: string;
  computedEditorEarned: number;
  editorEarnedCap: number;
  editorExtraPay: number;
  editorPaidBefore: number;
  editorSettlementAmount: number;
  editorOverpayment: number;
  unpaidCount: number;
  clientBase: number;
  clientCurrency: string | null;
  clientReceived: number;
  clientCharge: number;
  clientRefund: number;
  clientOwes: number;
};

export type AdminAdjustmentData = {
  adjustments: AdminAdjustment[];
  quotes: ScopeQuote[];
  roundCharges: RoundCharge[];
  settlement: Settlement | null;
};

const num = (v: unknown) => Number(v ?? 0);

/** Extra pay offers, scope quotes, extra-round charges and the settlement of a project. Admin only (RLS). */
export async function getAdminAdjustmentData(projectId: string): Promise<AdminAdjustmentData> {
  const supabase = await createClient();
  const [adj, quotes, charges, settlement] = await Promise.all([
    supabase
      .from("compensation_adjustments")
      .select(
        "id, assignment_id, kind, amount, currency, revision_request_id, scope_quote_id, status, note, offered_at",
      )
      .eq("project_id", projectId)
      .order("offered_at", { ascending: false }),
    supabase
      .from("scope_change_quotes")
      .select("id, revision_request_id, description, amount, currency, status")
      .eq("project_id", projectId)
      .order("created_at", { ascending: false }),
    supabase
      .from("client_milestones")
      .select("id, revision_request_id, amount, currency, due_date")
      .eq("project_id", projectId)
      .not("revision_request_id", "is", null)
      .is("voided_at", null),
    supabase.from("cancellation_settlements").select("*").eq("project_id", projectId).maybeSingle(),
  ]);
  if (adj.error || quotes.error || charges.error || settlement.error)
    throw new Error("Could not load extra pay and settlement data.");
  const s = settlement.data;
  return {
    adjustments: (adj.data ?? []).map((a) => ({
      id: a.id,
      assignmentId: a.assignment_id,
      kind: a.kind,
      amount: num(a.amount),
      currency: a.currency,
      revisionRequestId: a.revision_request_id,
      scopeQuoteId: a.scope_quote_id,
      status: a.status,
      note: a.note,
      offeredAt: a.offered_at,
    })),
    quotes: (quotes.data ?? []).map((q) => ({
      id: q.id,
      revisionRequestId: q.revision_request_id,
      description: q.description,
      amount: num(q.amount),
      currency: q.currency,
      status: q.status,
    })),
    roundCharges: (charges.data ?? []).flatMap((c) =>
      c.revision_request_id
        ? [
            {
              id: c.id,
              revisionRequestId: c.revision_request_id,
              amount: num(c.amount),
              currency: c.currency,
              dueDate: c.due_date,
            },
          ]
        : [],
    ),
    settlement: s
      ? {
          id: s.id,
          assignmentId: s.assignment_id,
          stage: s.stage,
          editorEarnedPercent: num(s.editor_earned_percent),
          clientChargePercent: num(s.client_charge_percent),
          agreedAmount: num(s.agreed_amount),
          editorCurrency: s.editor_currency,
          computedEditorEarned: num(s.computed_editor_earned),
          editorEarned: num(s.editor_earned),
          adjustmentReason: s.adjustment_reason,
          editorExtraPay: num(s.editor_extra_pay),
          editorPaidBefore: num(s.editor_paid_before),
          editorSettlementAmount: num(s.editor_settlement_amount),
          editorOverpayment: num(s.editor_overpayment),
          cancelledPaymentCount: s.cancelled_payment_count,
          clientBase: num(s.client_base),
          clientCurrency: s.client_currency,
          clientReceived: num(s.client_received),
          clientCharge: num(s.client_charge),
          clientRefund: num(s.client_refund),
          clientOwes: num(s.client_owes),
          settledAt: s.settled_at,
        }
      : null,
  };
}

/**
 * The proposed settlement, or the database's user-safe reason why there is none (for example a
 * missing cancellation schedule). Admin only.
 */
export async function previewSettlement(
  projectId: string,
): Promise<{ preview: SettlementPreview | null; message: string | null }> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_preview_cancellation_settlement", {
    p_project_id: projectId,
  });
  if (error) return { preview: null, message: userMessageFromDbError(error) };
  const f = (data ?? {}) as Record<string, unknown>;
  return {
    preview: {
      stage: String(f.stage ?? ""),
      editorEarnedPercent: num(f.editor_earned_percent),
      clientChargePercent: num(f.client_charge_percent),
      agreedAmount: num(f.agreed_amount),
      editorCurrency: String(f.editor_currency ?? ""),
      computedEditorEarned: num(f.computed_editor_earned),
      editorEarnedCap: num(f.editor_earned_cap),
      editorExtraPay: num(f.editor_extra_pay),
      editorPaidBefore: num(f.editor_paid_before),
      editorSettlementAmount: num(f.editor_settlement_amount),
      editorOverpayment: num(f.editor_overpayment),
      unpaidCount: num(f.unpaid_count),
      clientBase: num(f.client_base),
      clientCurrency: typeof f.client_currency === "string" ? f.client_currency : null,
      clientReceived: num(f.client_received),
      clientCharge: num(f.client_charge),
      clientRefund: num(f.client_refund),
      clientOwes: num(f.client_owes),
    },
    message: null,
  };
}

export type EditorAdjustment = {
  id: string;
  projectId: string;
  projectTitle: string;
  kind: AdjustmentKind;
  amount: number;
  currency: string;
  revisionRequestId: string | null;
  status: AdjustmentStatus;
  note: string | null;
  offeredAt: string;
};

/**
 * The signed-in editor's own offers, on one project or all (editor pay only; no admin ids or
 * client money).
 */
export async function listMyAdjustments(projectId?: string): Promise<EditorAdjustment[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(
    "editor_list_adjustments",
    projectId ? { p_project_id: projectId } : {},
  );
  if (error) throw new Error("Could not load extra pay offers.");
  return (data ?? []).map((a) => ({
    id: a.id,
    projectId: a.project_id,
    projectTitle: a.project_title,
    kind: a.kind,
    amount: num(a.amount),
    currency: a.currency,
    revisionRequestId: a.revision_request_id,
    status: a.status,
    note: a.note,
    offeredAt: a.offered_at,
  }));
}

/** Gate codes of the editor's own change requests that have not begun. */
export async function getRevisionGates(
  revisionIds: string[],
): Promise<Record<string, RevisionGate | "unknown">> {
  if (revisionIds.length === 0) return {};
  const supabase = await createClient();
  const results = await Promise.all(
    revisionIds.map((id) => supabase.rpc("editor_revision_gate", { p_revision_id: id })),
  );
  const gates: Record<string, RevisionGate | "unknown"> = {};
  results.forEach((r, i) => {
    const id = revisionIds[i];
    // An error is "unknown": the page shows a neutral notice instead of the begin buttons.
    if (id) gates[id] = !r.error && isRevisionGate(r.data) ? r.data : "unknown";
  });
  return gates;
}
