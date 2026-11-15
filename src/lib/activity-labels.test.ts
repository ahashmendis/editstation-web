import { describe, expect, it } from "vitest";

import {
  activityActions,
  activityEntityHref,
  activityLabel,
  entityTypeLabel,
  isKnownActivityAction,
} from "./activity-labels";

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

  it("maps Phase 12D editor pay codes", () => {
    expect(activityLabel("payment.dispute_split")).toBe(
      "Split for a dispute (disputed part on hold)",
    );
    expect(activityLabel("payment.late_balance_payable")).toBe(
      "Payable by late-balance protection",
    );
  });

  it("maps Phase 12A terms codes", () => {
    expect(activityLabel("project_terms.draft_saved")).toBe("Terms draft saved");
    expect(activityLabel("project_terms.agreed")).toBe("Terms agreed");
  });

  it("maps Phase 12B asset codes", () => {
    expect(activityLabel("asset.reported_inaccessible")).toBe("Asset reported inaccessible");
    expect(activityLabel("asset.editor_can_open")).toBe("Editor can open asset");
    expect(activityLabel("asset.verified")).toBe("Asset access verified");
    expect(activityLabel("asset_report.resolved")).toBe("Asset report resolved");
    expect(activityLabel("asset_grant.removal_requested")).toBe(
      "Access removal requested from client",
    );
    expect(activityLabel("asset_grant.removal_confirmed")).toBe("Access removal confirmed");
  });

  it("maps Phase 12C billing codes", () => {
    expect(activityLabel("project.auto_held")).toBe(
      "Put on hold automatically (client deposit overdue)",
    );
    expect(activityLabel("client_milestones.created")).toBe("Client milestones created");
    expect(activityLabel("client_milestone.invoice_issued")).toBe("Client invoice issued");
    expect(activityLabel("client_milestone.payment_recorded")).toBe("Client payment recorded");
    expect(activityLabel("client_milestone.verified")).toBe("Client payment verified");
    expect(activityLabel("client_milestone.verification_corrected")).toBe(
      "Client payment verification corrected",
    );
    expect(activityLabel("client_milestone.due_extended")).toBe("Client deposit due date extended");
    expect(activityLabel("timed_rules.run")).toBe("Timed rules run");
    expect(activityLabel("app_settings.changed")).toBe("Setting changed");
  });

  it("falls back to Updated", () => {
    expect(activityLabel("something.else")).toBe("Updated");
  });
});

describe("activity filter helpers (Phase 10)", () => {
  it("lists every code once, sorted by label", () => {
    const actions = activityActions();
    expect(new Set(actions.map((a) => a.code)).size).toBe(actions.length);
    const labels = actions.map((a) => a.label);
    expect([...labels].sort((a, b) => a.localeCompare(b))).toEqual(labels);
  });

  it("recognises only known codes", () => {
    expect(isKnownActivityAction("payment.paid")).toBe(true);
    expect(isKnownActivityAction("constructor")).toBe(false);
    expect(isKnownActivityAction("x'; drop")).toBe(false);
  });

  it("labels entity types in plain words", () => {
    expect(entityTypeLabel("client_inquiry")).toBe("Client inquiry");
    expect(entityTypeLabel("revision_request")).toBe("Change request");
    expect(entityTypeLabel("new_thing")).toBe("new thing");
  });
});

describe("activityEntityHref", () => {
  const id = "6f3c2d1e-0b4a-4c6d-8e9f-1a2b3c4d5e6f";
  it("links entities that have an admin page", () => {
    expect(activityEntityHref("project", id)).toBe(`/admin/projects/${id}`);
    expect(activityEntityHref("client_inquiry", id)).toBe(`/admin/inquiries/${id}`);
    expect(activityEntityHref("payment", id)).toBe(`/admin/earnings/${id}`);
  });
  it("returns null for other entities or non-uuid ids", () => {
    expect(activityEntityHref("assignment", id)).toBeNull();
    expect(activityEntityHref("project", "../x")).toBeNull();
  });
});
