import { StatusPill } from "@/components/status-pill";

import {
  PAYMENT_STATUS_LABEL,
  PAYMENT_STATUS_TONE,
  REVERSAL_LABEL,
  type PaymentKind,
  type PaymentStatus,
} from "../constants";

/** Status of a payment; reversal rows read "Correction" (spec §11). */
export function PaymentStatusPill({ status, kind }: { status: PaymentStatus; kind: PaymentKind }) {
  if (kind === "reversal") return <StatusPill tone="neutral">{REVERSAL_LABEL}</StatusPill>;
  return <StatusPill tone={PAYMENT_STATUS_TONE[status]}>{PAYMENT_STATUS_LABEL[status]}</StatusPill>;
}
