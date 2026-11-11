import { Badge } from "@/components/ui/badge";

import { STATUS_LABEL, type ApplicationStatus } from "../constants";

const VARIANT: Record<ApplicationStatus, "default" | "secondary" | "destructive" | "outline"> = {
  draft: "outline",
  submitted: "secondary",
  under_review: "secondary",
  info_requested: "outline",
  test_requested: "outline",
  approved: "default",
  rejected: "destructive",
  withdrawn: "outline",
};

export function StatusBadge({ status }: { status: ApplicationStatus }) {
  return <Badge variant={VARIANT[status]}>{STATUS_LABEL[status]}</Badge>;
}

export function formatDateTime(value: string | null | undefined): string {
  if (!value) return "—";
  return `${new Date(value).toISOString().replace("T", " ").slice(0, 16)} UTC`;
}
