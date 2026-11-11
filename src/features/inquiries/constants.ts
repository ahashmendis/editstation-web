import type { Database } from "@/lib/supabase/database.types";

export type InquiryStatus = Database["public"]["Enums"]["inquiry_status"];

export const MAX_REFERENCE_LINKS = 10;

/** Placeholder until the privacy notice is approved (OPEN_QUESTIONS P, KB §12.3). */
export { PRIVACY_NOTICE_VERSION } from "@/features/applications/constants";

export const INQUIRY_STATUS_LABEL: Record<InquiryStatus, string> = {
  new: "New",
  reviewing: "Reviewing",
  contacted: "Contacted",
  in_discussion: "In discussion",
  converted: "Converted to project",
  declined: "Declined",
  closed: "Closed",
  spam: "Spam",
};

export const OPEN_INQUIRY_STATUSES: InquiryStatus[] = [
  "new",
  "reviewing",
  "contacted",
  "in_discussion",
];

/** Statuses an admin can set by hand. `converted` happens only when a project is created. */
export const SETTABLE_INQUIRY_STATUSES: InquiryStatus[] = [
  "new",
  "reviewing",
  "contacted",
  "in_discussion",
  "declined",
  "closed",
  "spam",
];
