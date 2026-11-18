import { describe, expect, it } from "vitest";

import { isCurrent, isMostSpecificCurrent } from "./is-current";

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

describe("isMostSpecificCurrent", () => {
  const items = [
    { href: "/client", exact: true },
    { href: "/client/projects" },
    { href: "/client/projects/new" },
  ];

  it("marks only the most specific matching item", () => {
    expect(isMostSpecificCurrent("/client/projects/new", items[2], items)).toBe(true);
    expect(isMostSpecificCurrent("/client/projects/new", items[1], items)).toBe(false);
  });

  it("keeps parent matching for other sub-pages", () => {
    expect(isMostSpecificCurrent("/client/projects/abc-123", items[1], items)).toBe(true);
    expect(isMostSpecificCurrent("/client/projects", items[1], items)).toBe(true);
    expect(isMostSpecificCurrent("/client", items[0], items)).toBe(true);
  });
});
