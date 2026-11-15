import { describe, expect, it } from "vitest";

import {
  PAYMENT_STATUSES,
  PAYMENT_STATUS_LABEL,
  PAYMENT_STATUS_TONE,
  HOLD_LABEL,
  canSplitForDispute,
  maxDisputedAmount,
  nextAdminActions,
} from "./constants";

describe("payment constants", () => {
  it("labels and tones every status", () => {
    for (const s of PAYMENT_STATUSES) {
      expect(PAYMENT_STATUS_LABEL[s]).toBeTruthy();
      expect(PAYMENT_STATUS_TONE[s]).toBeTruthy();
    }
  });

  it("offers actions per status", () => {
    expect(nextAdminActions("not_due", "assignment", false)).toEqual(["hold", "set_due_date"]);
    expect(nextAdminActions("approved", "assignment", false)).toContain("mark_paid");
    expect(nextAdminActions("on_hold", "assignment", false)).toEqual(["release", "set_due_date"]);
    expect(nextAdminActions("paid", "assignment", false)).toEqual(["reverse"]);
    expect(nextAdminActions("paid", "assignment", true)).toEqual([]);
    expect(nextAdminActions("paid", "reversal", false)).toEqual([]);
  });

  it("never shows the editor a free-text reason", () => {
    expect(HOLD_LABEL.waiting_for_client_payment).toBe("Waiting for client payment");
    expect(HOLD_LABEL.under_review).toBe("Under review");
  });

  it("caps the disputed part one cent below the payment", () => {
    expect(maxDisputedAmount(5000)).toBe("4999.99");
    expect(maxDisputedAmount(33.01)).toBe("33.00");
  });

  it("offers a dispute split only for an unsplit, unpaid milestone that is not on hold", () => {
    const base = {
      kind: "assignment" as const,
      status: "pending_approval" as const,
      splitFromPaymentId: null,
      amountBeforeSplit: null,
    };
    expect(canSplitForDispute(base)).toBe(true);
    expect(canSplitForDispute({ ...base, status: "paid" })).toBe(false);
    expect(canSplitForDispute({ ...base, status: "on_hold" })).toBe(false);
    expect(canSplitForDispute({ ...base, kind: "reversal" })).toBe(false);
    expect(canSplitForDispute({ ...base, splitFromPaymentId: "x" })).toBe(false);
    expect(canSplitForDispute({ ...base, amountBeforeSplit: 10 })).toBe(false);
  });
});
