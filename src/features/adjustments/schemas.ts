import { z } from "zod";

import type { FormState } from "@/features/authentication/schemas";

import { ADJUSTMENT_KINDS } from "./constants";

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const MONEY = /^\d{1,10}(\.\d{1,2})?$/;

const projectId = z.uuid({ error: "The project is missing. Reload the page." });

/** A positive amount in whole cents, entered as text ("2500" or "2500.50"). */
const money = (label: string) =>
  z
    .string({ error: `Enter the ${label}.` })
    .trim()
    .regex(MONEY, { error: `Enter the ${label} as a number with at most 2 decimals.` })
    .transform(Number)
    .refine((n) => n > 0, { error: `The ${label} must be above 0.` });

const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max, { error: `Use at most ${max} characters.` })
    .optional()
    .transform((value) => (value === undefined || value === "" ? null : value));

const requiredText = (max: number, message: string) =>
  z
    .string({ error: message })
    .trim()
    .min(1, { error: message })
    .max(max, { error: `Use at most ${max} characters.` });

const dueDate = z
  .string({ error: "Enter the client due date." })
  .trim()
  .regex(ISO_DATE, { error: "Enter the client due date." });

const optionalUuid = z
  .union([z.uuid(), z.literal("")])
  .optional()
  .transform((v) => (v ? v : null));

export const setRequiredSchema = z.object({
  projectId,
  revisionId: z.uuid(),
  required: z.enum(["yes", "no"]).transform((v) => v === "yes"),
});

export const offerAdjustmentSchema = z
  .object({
    projectId,
    assignmentId: z.uuid({ error: "The assignment is missing. Reload the page." }),
    kind: z.enum(ADJUSTMENT_KINDS, { error: "Choose what the extra pay is for." }),
    amount: money("extra pay"),
    revisionId: optionalUuid,
    quoteId: optionalUuid,
    note: optionalText(1000),
  })
  .superRefine((v, ctx) => {
    if (v.kind === "extra_round" && v.revisionId === null)
      ctx.addIssue({ code: "custom", message: "The change request is missing.", path: ["kind"] });
    if (v.kind === "scope_change" && v.quoteId === null)
      ctx.addIssue({ code: "custom", message: "The scope quote is missing.", path: ["kind"] });
  });

export const adjustmentIdSchema = z.object({ projectId, adjustmentId: z.uuid() });

export const respondAdjustmentSchema = z.object({
  projectId,
  adjustmentId: z.uuid(),
  response: z.enum(["accept", "decline"], { error: "Choose accept or decline." }),
});

export const createQuoteSchema = z.object({
  projectId,
  revisionId: z.uuid(),
  description: requiredText(4000, "Describe the scope change for the client."),
  amount: money("client quote"),
  currency: z
    .string({ error: "Enter a three-letter currency code." })
    .trim()
    .regex(/^[A-Za-z]{3}$/, { error: "Enter a three-letter currency code." })
    .transform((v) => v.toUpperCase()),
});

export const quoteIdSchema = z.object({ projectId, quoteId: z.uuid() });

export const quoteAnswerSchema = z
  .object({
    projectId,
    quoteId: z.uuid(),
    accepted: z
      .enum(["yes", "no"], { error: "Choose the client's answer." })
      .transform((v) => v === "yes"),
    dueDate: z
      .string()
      .trim()
      .optional()
      .transform((v) => (v ? v : null))
      .refine((v) => v === null || ISO_DATE.test(v), { error: "Enter a valid date." }),
  })
  .superRefine((v, ctx) => {
    if (v.accepted && v.dueDate === null)
      ctx.addIssue({ code: "custom", message: "Enter the client due date.", path: ["dueDate"] });
  });

export const chargeRoundSchema = z.object({ projectId, revisionId: z.uuid(), dueDate });

export const settleSchema = z
  .object({
    projectId,
    adjustedEarned: z
      .string()
      .trim()
      .optional()
      .transform((v) => (v ? v : null))
      .refine((v) => v === null || MONEY.test(v), {
        error: "Enter the amount as a number with at most 2 decimals.",
      })
      .transform((v) => (v === null ? null : Number(v))),
    reason: optionalText(2000),
  })
  .superRefine((v, ctx) => {
    if (v.adjustedEarned !== null && v.reason === null)
      ctx.addIssue({
        code: "custom",
        message: "Give the reason for changing the editor's earned amount.",
        path: ["reason"],
      });
  });

const KEPT = [
  "amount",
  "note",
  "description",
  "currency",
  "dueDate",
  "adjustedEarned",
  "reason",
] as const;

/** Non-secret fields to refill after a failed submit. */
export function adjustmentKeptValues(formData: FormData): FormState["values"] {
  const values: Record<string, string> = {};
  for (const key of KEPT) {
    const v = formData.get(key);
    if (typeof v === "string") values[key] = v.slice(0, 4000);
  }
  return values;
}
