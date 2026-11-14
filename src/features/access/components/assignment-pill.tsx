import { StatusPill } from "@/components/status-pill";

import {
  ASSIGNMENT_ADMIN_LABEL,
  ASSIGNMENT_EDITOR_LABEL,
  ASSIGNMENT_TONE,
  type AssignmentStatus,
} from "../constants";

export function AssignmentPill({
  status,
  viewer,
}: {
  status: AssignmentStatus;
  viewer: "admin" | "editor";
}) {
  const label = viewer === "admin" ? ASSIGNMENT_ADMIN_LABEL : ASSIGNMENT_EDITOR_LABEL;
  return <StatusPill tone={ASSIGNMENT_TONE[status]}>{label[status]}</StatusPill>;
}
