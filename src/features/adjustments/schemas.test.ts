import { describe, expect, it } from "vitest";

import {
  adjustmentKeptValues,
  createQuoteSchema,
  offerAdjustmentSchema,
  quoteAnswerSchema,
  settleSchema,
} from "./schemas";

const projectId = "6f3c2d1e-0b4a-4c6d-8e9f-1a2b3c4d5e6f";
const otherId = "6f3c2d1e-0b4a-4c6d-8e9f-1a2b3c4d5e60";

describe("offerAdjustmentSchema", () => {
  const base = { projectId, assignmentId: otherId, kind: "extra_round", revisionId: otherId };
  it("accepts an amount in whole cents", () => {
    const r = offerAdjustmentSchema.safeParse({ ...base, amount: "2500.50", note: "" });
    expect(r.success && r.data.amount).toBe(2500.5);
    expect(r.success && r.data.note).toBeNull();
  });
  it("refuses zero, fractions of a cent and a missing target", () => {
    expect(offerAdjustmentSchema.safeParse({ ...base, amount: "0" }).success).toBe(false);
    expect(offerAdjustmentSchema.safeParse({ ...base, amount: "1.005" }).success).toBe(false);
    expect(
      offerAdjustmentSchema.safeParse({ ...base, kind: "scope_change", quoteId: "", amount: "5" })
        .success,
    ).toBe(false);
  });
});

describe("scope quotes", () => {
  it("upper-cases the currency", () => {
    const r = createQuoteSchema.safeParse({
      projectId,
      revisionId: otherId,
      description: "Second ending",
      amount: "5000",
      currency: "lkr",
    });
    expect(r.success && r.data.currency).toBe("LKR");
  });
  it("needs the admin's due date for an acceptance (call 5: no default)", () => {
    expect(
      quoteAnswerSchema.safeParse({ projectId, quoteId: otherId, accepted: "yes" }).success,
    ).toBe(false);
    expect(
      quoteAnswerSchema.safeParse({ projectId, quoteId: otherId, accepted: "no" }).success,
    ).toBe(true);
  });
});

describe("settleSchema", () => {
  it("uses the schedule when no amount is given", () => {
    const r = settleSchema.safeParse({ projectId, adjustedEarned: "", reason: "" });
    expect(r.success && r.data.adjustedEarned).toBeNull();
  });
  it("needs a reason for a changed amount, and allows 0", () => {
    expect(settleSchema.safeParse({ projectId, adjustedEarned: "0" }).success).toBe(false);
    const r = settleSchema.safeParse({ projectId, adjustedEarned: "0", reason: "No work done" });
    expect(r.success && r.data.adjustedEarned).toBe(0);
  });
});

describe("adjustmentKeptValues", () => {
  it("keeps typed values for a failed submit", () => {
    const fd = new FormData();
    fd.set("amount", "12");
    fd.set("projectId", projectId);
    expect(adjustmentKeptValues(fd)).toEqual({ amount: "12" });
  });
});
