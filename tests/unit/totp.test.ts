import { describe, expect, it } from "vitest";

import { base32Decode, totp } from "../e2e/support/totp";

// RFC 6238 appendix B test vectors (SHA-1 seed "12345678901234567890"), last 6 digits.
const SECRET = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";

describe("e2e TOTP helper", () => {
  it("decodes base32", () => {
    expect(base32Decode(SECRET).toString("ascii")).toBe("12345678901234567890");
  });

  it.each([
    [59, "94287082"],
    [1111111109, "07081804"],
    [1234567890, "89005924"],
    [2000000000, "69279037"],
  ])("matches the RFC 6238 vector at T=%i", (seconds, expected) => {
    expect(totp(SECRET, seconds * 1000, 8)).toBe(expected);
    expect(totp(SECRET, seconds * 1000)).toBe(expected.slice(2));
  });
});
