import "server-only";

import { createClient } from "@/lib/supabase/server";

import type { AssignmentStatus, NegotiationAction } from "./constants";

function check<T>(result: { data: T | null; error: unknown }): T {
  if (result.error) throw result.error;
  if (result.data === null) throw new Error("Unexpected empty result");
  return result.data;
}

export type PersonName = { id: string; name: string; email: string };

/** Names and emails for a set of accounts. Admin only (RLS on profiles). */
async function namesFor(ids: string[]): Promise<Map<string, PersonName>> {
  const unique = Array.from(new Set(ids));
  if (unique.length === 0) return new Map();
  const supabase = await createClient();
  const rows = check(
    await supabase.from("profiles").select("id, full_name, email").in("id", unique),
  );
  return new Map(
    rows.map((r) => [r.id, { id: r.id, name: r.full_name?.trim() || r.email, email: r.email }]),
  );
}

export type AdminAssignment = {
  id: string;
  editorId: string;
  status: AssignmentStatus;
  proposedAmount: number;
  currency: string;
  agreedAmount: number | null;
  agreedCurrency: string | null;
  confirmedAt: string | null;
  closedAt: string | null;
  createdAt: string;
};

export type AdminNegotiation = {
  id: string;
  assignmentId: string;
  fromRole: "admin" | "editor";
  action: NegotiationAction;
  amount: number | null;
  currency: string | null;
  message: string | null;
  createdAt: string;
};

/** Everything the admin project page needs for assets, editors, folder shares and notes. */
export async function getProjectAccessData(projectId: string) {
  const supabase = await createClient();
  const [assets, access, assignments, grants, notes, activeEditors] = await Promise.all([
    supabase
      .from("project_assets")
      .select("id, label, url, provider, kind, notes, early_access")
      .eq("project_id", projectId)
      .order("sort_order")
      .order("id"),
    supabase
      .from("project_access")
      .select("editor_id, reason, granted_at, revoked_at")
      .eq("project_id", projectId),
    supabase
      .from("assignments")
      .select(
        "id, editor_id, status, proposed_amount, currency, agreed_amount, agreed_currency, confirmed_at, closed_at, created_at",
      )
      .eq("project_id", projectId)
      .order("created_at", { ascending: false }),
    supabase
      .from("asset_access_grants")
      .select(
        "id, editor_id, shared_with_email, provider, folder_url, shared_at, revoked_at, revoke_reason",
      )
      .eq("project_id", projectId)
      .order("shared_at", { ascending: false }),
    supabase
      .from("project_notes")
      .select("id, author_id, note, created_at")
      .eq("project_id", projectId)
      .order("created_at", { ascending: false })
      .limit(200),
    supabase.from("editor_profiles").select("user_id").eq("access_status", "active"),
  ]);

  const assignmentRows = check(assignments);
  const negotiations = assignmentRows.length
    ? check(
        await supabase
          .from("negotiation_offers")
          .select("id, assignment_id, from_role, action, amount, currency, message, created_at")
          .in(
            "assignment_id",
            assignmentRows.map((a) => a.id),
          )
          .order("created_at"),
      )
    : [];
  const assignmentEditorIds = Array.from(new Set(assignmentRows.map((a) => a.editor_id)));
  const editorStatuses = assignmentEditorIds.length
    ? check(
        await supabase
          .from("editor_profiles")
          .select("user_id, access_status")
          .in("user_id", assignmentEditorIds),
      )
    : [];
  const accessStatus = new Map(editorStatuses.map((e) => [e.user_id, e.access_status]));

  const accessRows = check(access);
  const grantRows = check(grants);
  const noteRows = check(notes);
  const activeIds = check(activeEditors).map((e) => e.user_id);

  const names = await namesFor([
    ...activeIds,
    ...accessRows.map((a) => a.editor_id),
    ...assignmentRows.map((a) => a.editor_id),
    ...grantRows.map((g) => g.editor_id),
    ...noteRows.map((n) => n.author_id).filter((id): id is string => id !== null),
  ]);
  const nameOf = (id: string | null) =>
    id ? (names.get(id)?.name ?? "Unknown editor") : "Removed account";

  return {
    assets: check(assets),
    access: accessRows.map((a) => ({
      editorId: a.editor_id,
      reason: a.reason,
      grantedAt: a.granted_at,
      live: a.revoked_at === null,
    })),
    assignments: assignmentRows.map((a): AdminAssignment => ({
      id: a.id,
      editorId: a.editor_id,
      status: a.status,
      proposedAmount: Number(a.proposed_amount),
      currency: a.currency,
      agreedAmount: a.agreed_amount === null ? null : Number(a.agreed_amount),
      agreedCurrency: a.agreed_currency,
      confirmedAt: a.confirmed_at,
      closedAt: a.closed_at,
      createdAt: a.created_at,
    })),
    negotiations: negotiations.map((n): AdminNegotiation => ({
      id: n.id,
      assignmentId: n.assignment_id,
      fromRole: n.from_role,
      action: n.action,
      amount: n.amount === null ? null : Number(n.amount),
      currency: n.currency,
      message: n.message,
      createdAt: n.created_at,
    })),
    grants: grantRows.map((g) => ({
      id: g.id,
      editorName: nameOf(g.editor_id),
      email: g.shared_with_email,
      provider: g.provider,
      folderUrl: g.folder_url,
      sharedAt: g.shared_at,
      revokedAt: g.revoked_at,
      revokeReason: g.revoke_reason,
    })),
    notes: noteRows.map((n) => ({
      id: n.id,
      author: nameOf(n.author_id),
      note: n.note,
      createdAt: n.created_at,
    })),
    /** Active editors, for the invite and folder-share pickers. */
    editorOptions: activeIds
      .map((id) => ({ id, name: nameOf(id), email: names.get(id)?.email ?? "" }))
      .sort((a, b) => a.name.localeCompare(b.name)),
    nameOf,
    /** editor_profiles.access_status for editors holding an assignment on this project. */
    accessStatusOf: (id: string) => accessStatus.get(id),
  };
}

