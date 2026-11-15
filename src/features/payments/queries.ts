import "server-only";

import { createClient } from "@/lib/supabase/server";

import type { HoldLabel, PayableReason, PaymentKind, PaymentStatus } from "./constants";
import type { AdminEarningsFilter } from "./schemas";
import type { PaymentLike } from "./summary";

function check<T>(result: { data: T | null; error: unknown }): T {
  if (result.error) throw result.error;
  if (result.data === null) throw new Error("Unexpected empty result");
  return result.data;
}

export type EditorPaymentRow = PaymentLike & {
  id: string;
  projectId: string;
  projectTitle: string;
  milestoneSeq: number;
  /** A fixed label (Under review, Waiting for client payment, ...); never the admin's reason. */
  holdLabel: HoldLabel | null;
  waitingOnClient: boolean;
  splitFromPaymentId: string | null;
  reversesPaymentId: string | null;
  transferDate: string | null;
  transactionReference: string | null;
  createdAt: string;
};

/**
 * The signed-in editor's own payments (editor_list_payments: own rows, project title, milestone,
 * fixed hold label and the waiting flag; never hold/reversal reasons, payable reasons or client money).
 */
export async function listMyPayments(): Promise<EditorPaymentRow[]> {
  const supabase = await createClient();
  const rows = check(await supabase.rpc("editor_list_payments"));
  return rows.map((r) => ({
    id: r.id,
    projectId: r.project_id,
    projectTitle: r.project_title,
    kind: r.kind as PaymentKind,
    status: r.status as PaymentStatus,
    amount: Number(r.amount),
    currency: r.currency,
    dueDate: r.due_date,
    markedPaidAt: r.marked_paid_at,
    milestoneSeq: r.milestone_seq,
    holdLabel: r.hold_label,
    waitingOnClient: r.waiting_on_client,
    splitFromPaymentId: r.split_from_payment_id,
    reversesPaymentId: r.reverses_payment_id,
    transferDate: r.transfer_date,
    transactionReference: r.transaction_reference,
    createdAt: r.created_at,
  }));
}

export type AdminPaymentRow = PaymentLike & {
  id: string;
  editorId: string;
  editorName: string;
  projectId: string;
  projectTitle: string;
  assignmentId: string;
  milestoneSeq: number;
  payableReason: PayableReason | null;
  splitFromPaymentId: string | null;
  transferDate: string | null;
  createdAt: string;
};

const ADMIN_COLUMNS =
  "id, assignment_id, project_id, editor_id, kind, milestone_seq, payable_reason, split_from_payment_id, amount, currency, status, due_date, transfer_date, marked_paid_at, created_at, projects(title)";

/** Names for a set of accounts. Admin only (RLS on profiles). */
async function namesFor(ids: string[]): Promise<Map<string, string>> {
  const unique = Array.from(new Set(ids));
  if (unique.length === 0) return new Map();
  const supabase = await createClient();
  const rows = check(
    await supabase.from("profiles").select("id, full_name, email").in("id", unique),
  );
  return new Map(rows.map((r) => [r.id, r.full_name?.trim() || r.email]));
}

type AdminSelectRow = {
  id: string;
  assignment_id: string;
  project_id: string;
  editor_id: string;
  kind: string;
  milestone_seq: number;
  payable_reason: PayableReason | null;
  split_from_payment_id: string | null;
  amount: number;
  currency: string;
  status: string;
  due_date: string | null;
  transfer_date: string | null;
  marked_paid_at: string | null;
  created_at: string;
  projects: { title: string } | null;
};

/** Every payment (admin RLS), newest first. Filters are applied in the query. */
export async function listAdminPayments(filter?: AdminEarningsFilter): Promise<AdminPaymentRow[]> {
  const supabase = await createClient();
  let query = supabase
    .from("payments")
    .select(ADMIN_COLUMNS)
    .order("created_at", { ascending: false })
    .order("id");
  if (filter?.status) query = query.eq("status", filter.status);
  if (filter?.editor) query = query.eq("editor_id", filter.editor);
  if (filter?.currency) query = query.eq("currency", filter.currency);
  const rows = check(await query) as unknown as AdminSelectRow[];
  const names = await namesFor(rows.map((r) => r.editor_id));
  return rows.map((r) => ({
    id: r.id,
    assignmentId: r.assignment_id,
    projectId: r.project_id,
    projectTitle: r.projects?.title ?? "—",
    editorId: r.editor_id,
    editorName: names.get(r.editor_id) ?? "Unknown editor",
    kind: r.kind as PaymentKind,
    milestoneSeq: r.milestone_seq,
    payableReason: r.payable_reason,
    splitFromPaymentId: r.split_from_payment_id,
    status: r.status as PaymentStatus,
    amount: Number(r.amount),
    currency: r.currency,
    dueDate: r.due_date,
    transferDate: r.transfer_date,
    markedPaidAt: r.marked_paid_at,
    createdAt: r.created_at,
  }));
}

export type ProjectPriceRow = {
  projectId: string;
  title: string;
  clientPrice: number | null;
  clientCurrency: string;
};

