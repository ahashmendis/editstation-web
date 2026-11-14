import { z } from "zod";

const MAX_TEXT = 4000;

const requiredText = (message: string) =>
  z
    .string()
    .trim()
    .min(1, { error: message })
    .max(MAX_TEXT, { error: `Use at most ${MAX_TEXT} characters.` });

const optionalText = z
  .string()
  .trim()
  .max(MAX_TEXT, { error: `Use at most ${MAX_TEXT} characters.` })
  .optional()
  .transform((value) => (value === undefined || value === "" ? null : value));

const briefVersion = z
  .string()
  .trim()
  .regex(/^[1-9]\d{0,5}$/, { error: "The brief version is missing. Reload the page." })
  .transform(Number);

/** Interpretation: what the editor will reproduce and adapt, plus questions or limits. */
export const submitInterpretationSchema = z.object({
  projectId: z.uuid(),
  assignmentId: z.uuid(),
  briefVersion,
  willReproduce: requiredText("Say what you will reproduce from the references."),
  willAdapt: requiredText("Say what you will adapt or change."),
  questions: optionalText,
});

/** The editor confirms exactly what was shown: version, deadline, pay. */
export const confirmBriefSchema = z.object({
  projectId: z.uuid(),
  assignmentId: z.uuid(),
  briefVersion,
  deadline: z
    .string()
    .trim()
    .regex(/^\d{4}-\d{2}-\d{2}$/, { error: "The deadline is missing. Reload the page." }),
  amount: z
    .string()
    .trim()
    .regex(/^\d+(\.\d{1,2})?$/, { error: "The pay is missing. Reload the page." })
    .transform(Number)
    .refine((n) => n > 0, { error: "The pay is missing. Reload the page." }),
  currency: z
    .string()
    .trim()
    .toUpperCase()
    .regex(/^[A-Z]{3}$/, { error: "The currency is missing. Reload the page." }),
});

export const startWorkSchema = z.object({ projectId: z.uuid(), assignmentId: z.uuid() });

export const REVIEW_DECISIONS = ["accept", "request_changes"] as const;

export const reviewInterpretationSchema = z
  .object({
    projectId: z.uuid(),
    interpretationId: z.uuid(),
    decision: z.enum(REVIEW_DECISIONS, { error: "Choose accept or request changes." }),
    feedback: optionalText,
  })
  .refine((v) => v.decision !== "request_changes" || v.feedback !== null, {
    error: "Say what needs to change.",
    path: ["feedback"],
  });