export type PendingRevocation = {
  grantId: string;
  projectId: string;
  projectTitle: string;
  editorName: string;
  sharedWithEmail: string;
  provider: string;
  folderUrl: string | null;
  sharedAt: string;
  reason: string;
};

/** The revoke checklist: live folder shares that should be taken back. */
export async function listPendingRevocations(): Promise<PendingRevocation[]> {
  const supabase = await createClient();
  const rows = check(await supabase.rpc("admin_pending_revocations"));
  if (rows.length === 0) return [];
  const [names, projects] = await Promise.all([
    namesFor(rows.map((r) => r.editor_id)),
    supabase
      .from("projects")
      .select("id, title")
      .in("id", Array.from(new Set(rows.map((r) => r.project_id)))),
  ]);
  const titles = new Map(check(projects).map((p) => [p.id, p.title]));
  return rows.map((r) => ({
    grantId: r.grant_id,
    projectId: r.project_id,
    projectTitle: titles.get(r.project_id) ?? "Project",
    editorName: names.get(r.editor_id)?.name ?? "Unknown editor",
    sharedWithEmail: r.shared_with_email,
    provider: r.provider,
    folderUrl: r.folder_url,
    sharedAt: r.shared_at,
    reason: r.reason,
  }));
}

// --- Editor side (RLS filters everything to what this editor may see) -----------------------

export type EditorAssignment = {
  id: string;
  status: AssignmentStatus;
  proposedAmount: number;
  currency: string;
  agreedAmount: number | null;
  agreedCurrency: string | null;
  createdAt: string;
};

const PROJECT_LIMIT = 200;
const ASSIGNMENT_LIMIT = 500;
const LIVE_STATUSES: string[] = ["offered", "counteroffer_pending", "accepted", "confirmed"];

export async function getEditorDashboard() {
  const supabase = await createClient();
  const [projects, assignments] = await Promise.all([
    supabase
      .from("projects")
      .select("id, title, brief_type, status, deadline, proposed_amount, proposed_currency")
      .order("updated_at", { ascending: false })
      .limit(200),
    supabase
      .from("assignments")
      .select("id, project_id, status, proposed_amount, currency, created_at")
      .order("created_at", { ascending: false })
      .limit(500),
  ]);
  const projectRows = check(projects);
  const assignmentRows = check(assignments);
  // Capped queries (most recent first). Fine for an internal studio; `truncated` tells the page
  // to say so instead of silently hiding older projects.
  const truncated =
    projectRows.length >= PROJECT_LIMIT || assignmentRows.length >= ASSIGNMENT_LIMIT;

  const confirmed = new Set(
    assignmentRows
      .filter((a) => a.status === "confirmed" || a.status === "in_progress")
      .map((a) => a.project_id),
  );
  // Newest live assignment per project drives the card's amount (same rule as getEditorProject);
  // with none live, the newest one is kept only so the card can show its closed state.
  const latest = new Map<string, (typeof assignmentRows)[number]>();
  const liveOffer = new Map<string, (typeof assignmentRows)[number]>();
  for (const a of assignmentRows) {
    if (!latest.has(a.project_id)) latest.set(a.project_id, a);
    if (LIVE_STATUSES.includes(a.status) && !liveOffer.has(a.project_id)) {
      liveOffer.set(a.project_id, a);
    }
  }

  const card = (p: (typeof projectRows)[number]) => {
    const live = liveOffer.get(p.id);
    const a = live ?? latest.get(p.id);
    return {
      id: p.id,
      title: p.title,
      briefType: p.brief_type,
      status: p.status,
      deadline: p.deadline,
      offer: a
        ? {
            status: a.status as AssignmentStatus,
            live: Boolean(live),
            amount: Number(a.proposed_amount),
            currency: a.currency,
          }
        : null,
      baseline:
        p.proposed_amount === null
          ? null
          : { amount: Number(p.proposed_amount), currency: p.proposed_currency },
    };
  };

  return {
    opportunities: projectRows.filter((p) => !confirmed.has(p.id)).map(card),
    myProjects: projectRows.filter((p) => confirmed.has(p.id)).map(card),
    truncated,
    limit: PROJECT_LIMIT,
  };
}

