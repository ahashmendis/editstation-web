import { describe, expect, it } from "vitest";

import { barsFor, formatAmount, formatHours, formatRate } from "./constants";

describe("formatRate", () => {
  it("shows a percentage or a dash", () => {
    expect(formatRate(0.873)).toBe("87%");
    expect(formatRate(1)).toBe("100%");
    expect(formatRate(null)).toBe("—");
  });
});

describe("formatHours", () => {
  it("uses hours under two days and days after", () => {
    expect(formatHours(18.4)).toBe("18 h");
    expect(formatHours(84)).toBe("3.5 days");
    expect(formatHours(null)).toBe("—");
  });
});

describe("formatAmount", () => {
  it("keeps the currency with the amount", () => {
    expect(formatAmount(12500, "LKR")).toBe("LKR 12,500");
  });
});

describe("barsFor", () => {
  it("keeps the order, labels and zero-fills missing statuses", () => {
    expect(barsFor({ open: 2 }, ["draft", "open"], { draft: "Draft", open: "Open" })).toEqual([
      { key: "draft", label: "Draft", value: 0 },
      { key: "open", label: "Open", value: 2 },
    ]);
  });
});
