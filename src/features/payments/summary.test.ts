import { describe, expect, it } from "vitest";

import {
  colomboDay,
  projectMargin,
  summariseByCurrency,
  summariseByEditor,
  type PaymentLike,
} from "./summary";

const row = (over: Partial<PaymentLike>): PaymentLike => ({
  status: "not_due",
  kind: "assignment",
  amount: 1000,
  currency: "LKR",
  markedPaidAt: null,
  dueDate: null,
  ...over,
});

const NOW = new Date("2026-12-10T06:00:00Z");

describe("summariseByCurrency", () => {
  it("never mixes currencies", () => {
    const s = summariseByCurrency([row({}), row({ currency: "USD", amount: 50 })], NOW);
    expect(s.LKR.committed).toBe(1000);
    expect(s.USD.committed).toBe(50);
  });

  it("splits committed, awaiting transfer and on hold", () => {
    const s = summariseByCurrency(
      [
        row({ status: "not_due" }),
        row({ status: "pending_approval" }),
        row({ status: "approved" }),
        row({ status: "processing" }),
        row({ status: "on_hold", amount: 700 }),
      ],
      NOW,
    );
    expect(s.LKR.committed).toBe(4000);
    expect(s.LKR.awaitingTransfer).toBe(2000);
    expect(s.LKR.onHold).toBe(700);
  });

  it("nets reversals in paid totals", () => {
    const paidAt = "2026-12-05T10:00:00Z";
    const s = summariseByCurrency(
      [
        row({ status: "paid", markedPaidAt: paidAt }),
        row({ status: "paid", kind: "reversal", amount: -1000, markedPaidAt: paidAt }),
        row({ status: "paid", amount: 500, markedPaidAt: "2026-10-01T10:00:00Z" }),
      ],
      NOW,
    );
    expect(s.LKR.paidThisMonth).toBe(0);
    expect(s.LKR.paidAllTime).toBe(500);
  });

  it("uses the Asia/Colombo month boundary", () => {
    expect(colomboDay("2026-11-30T19:00:00Z")).toBe("2026-12-01");
    const s = summariseByCurrency(
      [row({ status: "paid", markedPaidAt: "2026-11-30T19:00:00Z" })],
      NOW,
    );
    expect(s.LKR.paidThisMonth).toBe(1000);
    const nov = summariseByCurrency(
      [row({ status: "paid", markedPaidAt: "2026-11-30T19:00:00Z" })],
      new Date("2026-11-30T12:00:00Z"),
    );
    expect(nov.LKR.paidThisMonth).toBe(0);
  });

  it("counts overdue only for unpaid rows due before Colombo today", () => {
    const s = summariseByCurrency(
      [
        row({ dueDate: "2026-12-09" }),
        row({ dueDate: "2026-12-10" }),
        row({ status: "paid", dueDate: "2026-12-01", markedPaidAt: "2026-12-01T00:00:00Z" }),
        row({ status: "on_hold", dueDate: "2026-12-01" }),
      ],
      NOW,
    );
    expect(s.LKR.overdue).toBe(1);
  });

  it("sums in cents", () => {
    const s = summariseByCurrency([row({ amount: 0.1 }), row({ amount: 0.2 })], NOW);
    expect(s.LKR.committed).toBe(0.3);
  });
});

describe("summariseByEditor", () => {
  it("groups by editor and currency, largest committed first", () => {
    const s = summariseByEditor(
      [
        row({ editorId: "a", amount: 100 }),
        row({ editorId: "b", amount: 900 }),
        row({ editorId: "a", amount: 50, currency: "USD" }),
      ],
      NOW,
    );
    expect(s.map((e) => `${e.editorId}/${e.currency}/${e.committed}`)).toEqual([
      "b/LKR/900",
      "a/LKR/100",
      "a/USD/50",
    ]);
  });
});

describe("projectMargin", () => {
  it("needs a client price", () => {
    expect(projectMargin({ clientPrice: null, clientCurrency: "LKR", rows: [row({})] })).toEqual({
      kind: "no_price",
    });
  });

  it("refuses mixed currencies", () => {
    expect(
      projectMargin({ clientPrice: 5000, clientCurrency: "LKR", rows: [row({ currency: "USD" })] }),
    ).toEqual({ kind: "mixed_currency" });
  });

  it("subtracts the net editor cost and flags on-hold pay", () => {
    expect(
      projectMargin({
        clientPrice: 5000,
        clientCurrency: "LKR",
        rows: [
          row({ status: "paid", amount: 1000 }),
          row({ status: "paid", kind: "reversal", amount: -1000 }),
          row({ status: "on_hold", amount: 1000 }),
        ],
      }),
    ).toEqual({ kind: "margin", amount: 4000, currency: "LKR", includesOnHold: true });
  });

  it("is the full price with no payments", () => {
    expect(projectMargin({ clientPrice: 5000.5, clientCurrency: "LKR", rows: [] })).toEqual({
      kind: "margin",
      amount: 5000.5,
      currency: "LKR",
      includesOnHold: false,
    });
  });
});
