import { describe, expect, it } from "vitest";

import { activityLabel, allowedStatusActions } from "./constants";
import {
  archiveProjectSchema,
  briefPayload,
  briefSchema,
  convertInquirySchema,
  createClientSchema,
  createProjectSchema,
  deliverableSchema,
  detailsPayload,
  mergeClientsSchema,
  money,
  projectDetailsSchema,
  projectFormInput,
  projectStatusChangeSchema,
  referenceSchema,
  saveBriefSchema,
  timecodeSeconds,
  updateClientSchema,
  updateProjectSchema,
} from "./schemas";

const ID = "6f1f3c0e-8f43-4a8e-9d57-3d1b2e5f7a10";
const ID2 = "0b7c2f84-1a3d-4c55-8a0e-2d9f6c1b4e33";

const details = {
  title: "  Wedding highlight  ",
  briefType: "fully_instructed",
  serviceTypeCode: "wedding",
  summary: "",
  deadline: "2026-12-01",
  requiresInterpretation: "",
  proposedAmount: "",
  proposedCurrency: "",
  revisionAllowance: "",
  clientId: "",
  clientPrice: "",
  clientPriceCurrency: "",
  internalNotes: "",
};

const briefText = {
  instructions: "Cut to 3 minutes",
  desiredOutcome: "",
  audience: "",
  coreMessage: "",
  brandConstraints: "",
  mandatoryContent: "",
  prohibitedContent: "",
};

describe("projectDetailsSchema", () => {
  it("trims, defaults currency and allowance, and nulls blanks", () => {
    const r = projectDetailsSchema.parse(details);
    expect(r.title).toBe("Wedding highlight");
    expect(r.summary).toBeNull();
    expect(r.proposedAmount).toBeNull();
    expect(r.proposedCurrency).toBe("LKR");
    expect(r.revisionAllowance).toBeNull();
    expect(r.requiresInterpretation).toBeNull();
    expect(r.clientId).toBeNull();
  });

  it("omits an empty revision allowance on create and update", () => {
    const create = createProjectSchema.parse({
      ...details,
      ...briefText,
      deliverables: [],
      references: [],
    });
    expect(detailsPayload(create)).not.toHaveProperty("revision_allowance");
    const update = updateProjectSchema.parse({ ...details, projectId: ID });
    expect(detailsPayload(update)).not.toHaveProperty("revision_allowance");
    const set = projectDetailsSchema.parse({ ...details, revisionAllowance: "0" });
    expect(detailsPayload(set).revision_allowance).toBe(0);
  });

  it("maps activity actions to plain labels", () => {
    expect(activityLabel("project.brief_version")).toBe("New brief version");
    expect(activityLabel("inquiry.converted")).toBe("Created from inquiry");
    expect(activityLabel("something.else")).toBe("Updated");
  });

  it("requires a title and a known brief type", () => {
    expect(projectDetailsSchema.safeParse({ ...details, title: " " }).success).toBe(false);
    expect(projectDetailsSchema.safeParse({ ...details, briefType: "other" }).success).toBe(false);
  });

  it("validates dates, allowance, currency and client id", () => {
    expect(projectDetailsSchema.safeParse({ ...details, deadline: "2026-13-40" }).success).toBe(
      false,
    );
    expect(projectDetailsSchema.safeParse({ ...details, revisionAllowance: "21" }).success).toBe(
      false,
    );
    expect(projectDetailsSchema.safeParse({ ...details, revisionAllowance: "2.5" }).success).toBe(
      false,
    );
    expect(projectDetailsSchema.safeParse({ ...details, proposedCurrency: "lk" }).success).toBe(
      false,
    );
    expect(projectDetailsSchema.safeParse({ ...details, clientId: "nope" }).success).toBe(false);
  });

  it("uppercases a currency and maps interpretation to a boolean", () => {
    const r = projectDetailsSchema.parse({
      ...details,
      proposedCurrency: "usd",
      requiresInterpretation: "yes",
    });
    expect(r.proposedCurrency).toBe("USD");
    expect(r.requiresInterpretation).toBe(true);
  });
});

describe("money", () => {
  it("accepts blank and amounts with up to two decimals", () => {
    expect(money.parse("")).toBeNull();
    expect(money.parse("1500.5")).toBe(1500.5);
  });
  it("rejects negatives, extra decimals and text", () => {
    for (const bad of ["-1", "1.234", "abc", "1e3"]) {
      expect(money.safeParse(bad).success).toBe(false);
    }
  });
});

