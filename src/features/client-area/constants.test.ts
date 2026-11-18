import { describe, expect, it } from "vitest";

import {
  CLIENT_STATUS_KEYS,
  PAYMENT_STATUS_KEYS,
  REQUEST_STATUS_KEYS,
  clientStatus,
  formatAmount,
  formatDay,
  isClosedStatus,
  isPaymentDue,
  milestoneKindLabel,
  paymentStatus,
  requestStatus,
} from "./constants";

describe("client status labels", () => {
  it("words every key the database mapping can return (private.client_status_key)", () => {
    // Keep in step with supabase/tests/database/117_client_area.test.sql "the client status mapping".
    expect([...CLIENT_STATUS_KEYS].sort()).toEqual(
      [
        "cancelled",
        "completed",
        "in_production",
        "on_hold",
        "planning",
        "finalising",
        "received",
        "revisions_in_progress",
      ].sort(),
    );
    const labels = CLIENT_STATUS_KEYS.map((k) => clientStatus(k).label);
    expect(new Set(labels).size).toBe(labels.length);
    expect(clientStatus("finalising").label).toBe("Finalising");
  });

  it("never echoes an unknown or internal status", () => {
    for (const raw of ["in_review", "approved", "draft", "ready_for_review", "anything"]) {
      expect(clientStatus(raw).label).toBe("In progress");
    }
  });

  it("treats completed and cancelled as closed", () => {
    expect(isClosedStatus("completed")).toBe(true);
    expect(isClosedStatus("cancelled")).toBe(true);
    expect(isClosedStatus("on_hold")).toBe(false);
  });
});

describe("payment status labels", () => {
  it("words every key the database mapping can return", () => {
    expect(PAYMENT_STATUS_KEYS.map((k) => paymentStatus(k).label)).toEqual([
      "Not invoiced yet",
      "Awaiting payment",
      "Received, being confirmed",
      "Paid",
      "Refunded",
    ]);
    expect(paymentStatus("received_unverified").label).toBe("Pending");
  });

  it("only an invoiced, unpaid milestone is due", () => {
    expect(isPaymentDue("awaiting_payment")).toBe(true);
    expect(isPaymentDue("not_invoiced")).toBe(false);
    expect(isPaymentDue("paid")).toBe(false);
  });
});

describe("formatting", () => {
  it("formats amounts and dates", () => {
    expect(formatAmount(10000, "LKR")).toBe("10,000.00 LKR");
    expect(formatDay("2099-01-31")).toBe("31 Jan 2099");
    expect(formatDay(null)).toBeNull();
    expect(milestoneKindLabel("extra_work")).toBe("Additional work");
    expect(milestoneKindLabel("other")).toBe("Payment");
  });
});

describe("request status labels", () => {
  it("words every key the database mapping can return (private.client_request_status_key)", () => {
    // Keep in step with supabase/tests/database/118_client_area_c2a.test.sql "the request status mapping".
    expect([...REQUEST_STATUS_KEYS].sort()).toEqual(
      ["accepted", "in_review", "not_taken_forward", "received"].sort(),
    );
    expect(REQUEST_STATUS_KEYS.map((k) => requestStatus(k).label)).toEqual([
      "Received",
      "In review",
      "Accepted as a project",
      "Not taken forward",
    ]);
  });

  it("never shows a raw inquiry status, even an unknown key", () => {
    for (const raw of ["spam", "declined", "contacted", "new", "converted", ""]) {
      const label = requestStatus(raw).label.toLowerCase();
      expect(label).not.toMatch(/spam|declined|contacted|converted/);
    }
    expect(requestStatus("spam").label).toBe("Received");
  });
});