/** One project as this editor may see it. Null when RLS shows them nothing. */
export async function getEditorProject(projectId: string) {
  const supabase = await createClient();
  const { data: project, error } = await supabase
    .from("projects")
    .select(
      "id, title, brief_type, service_type_code, summary, deadline, status, current_brief_version, proposed_amount, proposed_currency, revision_allowance",
    )
    .eq("id", projectId)
    .maybeSingle();
  if (error) throw error;
  if (!project) return null;

  const [service, deliverables, references, assets, assignments, brief] = await Promise.all([
    project.service_type_code
      ? supabase
          .from("service_types")
          .select("label")
          .eq("code", project.service_type_code)
          .maybeSingle()
      : Promise.resolve({ data: null, error: null }),
    supabase
      .from("project_deliverables")
      .select("id, name, format, resolution, aspect_ratio, duration_seconds, notes")
      .eq("project_id", projectId)
      .order("sort_order")
      .order("id"),
    supabase
      .from("project_references")
      .select(
        "id, title, url, start_seconds, end_seconds, observation_notes, priority, category, access_notes, early_access",
      )
      .eq("project_id", projectId)
      .order("sort_order")
      .order("id"),
    supabase
      .from("project_assets")
      .select("id, label, url, provider, kind, notes, early_access")
      .eq("project_id", projectId)
      .order("sort_order")
      .order("id"),
    supabase
      .from("assignments")
      .select("id, status, proposed_amount, currency, agreed_amount, agreed_currency, created_at")
      .eq("project_id", projectId)
      .order("created_at", { ascending: false }),
    supabase
      .from("brief_versions")
      .select(
        "version, instructions, desired_outcome, audience, core_message, brand_constraints, mandatory_content, prohibited_content",
      )
      .eq("project_id", projectId)
      .eq("version", project.current_brief_version)
      .maybeSingle(),
  ]);
  if (service.error) throw service.error;
  if (brief.error) throw brief.error;

  const assignmentRows = check(assignments);
  const negotiations = assignmentRows.length
    ? check(
        await supabase
          .from("negotiation_offers")
          .select("id, assignment_id, from_role, action, amount, currency, message, created_at")
          .in(
            "assignment_id",
            assignmentRows.map((a) => a.id),
          )
          .order("created_at"),
      )
    : [];

  const mine = assignmentRows.map((a): EditorAssignment => ({
    id: a.id,
    status: a.status,
    proposedAmount: Number(a.proposed_amount),
    currency: a.currency,
    agreedAmount: a.agreed_amount === null ? null : Number(a.agreed_amount),
    agreedCurrency: a.agreed_currency,
    createdAt: a.created_at,
  }));

  return {
    project,
    serviceLabel: service.data?.label ?? null,
    deliverables: check(deliverables),
    references: check(references),
    assets: check(assets),
    brief: brief.data,
    assignments: mine,
    /** The assignment to act on: a live one if any, else the newest. */
    current:
      mine.find(
        (a) =>
          a.status !== "declined" &&
          a.status !== "withdrawn" &&
          a.status !== "not_selected" &&
          a.status !== "reassigned",
      ) ??
      mine[0] ??
      null,
    negotiations: negotiations.map(
      (
        n,
      ): {
        id: string;
        assignmentId: string;
        fromRole: "admin" | "editor";
        action: NegotiationAction;
        amount: number | null;
        currency: string | null;
        message: string | null;
        createdAt: string;
      } => ({
        id: n.id,
        assignmentId: n.assignment_id,
        fromRole: n.from_role,
        action: n.action,
        amount: n.amount === null ? null : Number(n.amount),
        currency: n.currency,
        message: n.message,
        createdAt: n.created_at,
      }),
    ),
  };
}
