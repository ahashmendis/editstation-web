import { describe, expect, it } from "vitest";

import {
  bankDetailsSchema,
  clientProjectRequestInput,
  clientProjectRequestKeptValues,
  clientProjectRequestSchema,
  clientRequestRowSchema,
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

describe("new project request", () => {
  const form = (entries: [string, string][]) => {
    const data = new FormData();
    for (const [k, v] of entries) data.append(k, v);
    return data;
  };

  it("uses the public form's project rules and ignores contact fields", () => {
    const data = form([
      ["serviceType", "long_form"],
      ["description", "  Our launch film  "],
      ["expectedDeliverables", ""],
      ["budgetRangeId", "discuss"],
      ["expectedDeadline", "2099-03-01"],
      ["clientNotes", ""],
      ["linkUrl", "https://example.com/ref"],
      ["linkLabel", "Style"],
      ["linkUrl", ""],
      ["linkLabel", ""],
      ["email", "spoof@example.com"],
      ["contactName", "Someone Else"],
    ]);
    const parsed = clientProjectRequestSchema.parse(clientProjectRequestInput(data));
    expect(parsed).toEqual({
      serviceType: "long_form",
      description: "Our launch film",
      expectedDeliverables: null,
      budgetRangeId: null,
      expectedDeadline: "2099-03-01",
      clientNotes: null,
      links: [{ url: "https://example.com/ref", label: "Style" }],
    });
    expect(parsed).not.toHaveProperty("email");
    expect(parsed).not.toHaveProperty("contactName");
  });

  it("refuses what the public form refuses", () => {
    const base = {
      serviceType: "long_form",
      description: "x",
      expectedDeliverables: "",
      budgetRangeId: "",
      expectedDeadline: "",
      clientNotes: "",
      links: [],
    };
    expect(clientProjectRequestSchema.safeParse(base).success).toBe(true);
    expect(clientProjectRequestSchema.safeParse({ ...base, description: "  " }).success).toBe(
      false,
    );
    expect(clientProjectRequestSchema.safeParse({ ...base, serviceType: "" }).success).toBe(false);
    expect(clientProjectRequestSchema.safeParse({ ...base, budgetRangeId: "nope" }).success).toBe(
      false,
    );
    expect(
      clientProjectRequestSchema.safeParse({ ...base, expectedDeadline: "31/01/2099" }).success,
    ).toBe(false);
    expect(
      clientProjectRequestSchema.safeParse({ ...base, links: [{ url: "http://a.co", label: "" }] })
        .success,
    ).toBe(false);
    expect(
      clientProjectRequestSchema.safeParse({
        ...base,
        links: Array.from({ length: 11 }, (_, i) => ({ url: `https://a.co/${i}`, label: "" })),
      }).success,
    ).toBe(false);
  });

  it("keeps what the client typed after a failed submit", () => {
    const kept = clientProjectRequestKeptValues(
      form([
        ["description", "Keep me"],
        ["serviceType", "long_form"],
      ]),
    );
    expect(kept.description).toBe("Keep me");
    expect(kept.serviceType).toBe("long_form");
    expect(kept).not.toHaveProperty("email");
  });
});

describe("client request projection", () => {
  it("drops any key the projection did not promise", () => {
    const parsed = clientRequestRowSchema.parse({
      id: uuid,
      service_type_label: "Long-form video",
      description: "Our launch film",
      expected_deadline: null,
      submitted_at: "2026-11-18T00:00:00Z",
      request_status: "received",
      project_id: null,
      status: "spam",
      internal_note: "should never render",
    });
    expect(parsed).not.toHaveProperty("status");
    expect(parsed).not.toHaveProperty("internal_note");
  });
});
