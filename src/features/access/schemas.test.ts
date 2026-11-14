import { describe, expect, it } from "vitest";

import {
  addNoteSchema,
  assetRowsFromForm,
  assetsPayload,
  assetsSchema,
  confirmAssignmentSchema,
  earlyAccessSchema,
  grantAccessInput,
  grantAccessSchema,
  makeOfferSchema,
  reassignSchema,
  recordGrantSchema,
  respondSchema,
  revokeAccessSchema,
  revokeGrantSchema,
  saveAssetsSchema,
  withdrawOfferSchema,
} from "./schemas";

const ID = "5f3c2d1e-0b4a-4c6d-8e9f-1a2b3c4d5e6f";
const ID2 = "6f3c2d1e-0b4a-4c6d-8e9f-1a2b3c4d5e6f";

describe("assets", () => {
  const row = {
    id: "",
    label: " Raw footage ",
    url: "https://drive.example/x",
    provider: "dropbox",
    kind: "",
    notes: "",
  };

  it("trims, nulls empty text and accepts https links", () => {
    const parsed = assetsSchema.parse([row]);
    expect(parsed[0]).toMatchObject({ label: "Raw footage", id: null, kind: null, notes: null });
  });

  it("rejects http links, a missing label and an unknown provider", () => {
    expect(assetsSchema.safeParse([{ ...row, url: "http://x.test" }]).success).toBe(false);
    expect(assetsSchema.safeParse([{ ...row, label: " " }]).success).toBe(false);
    expect(assetsSchema.safeParse([{ ...row, provider: "box" }]).success).toBe(false);
  });

  it("limits the number of assets", () => {
    expect(assetsSchema.safeParse(Array.from({ length: 101 }, () => row)).success).toBe(false);
  });

  it("requires a project id", () => {
    expect(saveAssetsSchema.safeParse({ projectId: "nope", assets: [] }).success).toBe(false);
    expect(saveAssetsSchema.safeParse({ projectId: ID, assets: [] }).success).toBe(true);
  });

  it("builds rows from parallel form fields, dropping empty rows", () => {
    const fd = new FormData();
    const fields = {
      id: ["", ""],
      label: ["Footage", ""],
      url: ["https://a.test", ""],
      provider: ["other", "other"],
      kind: ["footage", ""],
      notes: ["", ""],
    };
    for (const [f, values] of Object.entries(fields)) {
      for (const v of values) fd.append(`asset.${f}`, v);
    }
    const rows = assetRowsFromForm(fd);
    expect(rows).toHaveLength(1);
    expect(rows[0].label).toBe("Footage");
  });

  it("builds the database payload with sort order and optional ids", () => {
    const parsed = assetsSchema.parse([row, { ...row, id: ID, label: "B" }]);
    const payload = assetsPayload(parsed);
    expect(payload[0]).toEqual({
      label: "Raw footage",
      url: "https://drive.example/x",
      provider: "dropbox",
      kind: null,
      notes: null,
      sort_order: 0,
    });
    expect(payload[1]).toMatchObject({ id: ID, sort_order: 1 });
  });
});

describe("earlyAccessSchema", () => {
  it("parses the toggle", () => {
    const on = earlyAccessSchema.parse({
      projectId: ID,
      targetId: ID2,
      target: "asset",
      value: "true",
    });
    expect(on.value).toBe(true);
    const off = earlyAccessSchema.parse({
      projectId: ID,
      targetId: ID2,
      target: "reference",
      value: "false",
    });
    expect(off.value).toBe(false);
  });

  it("rejects an unknown target or value", () => {
    const base = { projectId: ID, targetId: ID2, target: "asset", value: "true" };
    expect(earlyAccessSchema.safeParse({ ...base, target: "x" }).success).toBe(false);
    expect(earlyAccessSchema.safeParse({ ...base, value: "yes" }).success).toBe(false);
  });
});

describe("grantAccessSchema", () => {
  it("needs at least one editor and a reason", () => {
    const base = { projectId: ID, editorIds: [ID2], reason: "invited" };
    expect(grantAccessSchema.safeParse({ ...base, editorIds: [] }).success).toBe(false);
    expect(grantAccessSchema.safeParse({ ...base, reason: "other" }).success).toBe(false);
    expect(grantAccessSchema.safeParse({ ...base, reason: "available" }).success).toBe(true);
  });

  it("collects and de-duplicates ids from the form", () => {
    const fd = new FormData();
    fd.append("projectId", ID);
    fd.append("editorIds", ID2);
    fd.append("editorIds", ID2);
    fd.append("reason", "invited");
    expect(grantAccessInput(fd).editorIds).toEqual([ID2]);
  });

  it("limits the number of editors", () => {
    const ids = Array.from(
      { length: 101 },
      (_, i) => `00000000-0000-4000-8000-${String(i).padStart(12, "0")}`,
    );
    const result = grantAccessSchema.safeParse({
      projectId: ID,
      editorIds: ids,
      reason: "invited",
    });
    expect(result.success).toBe(false);
  });
});

