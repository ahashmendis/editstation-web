import { describe, expect, it } from "vitest";

import {
  confirmBriefSchema,
  reviewInterpretationSchema,
  startWorkSchema,
  submitInterpretationSchema,
} from "./schemas";

const ID = "5f3c2d1e-0b4a-4c6d-8e9f-1a2b3c4d5e6f";
const ID2 = "6f3c2d1e-0b4a-4c6d-8e9f-1a2b3c4d5e6f";

describe("submitInterpretationSchema", () => {
  const base = {
    projectId: ID,
    assignmentId: ID2,
    briefVersion: "2",
    willReproduce: " The pacing ",
    willAdapt: "The colours",
    questions: "",
  };

  it("trims, converts the version and nulls empty questions", () => {
    expect(submitInterpretationSchema.parse(base)).toMatchObject({
      briefVersion: 2,
      willReproduce: "The pacing",
      questions: null,
    });
  });

  it("requires both main fields and a valid version", () => {
    expect(submitInterpretationSchema.safeParse({ ...base, willReproduce: " " }).success).toBe(
      false,
    );
    expect(submitInterpretationSchema.safeParse({ ...base, willAdapt: "" }).success).toBe(false);
    expect(submitInterpretationSchema.safeParse({ ...base, briefVersion: "0" }).success).toBe(
      false,
    );
    expect(submitInterpretationSchema.safeParse({ ...base, briefVersion: "x" }).success).toBe(
      false,
    );
  });

  it("limits length", () => {
    expect(
      submitInterpretationSchema.safeParse({ ...base, questions: "a".repeat(4001) }).success,
    ).toBe(false);
  });
});

describe("confirmBriefSchema", () => {
  const base = {
    projectId: ID,
    assignmentId: ID2,
    briefVersion: "3",
    deadline: "2026-12-31",
    amount: "10000.50",
    currency: "lkr",
  };

  it("parses the displayed values", () => {
    expect(confirmBriefSchema.parse(base)).toMatchObject({
      briefVersion: 3,
      deadline: "2026-12-31",
      amount: 10000.5,
      currency: "LKR",
    });
  });

  it("rejects missing or malformed values", () => {
    expect(confirmBriefSchema.safeParse({ ...base, deadline: "" }).success).toBe(false);
    expect(confirmBriefSchema.safeParse({ ...base, amount: "0" }).success).toBe(false);
    expect(confirmBriefSchema.safeParse({ ...base, amount: "1.234" }).success).toBe(false);
    expect(confirmBriefSchema.safeParse({ ...base, currency: "LK" }).success).toBe(false);
  });
});

describe("startWorkSchema", () => {
  it("needs both ids", () => {
    expect(startWorkSchema.safeParse({ projectId: ID, assignmentId: ID2 }).success).toBe(true);
    expect(startWorkSchema.safeParse({ projectId: ID, assignmentId: "x" }).success).toBe(false);
  });
});

describe("reviewInterpretationSchema", () => {
  const base = { projectId: ID, interpretationId: ID2, decision: "accept", feedback: "" };

  it("accepts without feedback", () => {
    expect(reviewInterpretationSchema.parse(base).feedback).toBeNull();
  });

  it("requires feedback to request changes", () => {
    expect(
      reviewInterpretationSchema.safeParse({ ...base, decision: "request_changes" }).success,
    ).toBe(false);
    expect(
      reviewInterpretationSchema.safeParse({
        ...base,
        decision: "request_changes",
        feedback: "Use the client palette.",
      }).success,
    ).toBe(true);
  });

  it("rejects unknown decisions", () => {
    expect(reviewInterpretationSchema.safeParse({ ...base, decision: "maybe" }).success).toBe(
      false,
    );
  });
});
