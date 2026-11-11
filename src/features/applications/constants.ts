import type { Database } from "@/lib/supabase/database.types";

export type ApplicationStatus = Database["public"]["Enums"]["application_status"];
export type EditorLevel = Database["public"]["Enums"]["editor_level"];
export type RequestKind = Database["public"]["Enums"]["application_request_kind"];
export type AssessmentResult = Database["public"]["Enums"]["assessment_result"];

// Placeholder versions until the editor agreement and privacy notice are approved after
// legal review (KB §12.2, OPEN_QUESTIONS KB8 / P). Recorded on every submission.
export const EDITOR_TERMS_VERSION = "placeholder-2026-11-11";
export const PRIVACY_NOTICE_VERSION = "placeholder-2026-11-11";

export const MAX_PORTFOLIO_LINKS = 10;

export const OPEN_STATUSES: ApplicationStatus[] = [
  "submitted",
  "under_review",
  "info_requested",
  "test_requested",
];

export const STATUS_LABEL: Record<ApplicationStatus, string> = {
  draft: "Draft",
  submitted: "Submitted",
  under_review: "Under review",
  info_requested: "Information requested",
  test_requested: "Practical test requested",
  approved: "Approved",
  rejected: "Not approved",
  withdrawn: "Withdrawn",
};

export const LEVELS: { value: EditorLevel; label: string }[] = [
  { value: "junior", label: "Junior" },
  { value: "professional", label: "Professional" },
  { value: "specialist", label: "Specialist" },
];

export const ASSESSMENT_RESULTS: { value: AssessmentResult; label: string }[] = [
  { value: "passed", label: "Passed" },
  { value: "failed", label: "Failed" },
  { value: "inconclusive", label: "Inconclusive" },
];
