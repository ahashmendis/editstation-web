import { StatusPill, type StatusTone } from "@/components/status-pill";

import { PROJECT_STATUS_LABEL, type ProjectStatus } from "../constants";

const TONE: Record<ProjectStatus, StatusTone> = {
  draft: "neutral",
  open: "info",
  on_hold: "warning",
  cancelled: "danger",
  // Later phases: neutral until their workflows are built.
  assigned: "neutral",
  in_progress: "neutral",
  in_review: "neutral",
  revision_requested: "neutral",
  approved: "neutral",
  completed: "neutral",
};

export function ProjectStatusPill({ status }: { status: ProjectStatus }) {
  return <StatusPill tone={TONE[status]}>{PROJECT_STATUS_LABEL[status]}</StatusPill>;
}
