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

  "project.assets_changed": "Assets changed",
  "project.early_access_changed": "Early-access setting changed",
  "project.note_added": "Note added",
  "asset_grant.recorded": "Folder share recorded",
  "asset_grant.revoked": "Folder share removed",
  "project_access.granted": "Editor invited",
  "project_access.revoked": "Editor access removed",
  "assignment.offered": "Offer sent",
  "assignment.counteroffer_pending": "Counteroffer received",
  "assignment.accepted": "Offer accepted",
  "assignment.confirmed": "Editor confirmed",
  "assignment.declined": "Offer declined",
  "assignment.withdrawn": "Offer withdrawn",
  "assignment.not_selected": "Editor not selected",
  "assignment.reassigned": "Editor reassigned",

  "interpretation.submitted": "Interpretation submitted",
  "interpretation.accepted": "Interpretation accepted",
  "interpretation.changes_requested": "Interpretation changes requested",
  "brief_confirmation.confirmed": "Brief confirmed",
  "brief_confirmation.carried_forward": "Brief confirmation carried forward",
  "assignment.in_progress": "Work started",

  "submission.submitted": "Work submitted",
  "submission.reviewed": "Submission reviewed",
  "revision_request.created": "Change requested",
  "revision_request.classified": "Change request classified",
  "revision_request.acknowledged": "Change request acknowledged",
  "revision_request.in_progress": "Revision in progress",
  "revision_request.resubmitted": "Revision resubmitted",
  "revision_request.approved": "Revision approved",

  "payment.created": "Payment record created",
  "payment.pending_approval": "Sent for approval",
  "payment.approved": "Payment approved",
  "payment.processing": "Transfer in progress",
  "payment.paid": "Marked paid",
  "payment.on_hold": "Put on hold",
  "payment.hold_released": "Hold released",
  "payment.due_date_set": "Due date set",
  "payment.reversed": "Payment reversed",
  "payment_note.added": "Note added",

  "client.merged": "Client merged",
};

export function activityLabel(action: string): string {
  return ACTIVITY_LABEL[action] ?? "Updated";
}

/** Every known action code with its label, sorted by label (for the activity filter). */
export function activityActions(): { code: string; label: string }[] {
  return Object.entries(ACTIVITY_LABEL)
    .map(([code, label]) => ({ code, label }))
    .sort((a, b) => a.label.localeCompare(b.label) || a.code.localeCompare(b.code));
}

export function isKnownActivityAction(code: string): boolean {
  return Object.hasOwn(ACTIVITY_LABEL, code);
}

/** Plain names for `activity_logs.entity_type`. */
export const ENTITY_TYPE_LABEL: Record<string, string> = {
  admin_user: "Admin",
  profile: "Account",
  editor_profile: "Editor access",
  editor_application: "Application",
  application_request: "Application request",
  client_inquiry: "Client inquiry",
  client: "Client",
  project: "Project",
  project_access: "Project access",
  asset_grant: "Folder share",
  assignment: "Assignment",
  interpretation: "Interpretation",
  brief_confirmation: "Brief confirmation",
  submission: "Submission",
  revision_request: "Change request",
  payment: "Payment",
};

export function entityTypeLabel(entityType: string): string {
  return ENTITY_TYPE_LABEL[entityType] ?? entityType.replaceAll("_", " ");
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Admin page for an audit row's entity, when one exists. */
export function activityEntityHref(entityType: string, entityId: string): string | null {
  if (!UUID.test(entityId)) return null;
  switch (entityType) {
    case "project":
      return `/admin/projects/${entityId}`;
    case "client_inquiry":
      return `/admin/inquiries/${entityId}`;
    case "editor_application":
      return `/admin/applications/${entityId}`;
    case "payment":
      return `/admin/earnings/${entityId}`;
    default:
      return null;
  }
}
