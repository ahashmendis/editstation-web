import { describe, expect, it } from "vitest";

import { newPasswordSchema, signInSchema, signUpSchema, totpCodeSchema } from "./schemas";

describe("signUpSchema", () => {
  const valid = {
    email: "  Editor@Example.com ",
    password: "frames2024cut",
    confirmPassword: "frames2024cut",
  };

  it("accepts a valid sign-up and normalises the email", () => {
    const result = signUpSchema.safeParse(valid);
    expect(result.success).toBe(true);
    expect(result.data?.email).toBe("editor@example.com");
  });

  it("ignores extra fields such as a self-assigned role", () => {
    const result = signUpSchema.safeParse({ ...valid, role: "admin", access_status: "active" });
    expect(result.success).toBe(true);
    expect(result.data).not.toHaveProperty("role");
    expect(result.data).not.toHaveProperty("access_status");
  });

  it.each([
    ["too short", "abc123"],
    ["no digits", "onlylettershere"],
    ["no letters", "12345678901"],
  ])("rejects a password that is %s", (_label, password) => {
    const result = signUpSchema.safeParse({ ...valid, password, confirmPassword: password });
    expect(result.success).toBe(false);
  });

  it("rejects mismatched passwords", () => {
    const result = signUpSchema.safeParse({ ...valid, confirmPassword: "different2024x" });
    expect(result.success).toBe(false);
  });

  it("rejects an invalid email", () => {
    expect(signUpSchema.safeParse({ ...valid, email: "not-an-email" }).success).toBe(false);
  });
});

describe("signInSchema", () => {
  it("does not apply strength rules at sign-in", () => {
    expect(signInSchema.safeParse({ email: "a@b.co", password: "x" }).success).toBe(true);
  });

  it("requires a password", () => {
    expect(signInSchema.safeParse({ email: "a@b.co", password: "" }).success).toBe(false);
  });
});

describe("newPasswordSchema", () => {
  it("applies strength rules", () => {
    expect(
      newPasswordSchema.safeParse({ password: "short1", confirmPassword: "short1" }).success,
    ).toBe(false);
  });
});

describe("totpCodeSchema", () => {
  it("accepts six digits", () => {
    expect(totpCodeSchema.safeParse({ code: " 123456 " }).success).toBe(true);
  });

  it.each(["12345", "1234567", "abcdef", ""])("rejects %j", (code) => {
    expect(totpCodeSchema.safeParse({ code }).success).toBe(false);
  });
});
