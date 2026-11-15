import { describe, expect, it } from "vitest";

import { businessToday, isOverdue, milestoneActions, type MilestoneRow } from "./constants";
import {
  billingKeptValues,
  correctPaymentSchema,
  createMilestonesSchema,
  extendDueSchema,
  recordPaymentSchema,
  timezoneSchema,
} from "./schemas";

const projectId = "6f3c2d1e-0b4a-4c6d-8e9f-1a2b3c4d5e6f";
const milestoneId = "7a3c2d1e-0b4a-4c6d-8e9f-1a2b3c4d5e6f";

const base: MilestoneRow = {
  id: milestoneId,
  seq: 1,
  kind: "deposit",
  share_percent: 50,
  amount: 5000,
  currency: "LKR",
  invoice_issued_at: null,
  due_date: null,
  received_at: null,
  transfer_reference: null,
  verification_status: "expected",
  verified_at: null,
  auto_held_at: null,
  due_change_reason: null,
  correction_reason: null,
};

describe("client milestone schemas", () => {
  it("parses shares that add up to 100, including all upfront", () => {
    expect(createMilestonesSchema.parse({ projectId, shares: "50, 50" }).shares).toEqual([50, 50]);
    expect(createMilestonesSchema.parse({ projectId, shares: "100" }).shares).toEqual([100]);
  });

  it("refuses shares that do not add up or are not whole", () => {
    expect(createMilestonesSchema.safeParse({ projectId, shares: "60, 30" }).success).toBe(false);
    expect(createMilestonesSchema.safeParse({ projectId, shares: "0, 100" }).success).toBe(false);
    expect(createMilestonesSchema.safeParse({ projectId, shares: "50.5, 49.5" }).success).toBe(
      false,
    );
  });

  it("requires a transfer reference; the date is optional but must be valid", () => {
    expect(
      recordPaymentSchema.safeParse({ projectId, milestoneId, transferReference: "  " }).success,
    ).toBe(false);
    expect(
      recordPaymentSchema.parse({
        projectId,
        milestoneId,
        transferReference: " BANK-1 ",
        receivedOn: "",
      }),
    ).toMatchObject({ transferReference: "BANK-1", receivedOn: null });
    expect(
      recordPaymentSchema.safeParse({
        projectId,
        milestoneId,
        transferReference: "B",
        receivedOn: "15/11/2026",
      }).success,
    ).toBe(false);
  });

  it("requires a date and reason to extend, and a reason to correct", () => {
    expect(
      extendDueSchema.safeParse({ projectId, milestoneId, dueDate: "2026-12-01", reason: "" })
        .success,
    ).toBe(false);
    expect(
      extendDueSchema.safeParse({ projectId, milestoneId, dueDate: "2026-12-01", reason: "Asked" })
        .success,
    ).toBe(true);
    expect(correctPaymentSchema.safeParse({ projectId, milestoneId, reason: " " }).success).toBe(
      false,
    );
  });

  it("accepts timezone names only", () => {
    expect(timezoneSchema.safeParse({ timezone: "Asia/Colombo" }).success).toBe(true);
    expect(timezoneSchema.safeParse({ timezone: "Asia/Colombo; drop" }).success).toBe(false);
  });

  it("keeps typed values for a failed submit", () => {
    const fd = new FormData();
    fd.set("transferReference", "BANK-9");
    fd.set("projectId", projectId);
    expect(billingKeptValues(fd)).toEqual({ transferReference: "BANK-9" });
  });
});

describe("client milestone helpers", () => {
  it("offers actions by state", () => {
    expect(milestoneActions(base, false)).toMatchObject({
      issue: true,
      record: true,
      verify: false,
    });
    const received = { ...base, verification_status: "received_unverified" as const };
    expect(milestoneActions(received, false)).toMatchObject({ verify: true });
    const verified = { ...base, verification_status: "verified" as const };
    expect(milestoneActions(verified, false)).toMatchObject({ record: false, correct: true });
    expect(milestoneActions(verified, true).correct).toBe(false);
    const issued = { ...base, invoice_issued_at: "2026-11-15T00:00:00Z", due_date: "2026-11-29" };
    expect(milestoneActions(issued, false)).toMatchObject({ issue: false, extend: true });
    expect(milestoneActions(issued, false, true)).toMatchObject({ extend: false });
  });

  it("is overdue only after the due date and while unverified", () => {
    const issued = { ...base, due_date: "2026-11-29" };
    expect(isOverdue(issued, "2026-11-29")).toBe(false);
    expect(isOverdue(issued, "2026-11-30")).toBe(true);
    expect(isOverdue({ ...issued, verification_status: "verified" }, "2026-12-30")).toBe(false);
  });

  it("uses the business timezone for today", () => {
    const at = new Date("2026-11-15T20:00:00Z");
    expect(businessToday("Asia/Colombo", at)).toBe("2026-11-16");
    expect(businessToday("UTC", at)).toBe("2026-11-15");
    expect(businessToday("Not/AZone", at)).toBe("2026-11-16");
  });
});
