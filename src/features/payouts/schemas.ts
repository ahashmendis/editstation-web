import { z } from "zod";

/** Payout details (Phase 12E, decision E). Locked until the owner turns the feature on. */

const required = (max: number, message: string) =>
  z
    .string({ error: message })
    .trim()
    .min(1, { error: message })
    .max(max, { error: `Use at most ${max} characters.` });

const editorId = z.uuid({ error: "The editor is missing. Reload the page." });

export const ACCOUNT_NUMBER = /^[A-Za-z0-9 -]{6,34}$/;

/** Letters and digits only (spaces and hyphens ignored). */
const alnumCount = (v: string) => v.replace(/[^A-Za-z0-9]/g, "").length;

/** A run of 6+ digits (ignoring spaces, dots, hyphens) looks like bank data; reasons are logged. */
export function hasDigitRun(v: string): boolean {
  return /\d{6,}/.test(v.replace(/[\s.-]/g, ""));
}

export const savePayoutSchema = z.object({
  accountHolder: required(120, "Enter the account holder name."),
  bank: required(120, "Enter the bank."),
  branch: required(120, "Enter the branch."),
  accountNumber: z
    .string({ error: "Enter the account number." })
    .trim()
    .min(1, { error: "Enter the account number." })
    .max(34, { error: "Use at most 34 characters." })
    .refine((v) => ACCOUNT_NUMBER.test(v) && /\d/.test(v) && alnumCount(v) >= 6, {
      error:
        "Use at least 6 letters or digits (spaces and hyphens allowed, at most 34 characters).",
    }),
});

export const VERIFY_METHODS = ["phone", "in_person", "other"] as const;
export type VerifyMethod = (typeof VERIFY_METHODS)[number];
export const VERIFY_METHOD_LABEL: Record<VerifyMethod, string> = {
  phone: "Phone call",
  in_person: "In person",
  other: "Other",
};

export const verifyPayoutSchema = z.object({
  editorId,
  version: z.coerce.number({ error: "Reload the page." }).int().min(1),
  method: z.enum(VERIFY_METHODS, { error: "Choose how you verified the details." }),
  note: required(500, "Add a short note (for example who you spoke to)."),
});

export const revealPayoutSchema = z.object({
  editorId,
  reason: required(500, "Give a reason for revealing the full account number.").refine(
    (v) => !hasDigitRun(v),
    { error: "Do not type bank details here: give the reason in words." },
  ),
});

export const attestPayoutSchema = z.object({
  editorId,
  note: required(500, "Add a short note (how and when the account was verified)."),
});

export const payoutEnabledSchema = z.object({
  enabled: z.enum(["on", "off"], { error: "Choose on or off." }),
  confirm: z.literal("yes", { error: "Tick the box to confirm." }),
});

// ---------------------------------------------------------------------------
// Function results (jsonb). Parsed so the UI never trusts the shape blindly.
// ---------------------------------------------------------------------------
const status = z.enum(["unverified", "verified"]);

export const editorPayoutSchema = z.object({
  enabled: z.boolean(),
  saved: z.boolean(),
  account_holder: z.string().optional(),
  bank: z.string().optional(),
  branch: z.string().optional(),
  account_number_masked: z.string().optional(),
  verification_status: status.optional(),
  verified_at: z.string().nullable().optional(),
  last_changed_at: z.string().optional(),
});
export type EditorPayout = z.infer<typeof editorPayoutSchema>;

export const adminPayoutSchema = editorPayoutSchema.extend({
  version: z.number().optional(),
  verified_by: z.string().nullable().optional(),
  verified_method: z.enum(VERIFY_METHODS).nullable().optional(),
  verification_note: z.string().nullable().optional(),
  mark_paid_block: z.string().nullable(),
  attestation_current: z.boolean(),
  attestation: z
    .object({ attested_at: z.string(), attested_by: z.string().nullable(), note: z.string() })
    .optional(),
});
export type AdminPayout = z.infer<typeof adminPayoutSchema>;

/** Verification status in words (never colour alone). */
export function verificationLabel(p: Pick<EditorPayout, "saved" | "verification_status">): string {
  if (!p.saved) return "Not added";
  return p.verification_status === "verified"
    ? "Verified by Lenscape"
    : "Not verified yet (Lenscape will confirm by phone)";
}
