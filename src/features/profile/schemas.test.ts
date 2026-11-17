import { describe, expect, it } from "vitest";

import { AVATAR_MAX_BYTES } from "./avatar";
import { avatarUploadSchema } from "./schemas";

const file = (size: number, type: string) => new File([new Uint8Array(size)], "a", { type });
const message = (value: unknown) =>
  avatarUploadSchema.safeParse({ avatar: value }).error?.issues[0]?.message ?? null;

describe("avatarUploadSchema", () => {
  it("accepts JPEG, PNG and WebP up to 2 MB", () => {
    expect(message(file(AVATAR_MAX_BYTES, "image/png"))).toBeNull();
    expect(message(file(10, "image/jpeg"))).toBeNull();
    expect(message(file(10, "image/webp"))).toBeNull();
  });

  it("rejects a missing, empty, oversized or other-type file with a user-safe message", () => {
    expect(message(null)).toMatch(/choose/i);
    expect(message("not a file")).toMatch(/choose/i);
    expect(message(file(0, "image/png"))).toMatch(/choose/i);
    expect(message(file(AVATAR_MAX_BYTES + 1, "image/png"))).toMatch(/2 MB/);
    expect(message(file(10, "image/gif"))).toMatch(/JPEG, PNG or WebP/);
    expect(message(file(10, "image/svg+xml"))).toMatch(/JPEG, PNG or WebP/);
  });
});
