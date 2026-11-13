import { StatusPill, type StatusTone } from "@/components/status-pill";

import { INQUIRY_STATUS_LABEL, type InquiryStatus } from "../constants";

const TONE: Record<InquiryStatus, StatusTone> = {
  new: "warning", // nobody has looked at it yet
  reviewing: "info",
  contacted: "info",
  in_discussion: "info",
  converted: "success",
  declined: "neutral",
  closed: "neutral",
  spam: "danger",
};

export function InquiryStatusBadge({ status }: { status: InquiryStatus }) {
  return <StatusPill tone={TONE[status]}>{INQUIRY_STATUS_LABEL[status]}</StatusPill>;
}
