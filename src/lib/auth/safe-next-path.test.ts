import { describe, expect, it } from "vitest";

import { safeNextPath } from "./safe-next-path";

describe("safeNextPath", () => {
  it("keeps same-site relative paths and their query", () => {
    expect(safeNextPath("/apply")).toBe("/apply");
    expect(safeNextPath("/admin?tab=editors")).toBe("/admin?tab=editors");
  });

  it.each([
    ["absolute URL", "https://evil.example/phish"],
    ["protocol-relative", "//evil.example"],
    ["backslash trick", "/\\evil.example"],
    ["javascript scheme", "javascript:alert(1)"],
    ["no leading slash", "apply"],
    ["control characters", "/apply\r\nLocation: https://evil.example"],
    ["empty", ""],
    ["non-string", 42],
    ["null", null],
  ])("rejects %s", (_label, input) => {
    expect(safeNextPath(input, "/fallback")).toBe("/fallback");
  });

  it("rejects overly long values", () => {
    expect(safeNextPath(`/${"a".repeat(600)}`, "/fallback")).toBe("/fallback");
  });
});
