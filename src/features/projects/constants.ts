export const PROJECT_STATUSES = [
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
export type ProjectStatus = (typeof PROJECT_STATUSES)[number];

export const PROJECT_STATUS_LABEL: Record<ProjectStatus, string> = {
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

export const BRIEF_TYPES = ["fully_instructed", "reference_based", "creative_led"] as const;
export type BriefType = (typeof BRIEF_TYPES)[number];

export const BRIEF_TYPE_LABEL: Record<BriefType, string> = {
  fully_instructed: "Fully instructed",
  reference_based: "Reference-based",
  creative_led: "Creative-led",
};

export const BRIEF_TYPE_HINT: Record<BriefType, string> = {
  fully_instructed: "The client gave complete instructions. Needs written instructions to open.",
  reference_based:
    "The client pointed to examples to follow. Needs at least one reference to open.",
  creative_led: "The editor shapes the result. Needs a desired outcome to open.",
};

export const REFERENCE_PRIORITIES = ["essential", "optional"] as const;
export type ReferencePriority = (typeof REFERENCE_PRIORITIES)[number];

export const MAX_DELIVERABLES = 50;
export const MAX_REFERENCES = 100;

export const DEFAULT_CURRENCY = "LKR";

/** Statuses an admin can move a project to in Phase 4 (spec section 10). */
export const PROJECT_FILTERS = [
  { value: "active", label: "Active" },
  { value: "draft", label: "Draft" },
  { value: "open", label: "Open" },
  { value: "on_hold", label: "On hold" },
  { value: "cancelled", label: "Cancelled" },
  { value: "archived", label: "Archived" },
  { value: "all", label: "All" },
] as const;
export type ProjectFilter = (typeof PROJECT_FILTERS)[number]["value"];

export type StatusAction = {
  to: ProjectStatus;
  label: string;
  confirm?: string;
  destructive?: boolean;
};

/**
 * Allowed admin transitions in Phase 4. The database is the real gate; this only decides which
 * buttons to show. Later statuses (assigned and beyond) have no manual transitions here.
 */
export function allowedStatusActions(
  status: ProjectStatus,
  statusBeforeHold: ProjectStatus | null,
): StatusAction[] {
  switch (status) {
    case "draft":
      return [
        { to: "open", label: "Open project" },
        { to: "on_hold", label: "Put on hold" },
        {
          to: "cancelled",
          label: "Cancel project",
          confirm: "Cancel this project? This cannot be undone.",
          destructive: true,
        },
      ];
    case "open":
      return [
        { to: "draft", label: "Move back to draft" },
        { to: "on_hold", label: "Put on hold" },
        {
          to: "cancelled",
          label: "Cancel project",
          confirm: "Cancel this project? This cannot be undone.",
          destructive: true,
        },
      ];
    case "on_hold": {
      const back = statusBeforeHold ?? "draft";
      return [{ to: back, label: `Resume (back to ${PROJECT_STATUS_LABEL[back].toLowerCase()})` }];
    }
    default:
      return [];
  }
}

const ACTIVITY_LABEL: Record<string, string> = {
  "project.created": "Project created",
  "project.brief_version": "New brief version",
  "project.open": "Opened",
  "project.draft": "Moved back to draft",
  "project.on_hold": "Put on hold",
  "project.cancelled": "Cancelled",
  "inquiry.converted": "Created from inquiry",
  "client.merged": "Client merged",
};

export function activityLabel(action: string): string {
  return ACTIVITY_LABEL[action] ?? "Updated";
}
