import { describe, expect, it } from "vitest";

import { editorAccessWarning, editorLabel, formatMoney, summariseEditorLabels } from "./constants";

describe("editorAccessWarning", () => {
  it("is null for an active editor or one without a live assignment", () => {
    expect(editorAccessWarning("active", "confirmed")).toBeNull();
    expect(editorAccessWarning("suspended", null)).toBeNull();
    expect(editorAccessWarning("suspended", "declined")).toBeNull();
  });

  it("flags a suspended or revoked editor holding a live or confirmed assignment", () => {
    expect(editorAccessWarning("suspended", "confirmed")).toBe("Suspended");
    expect(editorAccessWarning("revoked", "offered")).toBe("Access revoked");
    expect(editorAccessWarning("none", "accepted")).toBe("Access not active");
    expect(editorAccessWarning(undefined, "accepted")).toBe("Access not active");
  });
});

describe("editorLabel", () => {
  it("shows Invited for access with no assignment", () => {
    expect(editorLabel({ hasLiveAccess: true, assignments: [] }).label).toBe("Invited");
  });

  it("a live assignment wins over older closed ones", () => {
    const l = editorLabel({
      hasLiveAccess: true,
      assignments: [{ status: "counteroffer_pending" }, { status: "declined" }],
    });
    expect(l.label).toBe("Counteroffer");
    expect(l.assignmentStatus).toBe("counteroffer_pending");
  });

  it("falls back to the newest closed state, then to access removed", () => {
    expect(
      editorLabel({ hasLiveAccess: false, assignments: [{ status: "not_selected" }] }).label,
    ).toBe("Not selected");
    expect(editorLabel({ hasLiveAccess: false, assignments: [] }).label).toBe("Access removed");
  });

  it("summarises the project in a fixed order", () => {
    const labels = [
      editorLabel({ hasLiveAccess: true, assignments: [] }),
      editorLabel({ hasLiveAccess: true, assignments: [] }),
      editorLabel({ hasLiveAccess: true, assignments: [{ status: "counteroffer_pending" }] }),
      editorLabel({ hasLiveAccess: false, assignments: [{ status: "declined" }] }),
    ];
    expect(summariseEditorLabels(labels)).toBe("2 invited · 1 counteroffer");
  });
});

describe("formatMoney", () => {
  it("formats whole and fractional amounts", () => {
    expect(formatMoney(15000, "LKR")).toBe("15,000 LKR");
    expect(formatMoney("1500.5", "USD")).toBe("1,500.50 USD");
    expect(formatMoney(null, null)).toBe("—");
  });
});
