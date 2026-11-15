import { z } from "zod";

import type { FormState } from "@/features/authentication/schemas";

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

const boundedText = (max: number, required: string) =>
  z
    .string({ error: required })
    .trim()
    .min(1, { error: required })
    .max(max, { error: `Use at most ${max} characters.` });

const projectId = z.uuid({ error: "The project is missing. Reload the page." });
const milestoneId = z.uuid({ error: "The milestone is missing. Reload the page." });

/** "50, 50" -> [50, 50]; "100" (all upfront) -> [100]. Whole percentages adding up to 100. */
export const clientShares = z
  .string()
  .trim()
  .transform((value, ctx) => {
    const parts = value.split(/[\s,/]+/).filter(Boolean);
    const nums = parts.map(Number);
    if (
      parts.length < 1 ||
      parts.length > 10 ||
      parts.some((p) => !/^\d{1,3}$/.test(p)) ||
      nums.some((n) => n < 1 || n > 100)
    ) {
      ctx.addIssue({
        code: "custom",
        message: "List 1 to 10 whole percentages, e.g. 50, 50 or 100.",
      });
      return z.NEVER;
    }
    if (nums.reduce((a, b) => a + b, 0) !== 100) {
      ctx.addIssue({ code: "custom", message: "The client milestones must add up to 100%." });
      return z.NEVER;
    }
    return nums;
  });

export const createMilestonesSchema = z.object({ projectId, shares: clientShares });

/** Issue an invoice or verify a transfer: ids only. */
export const milestoneActionSchema = z.object({ projectId, milestoneId });

export const recordPaymentSchema = z.object({
  projectId,
  milestoneId,
  transferReference: boundedText(120, "Enter the transfer reference."),
  receivedOn: z
    .string()
    .trim()
    .optional()
    .transform((value) => (value === undefined || value === "" ? null : value))
    .refine((value) => value === null || ISO_DATE.test(value), { error: "Enter a valid date." }),
});

export const extendDueSchema = z.object({
  projectId,
  milestoneId,
  dueDate: z
    .string({ error: "Choose the new due date." })
    .trim()
    .regex(ISO_DATE, { error: "Choose the new due date." }),
  reason: boundedText(2000, "Please give a reason for the extension."),
});

export const correctPaymentSchema = z.object({
  projectId,
  milestoneId,
  reason: boundedText(2000, "Please give a reason for the correction."),
});

export const timezoneSchema = z.object({
  timezone: boundedText(100, "Enter a timezone, e.g. Asia/Colombo.").regex(/^[A-Za-z0-9_+\-/]+$/, {
    error: "Use a timezone name such as Asia/Colombo.",
  }),
});

const KEPT = [
  "shares",
  "transferReference",
  "receivedOn",
  "dueDate",
  "reason",
  "timezone",
] as const;

/** Non-secret fields to refill after a failed submit. */
export function billingKeptValues(formData: FormData): FormState["values"] {
  const values: Record<string, string> = {};
  for (const key of KEPT) {
    const v = formData.get(key);
    if (typeof v === "string") values[key] = v.slice(0, 2000);
  }
  return values;
}
