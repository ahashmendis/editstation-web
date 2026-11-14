import { z } from "zod";

import { REVISION_TYPES, SUBMISSION_OUTCOMES } from "./constants";

const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max, { error: `Use at most ${max} characters.` })
    .optional()
    .transform((value) => (value === undefined || value === "" ? null : value));

/** The editor's submission: a link to the work (never the media itself), notes, export details. */
export const submitWorkSchema = z.object({
  projectId: z.uuid(),
  assignmentId: z.uuid(),
  link: z
    .string()
    .trim()
    .max(2048, { error: "Use at most 2048 characters." })
    .regex(/^https:\/\/\S+$/, { error: "Enter a link that starts with https://." }),
  notes: optionalText(4000),
  exportDetails: optionalText(2000),
});

export const acknowledgeRevisionSchema = z.object({
  projectId: z.uuid(),
  revisionId: z.uuid(),
  start: z
    .enum(["yes", "no"])
    .optional()
    .transform((v) => v === "yes"),
});

const revisionType = z.enum(REVISION_TYPES, {
  error: "Choose client revision, editor correction or scope change.",
});

export const reviewSubmissionSchema = z
  .object({
    projectId: z.uuid(),
    submissionId: z.uuid(),
    outcome: z.enum(SUBMISSION_OUTCOMES, { error: "Choose a review outcome." }),
    feedback: optionalText(4000),
    revisionType: z
      .union([revisionType, z.literal("")])
      .optional()
      .transform((v) => (v ? v : null)),
    reason: optionalText(4000),
  })
  .superRefine((v, ctx) => {
    if (v.outcome === "approved") return;
    if (v.feedback === null)
      ctx.addIssue({
        code: "custom",
        message: "Feedback for the editor is required unless you approve.",
        path: ["feedback"],
      });
    if (v.reason === null)
      ctx.addIssue({
        code: "custom",
        message: "Give the reason for this change request.",
        path: ["reason"],
      });
    if (
      v.outcome === "revision_requested" &&
      v.revisionType !== "client_revision" &&
      v.revisionType !== "editor_correction"
    )
      ctx.addIssue({
        code: "custom",
        message: "A revision is a client revision or an editor correction.",
        path: ["revisionType"],
      });
    if (v.outcome === "rejected_needs_discussion" && v.revisionType === null)
      ctx.addIssue({
        code: "custom",
        message: "Choose a provisional classification.",
        path: ["revisionType"],
      });
  });

export const classifyRevisionSchema = z.object({
  projectId: z.uuid(),
  revisionId: z.uuid(),
  revisionType,
  reason: z
    .string()
    .trim()
    .min(1, { error: "Give the reason for this classification." })
    .max(4000, { error: "Use at most 4000 characters." }),
});

export const completeProjectSchema = z.object({ projectId: z.uuid() });
