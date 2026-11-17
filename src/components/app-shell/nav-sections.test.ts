import { describe, expect, it } from "vitest";

import { toSections } from "./nav-sections";

const a = { href: "/a", label: "A", icon: "x" };
const b = { href: "/b", label: "B", icon: "x" };
const c = { href: "/c", label: "C", icon: "x" };

describe("toSections", () => {
  it("keeps a flat list as one untitled section (admin nav unchanged)", () => {
    expect(toSections([a, b])).toEqual([{ title: null, items: [a, b] }]);
  });

  it("renders groups under their titles, in order, with plain items between", () => {
    expect(
      toSections([{ group: "Work", items: [a] }, b, c, { group: "Account", items: [c] }]),
    ).toEqual([
      { title: "Work", items: [a] },
      { title: null, items: [b, c] },
      { title: "Account", items: [c] },
    ]);
  });
});
