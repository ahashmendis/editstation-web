import { describe, expect, it } from "vitest";

import { activityLabel } from "@/lib/activity-labels";

import { roundsSummary } from "./constants";
import {
  acknowledgeRevisionSchema,
  classifyRevisionSchema,
  reviewSubmissionSchema,
  submitWorkSchema,
} from "./schemas";

const projectId = "11111111-1111-4111-8111-111111111111";
const id = "22222222-2222-4222-8222-222222222222";

describe("submitWorkSchema", () => {
  it("accepts an https link and trims optional fields to null", () => {
    const r = submitWorkSchema.parse({
      projectId,
      assignmentId: id,
      link: " https://drive.example/v1 ",
      notes: " ",
      exportDetails: "4K",
    });
    expect(r).toMatchObject({ link: "https://drive.example/v1", notes: null, exportDetails: "4K" });
  });

  it("refuses non-https and long links", () => {
    expect(
      submitWorkSchema.safeParse({ projectId, assignmentId: id, link: "http://x.example" }).success,
    ).toBe(false);
    expect(
      submitWorkSchema.safeParse({
        projectId,
        assignmentId: id,
        link: `https://${"a".repeat(2050)}`,
      }).success,
    ).toBe(false);
  });
});

describe("reviewSubmissionSchema", () => {
  const base = { projectId, submissionId: id };

  it("approves without feedback, type or reason", () => {
    const r = reviewSubmissionSchema.parse({ ...base, outcome: "approved", revisionType: "" });
    expect(r).toMatchObject({ outcome: "approved", feedback: null, revisionType: null });
  });

  it("needs feedback, reason and a revision type for a revision", () => {
    const r = reviewSubmissionSchema.safeParse({ ...base, outcome: "revision_requested" });
    expect(r.success).toBe(false);
    const fields = Object.keys(r.error!.flatten().fieldErrors);
    expect(fields.sort()).toEqual(["feedback", "reason", "revisionType"]);
  });

  it("refuses scope_change as a revision type for a revision", () => {
    const r = reviewSubmissionSchema.safeParse({
      ...base,
      outcome: "revision_requested",
      feedback: "F",
      reason: "R",
      revisionType: "scope_change",
    });
    expect(r.success).toBe(false);
  });

  it("accepts a scope change without a type (the database records scope_change)", () => {
    const r = reviewSubmissionSchema.safeParse({
      ...base,
      outcome: "scope_change_required",
      feedback: "F",
      reason: "R",
    });
    expect(r.success).toBe(true);
  });

  it("needs a provisional type for needs discussion", () => {
    expect(
      reviewSubmissionSchema.safeParse({
        ...base,
        outcome: "rejected_needs_discussion",
        feedback: "F",
        reason: "R",
      }).success,
    ).toBe(false);
  });
});

describe("other schemas", () => {
  it("acknowledge maps start to a boolean", () => {
    expect(acknowledgeRevisionSchema.parse({ projectId, revisionId: id, start: "yes" }).start).toBe(
      true,
    );
    expect(acknowledgeRevisionSchema.parse({ projectId, revisionId: id }).start).toBe(false);
  });

  it("classify needs a known type and a reason", () => {
    expect(
      classifyRevisionSchema.safeParse({
        projectId,
        revisionId: id,
        revisionType: "x",
        reason: "r",
      }).success,
    ).toBe(false);
    expect(
      classifyRevisionSchema.safeParse({
        projectId,
        revisionId: id,
        revisionType: "editor_correction",
        reason: " ",
      }).success,
    ).toBe(false);
  });
});

describe("roundsSummary", () => {
  it("counts only client rounds and reports rounds beyond the allowance", () => {
    expect(
      roundsSummary(
        [
          { type: "client_revision", roundNumber: 1 },
          { type: "editor_correction", roundNumber: null },
          { type: "scope_change", roundNumber: null },
          { type: "client_revision", roundNumber: 4 },
        ],
        3,
      ),
    ).toEqual({ used: 4, allowance: 3, beyond: 1 });
    expect(roundsSummary([], 3)).toEqual({ used: 0, allowance: 3, beyond: 0 });
  });
});

describe("activity labels", () => {
  it("labels every Phase 8 action", () => {
    for (const action of [
      "submission.submitted",
      "submission.reviewed",
      "revision_request.created",
      "revision_request.classified",
      "revision_request.acknowledged",
      "revision_request.in_progress",
      "revision_request.resubmitted",
      "revision_request.approved",
    ]) {
      expect(activityLabel(action)).not.toBe("Updated");
    }
  });
});
