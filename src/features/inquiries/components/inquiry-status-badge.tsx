import { Badge } from "@/components/ui/badge";

import { INQUIRY_STATUS_LABEL, type InquiryStatus } from "../constants";

const VARIANT: Record<InquiryStatus, "default" | "secondary" | "destructive" | "outline"> = {
  new: "default",
  reviewing: "secondary",
  contacted: "secondary",
  in_discussion: "secondary",
  converted: "default",
  declined: "outline",
  closed: "outline",
  spam: "destructive",
};

export function InquiryStatusBadge({ status }: { status: InquiryStatus }) {
  return <Badge variant={VARIANT[status]}>{INQUIRY_STATUS_LABEL[status]}</Badge>;
}
