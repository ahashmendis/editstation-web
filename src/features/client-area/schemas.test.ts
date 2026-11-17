import { describe, expect, it } from "vitest";

import {
  bankDetailsSchema,
  clientProjectSchema,
  inviteClientUserSchema,
  publishUpdateSchema,
  verifyCodeSchema,
} from "./schemas";

const uuid = "c3000000-0000-4000-8000-000000000001";

describe("client sign-in code", () => {
  it("accepts an 8-digit code and normalises the email", () => {
    const parsed = verifyCodeSchema.parse({ email: " Client@Example.COM ", code: " 12345678 " });
    expect(parsed).toEqual({ email: "client@example.com", code: "12345678" });
  });

  it("refuses anything else", () => {
    expect(verifyCodeSchema.safeParse({ email: "a@b.co", code: "123456" }).success).toBe(false);
    expect(verifyCodeSchema.safeParse({ email: "a@b.co", code: "abcdefgh" }).success).toBe(false);
    expect(verifyCodeSchema.safeParse({ email: "nope", code: "12345678" }).success).toBe(false);
  });
});

describe("admin forms", () => {
  it("validates an invitation", () => {
    expect(inviteClientUserSchema.safeParse({ clientId: uuid, email: "x@y.co" }).success).toBe(
      true,
    );
    expect(inviteClientUserSchema.safeParse({ clientId: "1", email: "x@y.co" }).success).toBe(
      false,
    );
  });

  it("requires update text within the database limit", () => {
    expect(publishUpdateSchema.safeParse({ projectId: uuid, body: "   " }).success).toBe(false);
    expect(publishUpdateSchema.safeParse({ projectId: uuid, body: "x".repeat(5001) }).success).toBe(
      false,
    );
    expect(publishUpdateSchema.parse({ projectId: uuid, body: " Cut ready " }).body).toBe(
      "Cut ready",
    );
  });

  it("allows empty bank details (that hides the panel)", () => {
    expect(bankDetailsSchema.parse({ details: "  " }).details).toBe("");
    expect(bankDetailsSchema.safeParse({ details: "x".repeat(2001) }).success).toBe(false);
  });
});

describe("client project projection", () => {
  it("drops any key the projection did not promise", () => {
    const parsed = clientProjectSchema.parse({
      id: uuid,
      title: "Promo",
      client_status: "planning",
      created_at: "2026-11-17T00:00:00Z",
      deliverables: [],
      updates: [],
      milestones: [],
      editor_id: "should never render",
    });
    expect(parsed).not.toHaveProperty("editor_id");
  });
});
