/**
 * Plain-language labels for `activity_logs.action` codes. Codes come from the audit triggers and
 * admin functions in supabase/migrations; unknown codes fall back to "Updated".
 */
const ACTIVITY_LABEL: Record<string, string> = {
  "account.registered": "Account registered",

  "admin.granted": "Admin access granted",
  "admin.revoked": "Admin access revoked",
  "admin.restored": "Admin access restored",
  "admin.deleted": "Admin removed",
  "admin.updated": "Admin updated",

  "editor.access_changed": "Editor access changed",

  "application.draft": "Application started",
  "application.submitted": "Application submitted",
  "application.under_review": "Review started",
  "application.info_requested": "More information requested",
  "application.test_requested": "Test requested",
  "application.approved": "Application approved",
  "application.rejected": "Application rejected",
  "application.withdrawn": "Application withdrawn",
  "application_request.created": "Request sent",
  "application_request.answered": "Request answered",
  "application_request.updated": "Request updated",
  "assessment.recorded": "Assessment recorded",

  "inquiry.submitted": "Submitted",
  "inquiry.new": "Marked new",
  "inquiry.reviewing": "Marked reviewing",
  "inquiry.contacted": "Marked contacted",
  "inquiry.in_discussion": "In discussion",
  "inquiry.converted": "Converted to project",
  "inquiry.declined": "Declined",
  "inquiry.closed": "Closed",
  "inquiry.spam": "Marked as spam",

  "project.created": "Project created",
  "project.brief_version": "New brief version",
  "project.pricing_changed": "Pricing changed",
  "project.archived": "Archived",
  "project.restored": "Restored",
  "project.draft": "Moved back to draft",
  "project.open": "Opened",
  "project.assigned": "Assigned",
  "project.in_progress": "In progress",
  "project.in_review": "In review",
  "project.revision_requested": "Revision requested",
  "project.approved": "Approved",
  "project.completed": "Completed",
  "project.on_hold": "Put on hold",
  "project.cancelled": "Cancelled",

  "client.merged": "Client merged",
};

export function activityLabel(action: string): string {
  return ACTIVITY_LABEL[action] ?? "Updated";
}
