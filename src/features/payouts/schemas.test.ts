import { describe, expect, it } from "vitest";

import {
  adminPayoutSchema,
  attestPayoutSchema,
  hasDigitRun,
  payoutEnabledSchema,
  revealPayoutSchema,
  savePayoutSchema,
  verificationLabel,
  verifyPayoutSchema,
} from "./schemas";

const id = "6f3c2d1e-0b4a-4c6d-8e9f-1a2b3c4d5e6f";
// Obviously fake values only.
const fake = {
  accountHolder: "TEST ACCOUNT",
  bank: "TEST BANK",
  branch: "TEST BRANCH",
  accountNumber: "TEST-0000-1234",
};

describe("savePayoutSchema", () => {
  it("accepts complete details and trims them", () => {
    const r = savePayoutSchema.safeParse({ ...fake, accountHolder: "  TEST ACCOUNT " });
    expect(r.success && r.data.accountHolder).toBe("TEST ACCOUNT");
  });
  it("requires every field", () => {
    expect(savePayoutSchema.safeParse({ ...fake, bank: " " }).success).toBe(false);
  });
  it("refuses malformed account numbers", () => {
    for (const accountNumber of ["abc", "AB-123", "TEST;0000", "TEST-ACCOUNT", "1".repeat(35)]) {
      expect(savePayoutSchema.safeParse({ ...fake, accountNumber }).success).toBe(false);
    }
  });
});

describe("admin schemas", () => {
  it("verification needs a method, a version and a note", () => {
    expect(
      verifyPayoutSchema.safeParse({ editorId: id, version: "2", method: "phone", note: "TEST" })
        .success,
    ).toBe(true);
    expect(
      verifyPayoutSchema.safeParse({ editorId: id, version: "2", method: "email", note: "TEST" })
        .success,
    ).toBe(false);
    expect(
      verifyPayoutSchema.safeParse({ editorId: id, version: "2", method: "phone", note: "" })
        .success,
    ).toBe(false);
  });
  it("reveal requires a reason", () => {
    expect(revealPayoutSchema.safeParse({ editorId: id, reason: "  " }).success).toBe(false);
    expect(revealPayoutSchema.safeParse({ editorId: id, reason: "TEST" }).success).toBe(true);
  });
  it("reveal refuses reasons with a digit run (they are logged)", () => {
    expect(hasDigitRun("TEST 12-34 56")).toBe(true);
    expect(hasDigitRun("check before the 2026 transfer")).toBe(false);
    expect(revealPayoutSchema.safeParse({ editorId: id, reason: "TEST 1234567" }).success).toBe(
      false,
    );
  });
  it("attestation requires a note", () => {
    expect(attestPayoutSchema.safeParse({ editorId: id, note: "" }).success).toBe(false);
  });
  it("the flag change needs the confirmation box", () => {
    expect(payoutEnabledSchema.safeParse({ enabled: "on" }).success).toBe(false);
    expect(payoutEnabledSchema.safeParse({ enabled: "on", confirm: "yes" }).success).toBe(true);
  });
});

describe("result parsing and labels", () => {
  it("parses the locked admin view", () => {
    const r = adminPayoutSchema.safeParse({
      enabled: false,
      saved: false,
      mark_paid_block: "Record an attestation first.",
      attestation_current: false,
    });
    expect(r.success).toBe(true);
  });
  it("states verification in words", () => {
    expect(verificationLabel({ saved: false })).toBe("Not added");
    expect(verificationLabel({ saved: true, verification_status: "verified" })).toBe(
      "Verified by Lenscape",
    );
    expect(verificationLabel({ saved: true, verification_status: "unverified" })).toMatch(
      /^Not verified yet/,
    );
  });
});