describe("makeOfferSchema", () => {
  const base = { projectId: ID, editorId: ID2, amount: "15000", currency: "", message: "" };

  it("accepts an amount and leaves currency and message empty", () => {
    expect(makeOfferSchema.parse(base)).toMatchObject({
      amount: 15000,
      currency: null,
      message: null,
    });
  });

  it("upper-cases a currency", () => {
    expect(makeOfferSchema.parse({ ...base, currency: "usd" }).currency).toBe("USD");
  });

  it("requires a positive amount with at most 2 decimals", () => {
    for (const amount of ["", "0", "-5", "10.555", "abc", "10000000000"]) {
      expect(makeOfferSchema.safeParse({ ...base, amount }).success, amount).toBe(false);
    }
  });

  it("rejects a bad currency and an over-long message", () => {
    expect(makeOfferSchema.safeParse({ ...base, currency: "LK" }).success).toBe(false);
    expect(makeOfferSchema.safeParse({ ...base, message: "x".repeat(2001) }).success).toBe(false);
  });
});

describe("respondSchema", () => {
  const base = {
    projectId: ID,
    assignmentId: ID2,
    action: "accept",
    amount: "",
    currency: "",
    message: "",
  };

  it("accepts and declines without an amount", () => {
    expect(respondSchema.safeParse(base).success).toBe(true);
    expect(respondSchema.safeParse({ ...base, action: "decline", message: "Busy" }).success).toBe(
      true,
    );
  });

  it("requires an amount to counter", () => {
    expect(respondSchema.safeParse({ ...base, action: "counter" }).success).toBe(false);
    expect(respondSchema.safeParse({ ...base, action: "counter", amount: "18000" }).success).toBe(
      true,
    );
  });

  it("rejects an unknown action", () => {
    expect(respondSchema.safeParse({ ...base, action: "confirm" }).success).toBe(false);
    expect(respondSchema.safeParse({ ...base, action: "" }).success).toBe(false);
  });
});

describe("withdraw, confirm, reassign, revoke access", () => {
  it("parse ids and optional messages", () => {
    const withdraw = withdrawOfferSchema.parse({ projectId: ID, assignmentId: ID2, message: " " });
    expect(withdraw.message).toBeNull();
    const reassign = reassignSchema.parse({
      projectId: ID,
      assignmentId: ID2,
      message: "Needs a new editor",
    });
    expect(reassign.message).toBe("Needs a new editor");
    expect(confirmAssignmentSchema.safeParse({ projectId: ID, assignmentId: "x" }).success).toBe(
      false,
    );
    expect(revokeAccessSchema.safeParse({ projectId: ID, editorId: ID2 }).success).toBe(true);
    expect(revokeAccessSchema.safeParse({ projectId: ID }).success).toBe(false);
  });
});

describe("recordGrantSchema", () => {
  const base = {
    projectId: ID,
    editorId: ID2,
    email: "  Editor@Drive.COM ",
    provider: "google_drive",
    folderUrl: "",
  };

  it("normalises the email and treats an empty folder link as none", () => {
    expect(recordGrantSchema.parse(base)).toMatchObject({
      email: "editor@drive.com",
      folderUrl: null,
    });
  });

  it("requires an https folder link when given, a valid email and a provider", () => {
    expect(recordGrantSchema.safeParse({ ...base, folderUrl: "http://x.test" }).success).toBe(
      false,
    );
    expect(recordGrantSchema.safeParse({ ...base, folderUrl: "https://x.test/f" }).success).toBe(
      true,
    );
    expect(recordGrantSchema.safeParse({ ...base, email: "nope" }).success).toBe(false);
    expect(recordGrantSchema.safeParse({ ...base, provider: "" }).success).toBe(false);
    expect(recordGrantSchema.safeParse({ ...base, editorId: "" }).success).toBe(false);
  });
});

describe("revokeGrantSchema", () => {
  it("allows no project and no reason", () => {
    expect(revokeGrantSchema.parse({ grantId: ID, projectId: "", reason: "" })).toEqual({
      grantId: ID,
      projectId: null,
      reason: null,
    });
  });

  it("limits the reason", () => {
    const result = revokeGrantSchema.safeParse({
      grantId: ID,
      projectId: "",
      reason: "x".repeat(501),
    });
    expect(result.success).toBe(false);
  });
});

describe("addNoteSchema", () => {
  it("needs a note of up to 4000 characters", () => {
    expect(addNoteSchema.safeParse({ projectId: ID, note: "  " }).success).toBe(false);
    expect(addNoteSchema.safeParse({ projectId: ID, note: "x".repeat(4001) }).success).toBe(false);
    expect(addNoteSchema.parse({ projectId: ID, note: " Called the client " }).note).toBe(
      "Called the client",
    );
  });
});

describe("respond forms without amount fields", () => {
  const ids = {
    projectId: "11111111-1111-4111-8111-111111111111",
    assignmentId: "22222222-2222-4222-8222-222222222222",
  };
  it("accepts accept and decline with no amount, currency or message", () => {
    expect(respondSchema.safeParse({ ...ids, action: "accept" }).success).toBe(true);
    expect(respondSchema.safeParse({ ...ids, action: "decline" }).success).toBe(true);
  });
  it("still requires an amount to counter", () => {
    expect(respondSchema.safeParse({ ...ids, action: "counter" }).success).toBe(false);
  });
});
