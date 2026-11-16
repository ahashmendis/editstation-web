import { describe, expect, it } from "vitest";

import {
  closesAtFromDate,
  dateFromClosesAt,
  INTEREST_STATUS_LABEL,
  INTEREST_STATUS_TONE,
  OPPORTUNITY_STATUS_LABEL,
} from "./constants";
import {
  isRealDate,
  publishOpportunitySchema,
  registerInterestSchema,
  selectEditorSchema,
  summaryArgs,
  updateOpportunitySchema,
} from "./schemas";

const projectId = "6f3c2d1e-0b4a-4c6d-8e9f-1a2b3c4d5e6f";
const otherId = "7a3c2d1e-0b4a-4c6d-8e9f-1a2b3c4d5e6f";

const base = { projectId, title: "Promo edit", deliverablesSummary: "One 60 s cut" };

describe("publishOpportunitySchema", () => {
  it("accepts the minimum and hides pay by default", () => {
    const v = publishOpportunitySchema.parse(base);
    expect(v.showPay).toBe(false);
    expect(summaryArgs(v)).toEqual({
      p_title: "Promo edit",
      p_deliverables_summary: "One 60 s cut",
    });
  });

  it("requires a title and a deliverables summary", () => {
    const r = publishOpportunitySchema.safeParse({
      projectId,
      title: " ",
      deliverablesSummary: "",
    });
    expect(r.success).toBe(false);
    const fields = r.success ? [] : r.error.issues.map((i) => i.path[0]);
    expect(fields).toEqual(expect.arrayContaining(["title", "deliverablesSummary"]));
  });

  it("needs an amount when pay is shown", () => {
    const r = publishOpportunitySchema.safeParse({ ...base, showPay: "on" });
    expect(r.success).toBe(false);
    expect(r.success ? null : r.error.issues[0].path).toEqual(["payAmount"]);
  });

  it("sends the shown pay only when ticked", () => {
    const shown = publishOpportunitySchema.parse({
      ...base,
      showPay: "on",
      payAmount: "25000",
      payCurrency: "lkr",
    });
    expect(summaryArgs(shown)).toMatchObject({
      p_shown_pay_amount: 25000,
      p_shown_pay_currency: "LKR",
    });
    const hidden = publishOpportunitySchema.parse({ ...base, payAmount: "25000" });
    expect(summaryArgs(hidden)).not.toHaveProperty("p_shown_pay_amount");
  });

  it("turns the closing day into the end of that day in Sri Lanka time", () => {
    const v = publishOpportunitySchema.parse({
      ...base,
      closesOn: "2026-12-01",
      deadline: "2026-12-20",
    });
    expect(summaryArgs(v)).toMatchObject({
      p_closes_at: "2026-12-01T23:59:59+05:30",
      p_deadline: "2026-12-20",
    });
  });

  it("rejects a bad amount or date", () => {
    expect(
      publishOpportunitySchema.safeParse({ ...base, showPay: "on", payAmount: "-1" }).success,
    ).toBe(false);
    expect(publishOpportunitySchema.safeParse({ ...base, deadline: "soon" }).success).toBe(false);
  });

  it("refuses impossible calendar days", () => {
    expect(isRealDate("2026-02-28")).toBe(true);
    expect(isRealDate("2028-02-29")).toBe(true);
    expect(isRealDate("2026-02-31")).toBe(false);
    expect(isRealDate("2026-13-01")).toBe(false);
    expect(publishOpportunitySchema.safeParse({ ...base, deadline: "2026-02-31" }).success).toBe(
      false,
    );
    expect(publishOpportunitySchema.safeParse({ ...base, closesOn: "2026-04-31" }).success).toBe(
      false,
    );
  });

  it("update also needs the opportunity id", () => {
    expect(updateOpportunitySchema.safeParse(base).success).toBe(false);
    expect(updateOpportunitySchema.safeParse({ ...base, opportunityId: otherId }).success).toBe(
      true,
    );
  });
});

describe("registerInterestSchema", () => {
  it("allows interest without a rate or note", () => {
    expect(registerInterestSchema.parse({ opportunityId: otherId })).toEqual({
      opportunityId: otherId,
      proposedAmount: null,
      proposedCurrency: null,
      note: null,
    });
  });

  it("checks the rate and keeps the note short", () => {
    expect(
      registerInterestSchema.safeParse({ opportunityId: otherId, proposedAmount: "12.345" })
        .success,
    ).toBe(false);
    expect(
      registerInterestSchema.safeParse({ opportunityId: otherId, note: "x".repeat(501) }).success,
    ).toBe(false);
    expect(
      registerInterestSchema.parse({ opportunityId: otherId, proposedAmount: "15000.50" })
        .proposedAmount,
    ).toBe(15000.5);
  });
});

describe("selectEditorSchema", () => {
  it("needs the admin's offer amount", () => {
    const r = selectEditorSchema.safeParse({ projectId, interestId: otherId, amount: "" });
    expect(r.success).toBe(false);
    expect(
      selectEditorSchema.parse({ projectId, interestId: otherId, amount: "9000", currency: "usd" }),
    ).toMatchObject({ amount: 9000, currency: "USD", message: null });
  });
});

describe("labels", () => {
  it("names every interest status in words (never colour alone)", () => {
    expect(INTEREST_STATUS_LABEL).toEqual({
      interested: "Interested",
      withdrawn: "Withdrawn",
      selected: "Selected",
      not_selected: "Not selected",
    });
    expect(Object.keys(INTEREST_STATUS_TONE).sort()).toEqual(
      Object.keys(INTEREST_STATUS_LABEL).sort(),
    );
    expect(OPPORTUNITY_STATUS_LABEL.filled).toBe("Editor chosen");
  });

  it("round-trips the closing day", () => {
    expect(dateFromClosesAt(closesAtFromDate("2026-12-01"))).toBe("2026-12-01");
    expect(dateFromClosesAt(null)).toBe("");
  });
});
