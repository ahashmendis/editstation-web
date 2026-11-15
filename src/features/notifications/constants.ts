import type { Database } from "@/lib/supabase/database.types";

export type NotificationKind = Database["public"]["Enums"]["notification_kind"];

export type NotificationRow = {
  id: string;
  kind: NotificationKind;
  entity_type: string;
  entity_id: string;
  title: string;
  body: string;
  created_at: string;
  read_at: string | null;
};

/**
 * Where a notification leads. The kind decides the area (each kind has exactly one audience, see
 * the Phase 10 migration); the target page still enforces access on its own.
 */
export function notificationHref(n: Pick<NotificationRow, "kind" | "entity_id">): string {
  switch (n.kind) {
    case "inquiry_new":
      return `/admin/inquiries/${n.entity_id}`;
    case "application_new":
    case "applicant_response":
      return `/admin/applications/${n.entity_id}`;
    case "counteroffer":
    case "submission":
      return `/admin/projects/${n.entity_id}`;
    case "application_decision":
    case "application_request":
      return "/apply";
    case "invitation":
    case "assignment_confirmed":
    case "revision_requested":
      return `/editor/projects/${n.entity_id}`;
    case "payment_paid":
      return "/editor/earnings";
  }
}

/** Badge text for the bell; large counts are capped so the badge stays small. */
export function unreadBadge(count: number): string | null {
  if (count <= 0) return null;
  return count > 99 ? "99+" : String(count);
}
