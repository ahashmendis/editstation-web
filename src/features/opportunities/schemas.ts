import { z } from "zod";

import { closesAtFromDate } from "./constants";

// Optional fields may be absent from a form: absent = empty = null.
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

/** A positive amount with at most 2 decimals. Empty is "not given". */
const optionalAmount = z
  .string()
  .trim()
  .optional()
  .transform((value, ctx) => {
    if (value === undefined || value === "") return null;
    const n = Number(value);
    if (!/^\d+(\.\d{1,2})?$/.test(value) || !Number.isFinite(n) || n > 9_999_999_999.99) {
      ctx.addIssue({ code: "custom", message: "Enter an amount like 1500 or 1500.50." });
      return z.NEVER;
    }
    if (n <= 0) {
      ctx.addIssue({ code: "custom", message: "The amount must be more than zero." });
      return z.NEVER;
    }
    return n;
  });

const optionalCurrency = z
  .string()
  .trim()
  .toUpperCase()
  .optional()
  .transform((value) => (value === undefined || value === "" ? null : value))
  .pipe(
    z
      .string()
      .regex(/^[A-Z]{3}$/, { error: "Use a 3-letter currency code, e.g. LKR." })
      .nullable(),
  );

/** A real calendar day: 2026-02-31 is refused (it would round-trip to 2026-03-03). */
export function isRealDate(value: string): boolean {
  const parsed = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

const optionalDate = z
  .string()
  .trim()
  .optional()
  .transform((value) => (value === undefined || value === "" ? null : value))
  .pipe(
    z
      .string()
      .regex(/^\d{4}-\d{2}-\d{2}$/, { error: "Enter a date." })
      .refine(isRealDate, { error: "Enter a valid date." })
      .nullable(),
  );

const id = (what: string) => z.uuid({ error: `The ${what} is missing. Reload the page.` });

// ---------------------------------------------------------------------------
// Admin: the summary editors see (written here, never copied from the brief)
// ---------------------------------------------------------------------------
const summaryFields = {
  title: requiredText(120, "Give the opportunity a neutral title (no client name)."),
  deliverablesSummary: requiredText(1000, "Summarise the deliverables."),
  serviceTypeCode: optionalText(40),
  deadline: optionalDate,
  formatNotes: optionalText(1000),
  showPay: z
    .literal("on")
    .optional()
    .transform((v) => v === "on"),
  payAmount: optionalAmount,
  payCurrency: optionalCurrency,
  closesOn: optionalDate,
};

const payShownNeedsAmount = {
  error: "Enter the pay to show, or untick “Show pay to editors”.",
  path: ["payAmount"],
};
const paySet = (v: { showPay: boolean; payAmount: number | null }) =>
  !v.showPay || v.payAmount !== null;

export const publishOpportunitySchema = z
  .object({ projectId: id("project"), ...summaryFields })
  .refine(paySet, payShownNeedsAmount);
export const updateOpportunitySchema = z
  .object({ projectId: id("project"), opportunityId: id("opportunity"), ...summaryFields })
  .refine(paySet, payShownNeedsAmount);
export type OpportunitySummaryInput = z.infer<typeof publishOpportunitySchema>;

/** The RPC arguments shared by publish and update. Hidden pay is sent as null (never stored). */
export function summaryArgs(v: OpportunitySummaryInput) {
  return {
    p_title: v.title,
    p_deliverables_summary: v.deliverablesSummary,
    ...(v.serviceTypeCode ? { p_service_type_code: v.serviceTypeCode } : {}),
    ...(v.deadline ? { p_deadline: v.deadline } : {}),
    ...(v.formatNotes ? { p_format_notes: v.formatNotes } : {}),
    ...(v.showPay && v.payAmount !== null
      ? {
          p_shown_pay_amount: v.payAmount,
          ...(v.payCurrency ? { p_shown_pay_currency: v.payCurrency } : {}),
        }
      : {}),
    ...(v.closesOn ? { p_closes_at: closesAtFromDate(v.closesOn) } : {}),
  };
}

export const closeOpportunitySchema = z.object({
  projectId: id("project"),
  opportunityId: id("opportunity"),
});

/** "Choose this editor": the existing offer fields. The admin's amount is the offer. */
export const selectEditorSchema = z.object({
  projectId: id("project"),
  interestId: id("interest"),
  amount: optionalAmount.refine((v) => v !== null, { error: "Enter the amount you are offering." }),
  currency: optionalCurrency,
  message: optionalText(2000),
});

// ---------------------------------------------------------------------------
// Editor
// ---------------------------------------------------------------------------
export const registerInterestSchema = z.object({
  opportunityId: id("opportunity"),
  proposedAmount: optionalAmount,
  proposedCurrency: optionalCurrency,
  note: optionalText(500),
});

export const withdrawInterestSchema = z.object({ interestId: id("interest") });
