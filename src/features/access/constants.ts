import type { StatusTone } from "@/components/status-pill";

/** Shown next to early-access toggles and fields that invited editors may read. */
export const EARLY_ACCESS_HINT =
  "Early-access items, including their notes and links, are visible to every invited editor. Don't put client names or passwords here.";

export const ASSET_PROVIDERS = ["google_drive", "dropbox", "other"] as const;
export type AssetProvider = (typeof ASSET_PROVIDERS)[number];
export const ASSET_PROVIDER_LABEL: Record<AssetProvider, string> = {
  google_drive: "Google Drive",
  dropbox: "Dropbox",
  other: "Other",
};

/** Suggestions only: the database accepts any kind of 1 to 40 characters. */
export const ASSET_KIND_SUGGESTIONS = [
  "footage",
  "music",
  "graphics",
  "brand",
  "script",
  "other",
] as const;

export const MAX_ASSETS = 100;
export const MAX_INVITES = 100;

export const ACCESS_REASONS = ["invited", "available"] as const;
export type AccessReason = (typeof ACCESS_REASONS)[number];
export const ACCESS_REASON_LABEL: Record<AccessReason, string> = {
  invited: "Invited personally",
  available: "Available to eligible editors",
};

export const ASSIGNMENT_STATUSES = [
  "offered",
  "counteroffer_pending",
  "accepted",
  "confirmed",
  "in_progress",
  "declined",
  "withdrawn",
  "not_selected",
  "reassigned",
] as const;
export type AssignmentStatus = (typeof ASSIGNMENT_STATUSES)[number];

/** Admin-side labels (spec section 8). */
export const ASSIGNMENT_ADMIN_LABEL: Record<AssignmentStatus, string> = {
  offered: "Offer sent",
  counteroffer_pending: "Counteroffer",
  accepted: "Accepted",
  confirmed: "Confirmed",
  in_progress: "In progress",
  declined: "Declined",
  withdrawn: "Withdrawn",
  not_selected: "Not selected",
  reassigned: "Reassigned",
};

/** Editor-side labels: the same states from the editor's point of view. */
export const ASSIGNMENT_EDITOR_LABEL: Record<AssignmentStatus, string> = {
  offered: "Offer received",
  counteroffer_pending: "Counteroffer sent",
  accepted: "Accepted, waiting for confirmation",
  confirmed: "Confirmed",
  in_progress: "In progress",
  declined: "Declined",
  withdrawn: "Offer withdrawn",
  not_selected: "Not selected",
  reassigned: "Reassigned",
};

export const ASSIGNMENT_TONE: Record<AssignmentStatus, StatusTone> = {
  offered: "info",
  counteroffer_pending: "warning", // needs the admin's reply
  accepted: "warning", // needs the admin's confirmation
  confirmed: "success",
  in_progress: "success",
  declined: "neutral",
  withdrawn: "neutral",
  not_selected: "neutral",
  reassigned: "neutral",
};

export const LIVE_ASSIGNMENT_STATUSES: readonly AssignmentStatus[] = [
  "offered",
  "counteroffer_pending",
  "accepted",
  "confirmed",
  "in_progress",
];

export function isLiveAssignment(status: AssignmentStatus): boolean {
  return LIVE_ASSIGNMENT_STATUSES.includes(status);
}

/**
 * Warning badge for an editor whose access is no longer active while they still hold a live or
 * confirmed assignment. Suspension never closes assignments automatically (WORKFLOWS §6): the admin
 * decides per assignment, so the project page must make the state visible.
 */
export function editorAccessWarning(
  accessStatus: "none" | "active" | "suspended" | "revoked" | undefined,
  currentAssignment: AssignmentStatus | null,
): string | null {
  if (accessStatus === "active" || !currentAssignment || !isLiveAssignment(currentAssignment)) {
    return null;
  }
  if (accessStatus === "suspended") return "Suspended";
  if (accessStatus === "revoked") return "Access revoked";
  return "Access not active";
}

export const NEGOTIATION_ACTION_LABEL = {
  offer: "made an offer",
  counter: "proposed a different amount",
  accept: "accepted",
  decline: "declined",
  withdraw: "withdrew the offer",
} as const;
export type NegotiationAction = keyof typeof NEGOTIATION_ACTION_LABEL;

export const RESPOND_ACTIONS = ["accept", "counter", "decline"] as const;
export type RespondAction = (typeof RESPOND_ACTIONS)[number];

export type EditorRowInput = {
  /** Has a live (not revoked) project_access row. */
  hasLiveAccess: boolean;
  /** The editor's assignments on this project, newest first. */
  assignments: { status: AssignmentStatus }[];
};

export type EditorLabel = {
  label: string;
  tone: StatusTone;
  assignmentStatus: AssignmentStatus | null;
};

/**
 * One label per editor on the admin project page (spec section 8): a live assignment wins, then
 * a live invitation, then the most recent closed assignment, then "Access removed".
 */
export function editorLabel({ hasLiveAccess, assignments }: EditorRowInput): EditorLabel {
  const live = assignments.find((a) => isLiveAssignment(a.status));
  if (live) {
    return {
      label: ASSIGNMENT_ADMIN_LABEL[live.status],
      tone: ASSIGNMENT_TONE[live.status],
      assignmentStatus: live.status,
    };
  }
  if (hasLiveAccess) return { label: "Invited", tone: "info", assignmentStatus: null };
  const latest = assignments[0];
  if (latest) {
    return {
      label: ASSIGNMENT_ADMIN_LABEL[latest.status],
      tone: ASSIGNMENT_TONE[latest.status],
      assignmentStatus: latest.status,
    };
  }
  return { label: "Access removed", tone: "neutral", assignmentStatus: null };
}

/** Project-level summary such as "2 invited · 1 counteroffer" (computed in the app, decision J). */
export function summariseEditorLabels(labels: EditorLabel[]): string {
  const order = ["Invited", "Offer sent", "Counteroffer", "Accepted", "Confirmed"];
  const counts = new Map<string, number>();
  for (const l of labels) counts.set(l.label, (counts.get(l.label) ?? 0) + 1);
  return order
    .filter((name) => counts.has(name))
    .map((name) => `${counts.get(name)} ${name.toLowerCase()}`)
    .join(" · ");
}

export const REVOCATION_REASON_LABEL: Record<string, string> = {
  editor_not_active: "The editor no longer has active access.",
  project_closed: "The project is closed.",
  no_active_assignment: "The editor has no live offer or assignment on this project.",
};

export function formatMoney(amount: number | string | null, currency: string | null): string {
  if (amount === null || amount === undefined) return "—";
  const n = Number(amount);
  const text = Number.isInteger(n)
    ? n.toLocaleString("en-US")
    : n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  return `${text} ${currency ?? ""}`.trim();
}