describe("timecodeSeconds", () => {
  it("parses seconds and m:ss", () => {
    expect(timecodeSeconds.parse("")).toBeNull();
    expect(timecodeSeconds.parse("90")).toBe(90);
    expect(timecodeSeconds.parse("1:30")).toBe(90);
    expect(timecodeSeconds.parse("1:02:03")).toBe(3723);
  });
  it("rejects negatives, decimals and bad minutes", () => {
    for (const bad of ["-5", "1.5", "1:75", "abc"]) {
      expect(timecodeSeconds.safeParse(bad).success).toBe(false);
    }
  });
});

describe("referenceSchema", () => {
  const ref = {
    id: "",
    title: "Pacing example",
    url: "https://example.com/video",
    startSeconds: "10",
    endSeconds: "20",
    observationNotes: "",
    priority: "essential",
    category: "pacing",
    accessNotes: "",
  };
  it("accepts a valid reference", () => {
    const r = referenceSchema.parse(ref);
    expect(r.startSeconds).toBe(10);
    expect(r.endSeconds).toBe(20);
    expect(r.observationNotes).toBeNull();
  });
  it("allows end equal to start but not before", () => {
    expect(referenceSchema.safeParse({ ...ref, endSeconds: "10" }).success).toBe(true);
    expect(referenceSchema.safeParse({ ...ref, endSeconds: "9" }).success).toBe(false);
  });
  it("needs a start when there is an end", () => {
    expect(referenceSchema.safeParse({ ...ref, startSeconds: "" }).success).toBe(false);
    expect(referenceSchema.safeParse({ ...ref, startSeconds: "", endSeconds: "" }).success).toBe(
      true,
    );
  });
  it("allows only https links", () => {
    expect(referenceSchema.safeParse({ ...ref, url: "http://example.com" }).success).toBe(false);
    expect(referenceSchema.safeParse({ ...ref, url: "javascript:alert(1)" }).success).toBe(false);
  });
  it("limits priority to essential or optional", () => {
    expect(referenceSchema.safeParse({ ...ref, priority: "optional" }).success).toBe(true);
    expect(referenceSchema.safeParse({ ...ref, priority: "high" }).success).toBe(false);
  });
});

describe("deliverableSchema", () => {
  const d = {
    id: "",
    name: "Main film",
    format: "MP4",
    resolution: "",
    aspectRatio: "16:9",
    durationSeconds: "180",
    notes: "",
  };
  it("parses duration as whole seconds", () => {
    const r = deliverableSchema.parse(d);
    expect(r.durationSeconds).toBe(180);
    expect(r.resolution).toBeNull();
  });
  it("needs a name and a whole, non-negative duration", () => {
    expect(deliverableSchema.safeParse({ ...d, name: "" }).success).toBe(false);
    expect(deliverableSchema.safeParse({ ...d, durationSeconds: "-1" }).success).toBe(false);
    expect(deliverableSchema.safeParse({ ...d, durationSeconds: "1.5" }).success).toBe(false);
  });
});

describe("briefSchema and payloads", () => {
  const deliverable = {
    id: "",
    name: "Main film",
    format: "",
    resolution: "",
    aspectRatio: "",
    durationSeconds: "",
    notes: "",
  };

  it("caps deliverables at 50 and references at 100", () => {
    expect(
      briefSchema.safeParse({
        ...briefText,
        deliverables: Array.from({ length: 51 }, () => deliverable),
        references: [],
      }).success,
    ).toBe(false);
    expect(
      briefSchema.safeParse({
        ...briefText,
        deliverables: [],
        references: Array.from({ length: 101 }, () => ({
          id: "",
          title: "x",
          url: "https://example.com",
          startSeconds: "",
          endSeconds: "",
          observationNotes: "",
          priority: "optional",
          category: "",
          accessNotes: "",
        })),
      }).success,
    ).toBe(false);
  });

  it("builds snake_case database keys and keeps ids and order", () => {
    const parsed = briefSchema.parse({
      ...briefText,
      deliverables: [deliverable, { ...deliverable, id: ID, name: "Teaser" }],
      references: [],
    });
    const payload = briefPayload(parsed);
    expect(payload.brief.instructions).toBe("Cut to 3 minutes");
    expect(payload.brief.desired_outcome).toBeNull();
    expect(payload.deliverables[0]).not.toHaveProperty("id");
    expect(payload.deliverables[1]).toMatchObject({ id: ID, name: "Teaser", sort_order: 1 });
  });

  it("requires a change summary only as optional text and a checkbox boolean", () => {
    const base = { ...briefText, deliverables: [], references: [], projectId: ID };
    expect(
      saveBriefSchema.parse({ ...base, changeSummary: "", requiresReacknowledgement: "" }),
    ).toMatchObject({ changeSummary: null, requiresReacknowledgement: false });
    expect(
      saveBriefSchema.parse({
        ...base,
        changeSummary: "Fixed typo",
        requiresReacknowledgement: "on",
      }),
    ).toMatchObject({ changeSummary: "Fixed typo", requiresReacknowledgement: true });
    expect(saveBriefSchema.safeParse({ ...base, changeSummary: "x".repeat(1001) }).success).toBe(
      false,
    );
    expect(saveBriefSchema.safeParse({ ...base, projectId: "nope" }).success).toBe(false);
  });

  it("omits requires_interpretation when left on default", () => {
    expect(detailsPayload(projectDetailsSchema.parse(details))).not.toHaveProperty(
      "requires_interpretation",
    );
    const explicit = projectDetailsSchema.parse({ ...details, requiresInterpretation: "no" });
    expect(detailsPayload(explicit)).toMatchObject({ requires_interpretation: false });
  });

  it("parses all three brief types for creation", () => {
    for (const briefType of ["fully_instructed", "reference_based", "creative_led"]) {
      const r = createProjectSchema.safeParse({
        ...details,
        ...briefText,
        briefType,
        deliverables: [],
        references: [],
      });
      expect(r.success).toBe(true);
    }
  });
});