/** Client prices for the projects that have payments. Admin only (project_internal RLS). */
export async function listProjectPrices(projectIds: string[]): Promise<ProjectPriceRow[]> {
  const unique = Array.from(new Set(projectIds));
  if (unique.length === 0) return [];
  const supabase = await createClient();
  const [internal, projects] = await Promise.all([
    supabase
      .from("project_internal")
      .select("project_id, client_price, client_price_currency")
      .in("project_id", unique),
    supabase.from("projects").select("id, title").in("id", unique),
  ]);
  const prices = new Map(check(internal).map((r) => [r.project_id, r]));
  return check(projects)
    .map((p) => {
      const price = prices.get(p.id);
      return {
        projectId: p.id,
        title: p.title,
        clientPrice:
          price?.client_price === null || price === undefined ? null : Number(price.client_price),
        clientCurrency: price?.client_price_currency ?? "LKR",
      };
    })
    .sort((a, b) => a.title.localeCompare(b.title));
}

export type AdminPaymentDetail = {
  id: string;
  assignmentId: string;
  projectId: string;
  projectTitle: string;
  editorId: string;
  editorName: string;
  kind: PaymentKind;
  status: PaymentStatus;
  amount: number;
  currency: string;
  heldFromStatus: PaymentStatus | null;
  onHoldReason: string | null;
  milestoneSeq: number;
  payableReason: PayableReason | null;
  payableAt: string | null;
  waitingOnClient: boolean;
  splitFromPaymentId: string | null;
  amountBeforeSplit: number | null;
  splitChildId: string | null;
  dueDate: string | null;
  transferDate: string | null;
  transactionReference: string | null;
  reversesPaymentId: string | null;
  reversalReason: string | null;
  reversedById: string | null;
  approvedBy: string | null;
  approvedAt: string | null;
  markedPaidBy: string | null;
  markedPaidAt: string | null;
  createdAt: string;
  notes: { id: string; note: string; author: string; createdAt: string }[];
  activity: { id: number; action: string; actor: string | null; createdAt: string }[];
};

/** One payment with notes, reversal links and history. Admin only. */
export async function getAdminPayment(id: string): Promise<AdminPaymentDetail | null> {
  const supabase = await createClient();
  const { data: p, error } = await supabase
    .from("payments")
    .select(
      "id, assignment_id, project_id, editor_id, kind, milestone_seq, payable_reason, payable_at, waiting_on_client, split_from_payment_id, amount_before_split, amount, currency, status, held_from_status, on_hold_reason, due_date, transfer_date, transaction_reference, reverses_payment_id, reversal_reason, approved_by, approved_at, marked_paid_by, marked_paid_at, created_at, projects(title)",
    )
    .eq("id", id)
    .maybeSingle();
  if (error) throw error;
  if (!p) return null;

  const [reversal, splitChild, notes, activity] = await Promise.all([
    supabase.from("payments").select("id").eq("reverses_payment_id", id).maybeSingle(),
    supabase.from("payments").select("id").eq("split_from_payment_id", id).maybeSingle(),
    supabase
      .from("payment_notes")
      .select("id, note, author_id, created_at")
      .eq("payment_id", id)
      .order("created_at", { ascending: false }),
    supabase
      .from("activity_logs")
      .select("id, action, actor_id, created_at")
      .eq("entity_type", "payment")
      .eq("entity_id", id)
      .order("created_at", { ascending: false })
      .order("id", { ascending: false })
      .limit(50),
  ]);
  if (reversal.error) throw reversal.error;
  if (splitChild.error) throw splitChild.error;
  const noteRows = check(notes);
  const activityRows = check(activity);
  const names = await namesFor(
    [
      p.editor_id,
      p.approved_by,
      p.marked_paid_by,
      ...noteRows.map((n) => n.author_id),
      ...activityRows.map((a) => a.actor_id),
    ].filter((v): v is string => typeof v === "string"),
  );
  const name = (uid: string | null) => (uid ? (names.get(uid) ?? "Former account") : null);
  const project = p.projects as unknown as { title: string } | null;

  return {
    id: p.id,
    assignmentId: p.assignment_id,
    projectId: p.project_id,
    projectTitle: project?.title ?? "—",
    editorId: p.editor_id,
    editorName: name(p.editor_id) ?? "Unknown editor",
    kind: p.kind as PaymentKind,
    status: p.status as PaymentStatus,
    amount: Number(p.amount),
    currency: p.currency,
    heldFromStatus: p.held_from_status as PaymentStatus | null,
    onHoldReason: p.on_hold_reason,
    milestoneSeq: p.milestone_seq,
    payableReason: p.payable_reason,
    payableAt: p.payable_at,
    waitingOnClient: p.waiting_on_client,
    splitFromPaymentId: p.split_from_payment_id,
    amountBeforeSplit: p.amount_before_split === null ? null : Number(p.amount_before_split),
    splitChildId: splitChild.data?.id ?? null,
    dueDate: p.due_date,
    transferDate: p.transfer_date,
    transactionReference: p.transaction_reference,
    reversesPaymentId: p.reverses_payment_id,
    reversalReason: p.reversal_reason,
    reversedById: reversal.data?.id ?? null,
    approvedBy: name(p.approved_by),
    approvedAt: p.approved_at,
    markedPaidBy: name(p.marked_paid_by),
    markedPaidAt: p.marked_paid_at,
    createdAt: p.created_at,
    notes: noteRows.map((n) => ({
      id: n.id,
      note: n.note,
      author: name(n.author_id) ?? "Former account",
      createdAt: n.created_at,
    })),
    activity: activityRows.map((a) => ({
      id: a.id,
      action: a.action,
      actor: name(a.actor_id),
      createdAt: a.created_at,
    })),
  };
}
