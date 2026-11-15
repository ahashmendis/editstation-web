import { describe, expect, it } from "vitest";

import { notificationHref, unreadBadge, type NotificationKind } from "./constants";

const id = "6f3c2d1e-0b4a-4c6d-8e9f-1a2b3c4d5e6f";

describe("notificationHref", () => {
  it.each<[NotificationKind, string]>([
    ["inquiry_new", `/admin/inquiries/${id}`],
    ["application_new", `/admin/applications/${id}`],
    ["applicant_response", `/admin/applications/${id}`],
    ["counteroffer", `/admin/projects/${id}`],
    ["submission", `/admin/projects/${id}`],
    ["asset_inaccessible", `/admin/projects/${id}`],
    ["application_decision", "/apply"],
    ["application_request", "/apply"],
    ["invitation", `/editor/projects/${id}`],
    ["assignment_confirmed", `/editor/projects/${id}`],
    ["revision_requested", `/editor/projects/${id}`],
    ["payment_paid", "/editor/earnings"],
  ])("%s links to %s", (kind, href) => {
    expect(notificationHref({ kind, entity_id: id })).toBe(href);
  });
});

describe("unreadBadge", () => {
  it("hides the badge when nothing is unread", () => {
    expect(unreadBadge(0)).toBeNull();
  });
  it("shows small counts and caps large ones", () => {
    expect(unreadBadge(7)).toBe("7");
    expect(unreadBadge(150)).toBe("99+");
  });
});
