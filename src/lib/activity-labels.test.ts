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

  it("maps Phase 5 and 6 codes", () => {
    expect(activityLabel("assignment.confirmed")).toBe("Editor confirmed");
    expect(activityLabel("project_access.granted")).toBe("Editor invited");
    expect(activityLabel("asset_grant.revoked")).toBe("Folder share removed");
    expect(activityLabel("project.note_added")).toBe("Note added");
  });

  it("maps Phase 9 payment codes", () => {
    expect(activityLabel("payment.created")).toBe("Payment record created");
    expect(activityLabel("payment.hold_released")).toBe("Hold released");
    expect(activityLabel("payment.reversed")).toBe("Payment reversed");
    expect(activityLabel("payment_note.added")).toBe("Note added");
  });

  it("falls back to Updated", () => {
    expect(activityLabel("something.else")).toBe("Updated");
  });
});
