import { describe, expect, it } from "vitest";

import {
  PAYMENT_STATUSES,
  PAYMENT_STATUS_LABEL,
  PAYMENT_STATUS_TONE,
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
    expect(nextAdminActions("not_due", "assignment", false)).toEqual([
      "to_pending_approval",
      "hold",
      "set_due_date",
    ]);
    expect(nextAdminActions("approved", "assignment", false)).toContain("mark_paid");
    expect(nextAdminActions("on_hold", "assignment", false)).toEqual(["release", "set_due_date"]);
    expect(nextAdminActions("paid", "assignment", false)).toEqual(["reverse"]);
    expect(nextAdminActions("paid", "assignment", true)).toEqual([]);
    expect(nextAdminActions("paid", "reversal", false)).toEqual([]);
  });
});
