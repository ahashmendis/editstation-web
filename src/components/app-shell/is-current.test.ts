import { describe, expect, it } from "vitest";

import { isCurrent } from "./is-current";

const overview = { href: "/admin", exact: true };
const inquiries = { href: "/admin/inquiries" };

describe("isCurrent", () => {
  it("matches an item's own path", () => {
    expect(isCurrent("/admin", overview)).toBe(true);
    expect(isCurrent("/admin/inquiries", inquiries)).toBe(true);
  });

  it("matches sub-pages of non-exact items", () => {
    expect(isCurrent("/admin/inquiries/abc-123", inquiries)).toBe(true);
  });

  it("does not light up an exact overview item on its sub-pages", () => {
    expect(isCurrent("/admin/inquiries", overview)).toBe(false);
    expect(isCurrent("/admin/settings", overview)).toBe(false);
  });

  it("does not match a different path that shares a prefix", () => {
    expect(isCurrent("/admin/inquiriesX", inquiries)).toBe(false);
    expect(isCurrent("/administrator", overview)).toBe(false);
  });
});
