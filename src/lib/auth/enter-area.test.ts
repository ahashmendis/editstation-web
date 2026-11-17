import { describe, expect, it } from "vitest";

import { shouldEnterArea } from "./enter-area";

describe("shouldEnterArea", () => {
  it("sends only signed-in visitors on the home page", () => {
    expect(shouldEnterArea("/", true)).toBe(true);
    expect(shouldEnterArea("/", false)).toBe(false);
  });

  it("leaves every other page alone, including the redirect target itself", () => {
    for (const path of [
      "/site",
      "/go",
      "/editors",
      "/inquire",
      "/legal/privacy",
      "/sign-in",
      "/admin",
    ]) {
      expect(shouldEnterArea(path, true)).toBe(false);
    }
  });
});
