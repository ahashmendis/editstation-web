import { z } from "zod";

import { httpsUrl } from "@/features/applications/schemas";

import { MAX_REFERENCE_LINKS, SETTABLE_INQUIRY_STATUSES } from "./constants";

const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max, { error: `Use at most ${max} characters.` })
    .transform((value) => (value === "" ? null : value));

const requiredText = (max: number, message: string) =>
  z
    .string()
    .trim()
    .min(1, { error: message })
    .max(max, { error: `Use at most ${max} characters.` });

/** Public client inquiry form (decisions N, U, V). */
export const inquirySchema = z.object({
  contactName: requiredText(200, "Please tell us your name."),
  company: optionalText(200),
  email: z
    .string()
    .trim()
    .toLowerCase()
    .pipe(z.email({ error: "Enter a valid email address." }).max(254)),
  phone: optionalText(40),
  serviceType: z.string().regex(/^[a-z0-9_]{1,40}$/, { error: "Please choose a type of service." }),
  description: requiredText(5000, "Please describe the project."),
  expectedDeliverables: optionalText(2000),
  budgetRangeId: z
    .string()
    .trim()
    .transform((value) => (value === "" || value === "discuss" ? null : value))
    .pipe(z.uuid({ error: "Please choose a budget option." }).nullable()),
  expectedDeadline: z
    .string()
    .trim()
    .transform((value, ctx) => {
      if (value === "") return null;
      if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || Number.isNaN(Date.parse(`${value}T00:00:00Z`))) {
        ctx.addIssue({ code: "custom", message: "Enter a valid date." });
        return z.NEVER;
      }
      return value;
    }),
  clientNotes: optionalText(2000),
  links: z
    .array(z.object({ url: httpsUrl, label: optionalText(120) }))
    .max(MAX_REFERENCE_LINKS, { error: `Add at most ${MAX_REFERENCE_LINKS} links.` }),
});

export function inquiryFormInput(formData: FormData) {
  const text = (name: string) => {
    const value = formData.get(name);
    return typeof value === "string" ? value : "";
  };
  const urls = formData.getAll("linkUrl").map(String);
  const labels = formData.getAll("linkLabel").map(String);
  return {
    contactName: text("contactName"),
    company: text("company"),
    email: text("email"),
    phone: text("phone"),
    serviceType: text("serviceType"),
    description: text("description"),
    expectedDeliverables: text("expectedDeliverables"),
    budgetRangeId: text("budgetRangeId"),
    expectedDeadline: text("expectedDeadline"),
    clientNotes: text("clientNotes"),
    links: urls
      .map((url, i) => ({ url, label: labels[i] ?? "" }))
      .filter((link) => link.url.trim() !== "" || link.label.trim() !== ""),
  };
}

/** Non-secret values to refill after a failed submit (all inquiry fields are non-secret). */
export function inquiryKeptValues(formData: FormData): Record<string, string> {
  const keep = [
    "contactName",
    "company",
    "email",
    "phone",
    "serviceType",
    "description",
    "expectedDeliverables",
    "budgetRangeId",
    "expectedDeadline",
    "clientNotes",
  ];
  return Object.fromEntries(
    keep.map((name) => [name, String(formData.get(name) ?? "").slice(0, 5000)]),
  );
}

// --- Admin -------------------------------------------------------------------

export const inquiryStatusSchema = z.object({
  inquiryId: z.uuid(),
  status: z.enum(SETTABLE_INQUIRY_STATUSES as [string, ...string[]]),
  note: optionalText(4000),
});

export const inquiryNoteSchema = z.object({
  inquiryId: z.uuid(),
  note: requiredText(4000, "Write a note."),
});

const sortOrder = z
  .string()
  .trim()
  .transform((value, ctx) => {
    const n = value === "" ? 0 : Number(value);
    if (!Number.isInteger(n) || n < -999 || n > 999) {
      ctx.addIssue({ code: "custom", message: "Sort order must be a whole number." });
      return z.NEVER;
    }
    return n;
  });

const active = z
  .union([z.literal("on"), z.literal("")])
  .optional()
  .transform((value) => value === "on");

export const serviceTypeSchema = z.object({
  code: z
    .string()
    .trim()
    .regex(/^[a-z0-9_]{1,40}$/, { error: "Use lowercase letters, numbers and underscores." }),
  label: requiredText(80, "Give the service a name."),
  sortOrder,
  active,
});

const amount = z
  .string()
  .trim()
  .transform((value, ctx) => {
    if (value === "") return null;
    const n = Number(value);
    if (!Number.isFinite(n) || n < 0 || n > 9_999_999_999) {
      ctx.addIssue({ code: "custom", message: "Enter a positive amount." });
      return z.NEVER;
    }
    return n;
  });

export const budgetRangeSchema = z
  .object({
    id: z
      .string()
      .trim()
      .transform((value) => (value === "" ? null : value))
      .pipe(z.uuid().nullable()),
    label: requiredText(80, "Give the range a label."),
    minAmount: amount,
    maxAmount: amount,
    currency: z
      .string()
      .trim()
      .toUpperCase()
      .regex(/^[A-Z]{3}$/, { error: "Use a 3-letter currency code, e.g. LKR." }),
    sortOrder,
    active,
  })
  .refine((v) => v.minAmount === null || v.maxAmount === null || v.minAmount <= v.maxAmount, {
    error: "The minimum must not be above the maximum.",
    path: ["maxAmount"],
  });
