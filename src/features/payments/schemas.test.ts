import { describe, expect, it } from "vitest";

import {
  markPaidSchema,
  parseAdminEarningsFilter,
  parseEditorEarningsFilter,
  paymentNoteSchema,
  reversePaymentSchema,
  setDueDateSchema,
  setPaymentStatusSchema,
} from "./schemas";

const paymentId = "7a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d";

describe("setPaymentStatusSchema", () => {
  it("accepts an advance without a reason", () => {
    const r = setPaymentStatusSchema.safeParse({ paymentId, status: "approved", reason: "" });
    expect(r.success && r.data.reason).toBe(null);
  });

  it("requires a reason only for a hold", () => {
    expect(setPaymentStatusSchema.safeParse({ paymentId, status: "on_hold" }).success).toBe(false);
    expect(
      setPaymentStatusSchema.safeParse({ paymentId, status: "on_hold", reason: "   " }).success,
    ).toBe(false);
    expect(
      setPaymentStatusSchema.safeParse({ paymentId, status: "on_hold", reason: "Bank" }).success,
    ).toBe(true);
    expect(
      setPaymentStatusSchema.safeParse({ paymentId, status: "on_hold", reason: "x".repeat(501) })
        .success,
    ).toBe(false);
  });

  it("refuses paid, not_due and unknown statuses", () => {
    for (const status of ["paid", "not_due", "bogus", "PAID"]) {
      expect(setPaymentStatusSchema.safeParse({ paymentId, status }).success).toBe(false);
    }
  });

  it("refuses a bad id", () => {
    expect(setPaymentStatusSchema.safeParse({ paymentId: "x", status: "approved" }).success).toBe(
      false,
    );
  });
});

describe("markPaidSchema", () => {
  it("trims the reference and needs a date", () => {
    const r = markPaidSchema.safeParse({
      paymentId,
      reference: "  R1 ",
      transferDate: "2026-11-14",
    });
    expect(r.success && r.data.reference).toBe("R1");
    expect(
      markPaidSchema.safeParse({ paymentId, reference: "", transferDate: "2026-11-14" }).success,
    ).toBe(false);
    expect(
      markPaidSchema.safeParse({
        paymentId,
        reference: "x".repeat(121),
        transferDate: "2026-11-14",
      }).success,
    ).toBe(false);
    expect(markPaidSchema.safeParse({ paymentId, reference: "R", transferDate: "" }).success).toBe(
      false,
    );
  });
});

describe("setDueDateSchema", () => {
  it("turns empty into null and checks the format", () => {
    const r = setDueDateSchema.safeParse({ paymentId, dueDate: "" });
    expect(r.success && r.data.dueDate).toBe(null);
    expect(setDueDateSchema.safeParse({ paymentId, dueDate: "2026-12-01" }).success).toBe(true);
    expect(setDueDateSchema.safeParse({ paymentId, dueDate: "tomorrow" }).success).toBe(false);
  });
});

describe("reversePaymentSchema", () => {
  it("needs a reason and reads the checkbox", () => {
    const on = reversePaymentSchema.safeParse({ paymentId, reason: "Mistake", reopen: "on" });
    expect(on.success && on.data.reopen).toBe(true);
    const off = reversePaymentSchema.safeParse({ paymentId, reason: "Mistake" });
    expect(off.success && off.data.reopen).toBe(false);
    expect(reversePaymentSchema.safeParse({ paymentId, reason: " " }).success).toBe(false);
  });
});

describe("paymentNoteSchema", () => {
  it("bounds the note", () => {
    expect(paymentNoteSchema.safeParse({ paymentId, note: "Called" }).success).toBe(true);
    expect(paymentNoteSchema.safeParse({ paymentId, note: "" }).success).toBe(false);
    expect(paymentNoteSchema.safeParse({ paymentId, note: "n".repeat(4001) }).success).toBe(false);
  });
});

describe("earnings filters", () => {
  it("keeps valid values and drops invalid ones", () => {
    expect(
      parseAdminEarningsFilter({ status: "paid", editor: paymentId, currency: "LKR" }),
    ).toEqual({ status: "paid", editor: paymentId, currency: "LKR" });
    expect(parseAdminEarningsFilter({ status: "nope", editor: "x", currency: "lkr" })).toEqual({
      status: null,
      editor: null,
      currency: null,
    });
    expect(parseEditorEarningsFilter({ status: ["on_hold", "paid"] })).toEqual({
      status: "on_hold",
    });
    expect(parseEditorEarningsFilter({})).toEqual({ status: null });
  });
});
