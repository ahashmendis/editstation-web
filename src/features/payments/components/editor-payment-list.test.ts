import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import type { EditorPaymentRow } from "../queries";
import { EditorPaymentList } from "./editor-payment-list";

const base: EditorPaymentRow = {
  id: "6f3c2d1e-0b4a-4c6d-8e9f-1a2b3c4d5e61",
  projectId: "6f3c2d1e-0b4a-4c6d-8e9f-1a2b3c4d5e62",
  projectTitle: "Wedding film",
  kind: "assignment",
  status: "not_due",
  amount: 5000,
  currency: "LKR",
  dueDate: null,
  markedPaidAt: null,
  milestoneSeq: 1 as number | null,
  lineKind: "milestone" as const,
  holdLabel: null,
  waitingOnClient: false,
  splitFromPaymentId: null,
  reversesPaymentId: null,
  transferDate: null,
  transactionReference: null,
  createdAt: "2026-11-15T00:00:00Z",
};

const render = (rows: EditorPaymentRow[]) =>
  renderToStaticMarkup(createElement(EditorPaymentList, { rows }));

describe("EditorPaymentList", () => {
  it("shows the milestone and the fixed waiting label", () => {
    const html = render([
      { ...base, waitingOnClient: true, holdLabel: "waiting_for_client_payment" },
    ]);
    expect(html).toContain("Milestone 1");
    expect(html).toContain("Waiting for client payment");
  });

  it("shows only fixed labels for holds and reversals, never a reason", () => {
    // Rows carry no reason fields at all; a reason-like title elsewhere must not leak into labels.
    const html = render([
      { ...base, id: "a", status: "on_hold", holdLabel: "under_review", milestoneSeq: 2 },
      {
        ...base,
        id: "b",
        kind: "reversal",
        status: "paid",
        amount: -5000,
        reversesPaymentId: base.id,
      },
    ]);
    expect(html).toContain("Under review");
    expect(html).toContain("Reversed");
    expect(html).not.toMatch(/reason|client disputes|balance unpaid|late_balance/i);
    expect(Object.keys(base).some((k) => /reason/i.test(k))).toBe(false);
  });

  it("labels extra pay, cancelled milestones and the settlement with fixed wording", () => {
    const html = render([
      { ...base, id: "c", lineKind: "extra_round", milestoneSeq: null, status: "pending_approval" },
      { ...base, id: "d", status: "cancelled" },
      { ...base, id: "e", lineKind: "cancellation_settlement", milestoneSeq: null },
    ]);
    expect(html).toContain("Extra round pay");
    expect(html).toContain("Cancelled");
    expect(html).toContain("Cancellation settlement");
    expect(html).not.toMatch(/refund|client charge|client price/i);
  });
});
