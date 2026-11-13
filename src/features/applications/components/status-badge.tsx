import { StatusPill, type StatusTone } from "@/components/status-pill";

import { STATUS_LABEL, type ApplicationStatus } from "../constants";

const TONE: Record<ApplicationStatus, StatusTone> = {
  draft: "neutral",
  submitted: "warning", // waiting for an admin to start the review
  under_review: "info",
  info_requested: "info", // waiting on the applicant
  test_requested: "info",
  approved: "success",
  rejected: "danger",
  withdrawn: "neutral",
};

export function StatusBadge({ status }: { status: ApplicationStatus }) {
  return <StatusPill tone={TONE[status]}>{STATUS_LABEL[status]}</StatusPill>;
}

export function formatDateTime(value: string | null | undefined): string {
  if (!value) return "—";
  return `${new Date(value).toISOString().replace("T", " ").slice(0, 16)} UTC`;
}
