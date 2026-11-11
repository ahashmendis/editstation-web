import { describe, expect, it } from "vitest";
import { cn } from "@/lib/utils";

// Smoke test: proves Vitest, TypeScript and the "@/" path alias are wired up.
describe("cn", () => {
  it("merges class names and resolves Tailwind conflicts", () => {
    expect(cn("px-2", false && "hidden", "px-4")).toBe("px-4");
  });
});
