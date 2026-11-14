import { z } from "zod";

import { isPaymentStatus, type PaymentStatus } from "./constants";

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

const boundedText = (max: number, required: string) =>
  z
    .string({ error: required })
    .trim()
    .min(1, { error: required })
    .max(max, { error: `Use at most ${max} characters.` });

const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max, { error: `Use at most ${max} characters.` })
    .optional()
    .transform((value) => (value === undefined || value === "" ? null : value));

const paymentId = z.uuid({ error: "The payment is missing. Reload the page." });

export const SETTABLE_STATUSES = ["pending_approval", "approved", "processing", "on_hold"] as const;

/** Advance or hold. A reason is required only for a hold (the editor can see it). */
export const setPaymentStatusSchema = z
  .object({
    paymentId,
    status: z.enum(SETTABLE_STATUSES, { error: "Choose a valid status." }),
    reason: optionalText(500),
  })
  .superRefine((value, ctx) => {
    if (value.status === "on_hold" && value.reason === null) {
      ctx.addIssue({
        code: "custom",
        path: ["reason"],
        message: "Please give a reason for the hold.",
      });
    }
  });

export const releaseHoldSchema = z.object({ paymentId });

export const markPaidSchema = z.object({
  paymentId,
  reference: boundedText(120, "Enter the transaction reference."),
  transferDate: z
    .string({ error: "Enter the transfer date." })
    .trim()
    .regex(ISO_DATE, { error: "Enter the transfer date." }),
});

export const setDueDateSchema = z.object({
  paymentId,
  dueDate: z
    .string()
    .trim()
    .optional()
    .transform((value) => (value === undefined || value === "" ? null : value))
    .refine((value) => value === null || ISO_DATE.test(value), { error: "Enter a valid date." }),
});

export const reversePaymentSchema = z.object({
  paymentId,
  reason: boundedText(500, "Give a reason for the reversal."),
  reopen: z
    .string()
    .optional()
    .transform((value) => value === "on" || value === "true"),
});

export const paymentNoteSchema = z.object({
  paymentId,
  note: boundedText(4000, "Write a note."),
});

export type AdminEarningsFilter = {
  status: PaymentStatus | null;
  editor: string | null;
  currency: string | null;
};

const first = (value: unknown) => (Array.isArray(value) ? value[0] : value);

/** Search-param filters: invalid values are dropped, never thrown. */
export function parseAdminEarningsFilter(params: Record<string, unknown>): AdminEarningsFilter {
  const status = first(params.status);
  const editor = first(params.editor);
  const currency = first(params.currency);
  return {
    status: isPaymentStatus(status) ? status : null,
    editor: typeof editor === "string" && z.uuid().safeParse(editor).success ? editor : null,
    currency: typeof currency === "string" && /^[A-Z]{3}$/.test(currency) ? currency : null,
  };
}

export function parseEditorEarningsFilter(params: Record<string, unknown>): {
  status: PaymentStatus | null;
} {
  const status = first(params.status);
  return { status: isPaymentStatus(status) ? status : null };
}