describe("projectFormInput", () => {
  it("reads parallel row lists and drops blank rows", () => {
    const fd = new FormData();
    fd.append("title", "T");
    fd.append("deliverable.id", "");
    fd.append("deliverable.name", "Film");
    fd.append("deliverable.id", "");
    fd.append("deliverable.name", "");
    fd.append("reference.priority", "essential");
    fd.append("reference.url", "");
    const input = projectFormInput(fd);
    expect(input.deliverables).toHaveLength(1);
    expect(input.deliverables[0].name).toBe("Film");
    expect(input.references).toHaveLength(0);
    expect((input as Record<string, unknown>).title).toBe("T");
  });
});

describe("status and archive", () => {
  it("accepts only admin-settable statuses", () => {
    expect(projectStatusChangeSchema.safeParse({ projectId: ID, status: "open" }).success).toBe(
      true,
    );
    expect(projectStatusChangeSchema.safeParse({ projectId: ID, status: "assigned" }).success).toBe(
      false,
    );
  });
  it("parses the archive flag", () => {
    expect(archiveProjectSchema.parse({ projectId: ID, archive: "true" }).archive).toBe(true);
    expect(archiveProjectSchema.safeParse({ projectId: ID, archive: "maybe" }).success).toBe(false);
  });
  it("limits buttons to the allowed transitions", () => {
    expect(allowedStatusActions("draft", null).map((a) => a.to)).toEqual([
      "open",
      "on_hold",
      "cancelled",
    ]);
    expect(allowedStatusActions("open", null).map((a) => a.to)).toEqual([
      "draft",
      "on_hold",
      "cancelled",
    ]);
    expect(allowedStatusActions("on_hold", "open").map((a) => a.to)).toEqual(["open"]);
    expect(allowedStatusActions("cancelled", null)).toEqual([]);
    expect(allowedStatusActions("assigned", null)).toEqual([]);
  });
});

describe("clients", () => {
  it("normalises the email and requires a name", () => {
    const r = createClientSchema.parse({
      name: "Asha",
      company: "",
      email: "  Asha@Example.COM ",
      phone: "",
      notes: "",
    });
    expect(r.email).toBe("asha@example.com");
    expect(
      createClientSchema.safeParse({ name: "", email: "a@b.co", company: "", phone: "", notes: "" })
        .success,
    ).toBe(false);
    expect(
      createClientSchema.safeParse({ name: "A", email: "nope", company: "", phone: "", notes: "" })
        .success,
    ).toBe(false);
  });
  it("reads the archived checkbox on update", () => {
    const base = { clientId: ID, name: "A", email: "a@b.co", company: "", phone: "", notes: "" };
    expect(updateClientSchema.parse({ ...base, archived: "on" }).archived).toBe(true);
    expect(updateClientSchema.parse(base).archived).toBe(false);
  });
  it("refuses merging a client into itself", () => {
    expect(mergeClientsSchema.safeParse({ sourceId: ID, targetId: ID }).success).toBe(false);
    expect(mergeClientsSchema.safeParse({ sourceId: ID, targetId: ID2 }).success).toBe(true);
  });
});

describe("convertInquirySchema", () => {
  it("needs a brief type; title, deadline and client are optional", () => {
    const r = convertInquirySchema.parse({
      inquiryId: ID,
      title: "",
      briefType: "creative_led",
      deadline: "",
      clientId: "",
    });
    expect(r).toMatchObject({ title: null, deadline: null, clientId: null });
    expect(
      convertInquirySchema.safeParse({
        inquiryId: ID,
        title: "",
        briefType: "",
        deadline: "",
        clientId: "",
      }).success,
    ).toBe(false);
  });
});
