import { describe, expect, it } from "vitest";

import { activityLabel } from "./activity-labels";

describe("activityLabel", () => {
  it("maps known codes", () => {
    expect(activityLabel("inquiry.submitted")).toBe("Submitted");
    expect(activityLabel("inquiry.converted")).toBe("Converted to project");
    expect(activityLabel("project.cancelled")).toBe("Cancelled");
    expect(activityLabel("client.merged")).toBe("Client merged");
    expect(activityLabel("application.approved")).toBe("Application approved");
  });

  it("falls back to Updated", () => {
    expect(activityLabel("something.else")).toBe("Updated");
  });
});
