import { z } from "zod";

import { httpsUrl } from "@/features/applications/schemas";

import {
  BRIEF_TYPES,
  DEFAULT_CURRENCY,
  MAX_DELIVERABLES,
  MAX_REFERENCES,
  REFERENCE_PRIORITIES,
} from "./constants";

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

const optionalUuid = z
  .string()
  .trim()
  .transform((value) => (value === "" ? null : value))
  .pipe(z.uuid({ error: "Choose a valid option." }).nullable());

const optionalDate = z
  .string()
  .trim()
  .transform((value, ctx) => {
    if (value === "") return null;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || Number.isNaN(Date.parse(`${value}T00:00:00Z`))) {
      ctx.addIssue({ code: "custom", message: "Enter a valid date." });
      return z.NEVER;
    }
    return value;
  });

/** Money: empty means "not set"; otherwise a non-negative amount with at most 2 decimals. */
export const money = z
  .string()
  .trim()
  .transform((value, ctx) => {
    if (value === "") return null;
    const n = Number(value);
    if (!/^\d+(\.\d{1,2})?$/.test(value) || !Number.isFinite(n) || n > 9_999_999_999) {
      ctx.addIssue({ code: "custom", message: "Enter an amount like 1500 or 1500.50." });
      return z.NEVER;
    }
    return n;
  });

export const currencyCode = z
  .string()
  .trim()
  .toUpperCase()
  .transform((value) => (value === "" ? DEFAULT_CURRENCY : value))
  .pipe(z.string().regex(/^[A-Z]{3}$/, { error: "Use a 3-letter currency code, e.g. LKR." }));

const wholeNumber = (min: number, max: number, message: string) =>
  z
    .string()
    .trim()
    .transform((value, ctx) => {
      if (value === "") return null;
      const n = Number(value);
      if (!/^\d+$/.test(value) || !Number.isInteger(n) || n < min || n > max) {
        ctx.addIssue({ code: "custom", message });
        return z.NEVER;
      }
      return n;
    });

/**
 * A timecode in seconds. Accepts whole seconds ("90") or m:ss / h:mm:ss ("1:30"), and always
 * returns whole seconds.
 */
export const timecodeSeconds = z
  .string()
  .trim()
  .transform((value, ctx) => {
    if (value === "") return null;
    if (/^\d{1,7}$/.test(value)) return Number(value);
    const match = /^(?:(\d{1,3}):)?(\d{1,2}):([0-5]\d)$/.exec(value);
    if (!match || (match[1] !== undefined && Number(match[2]) > 59)) {
      ctx.addIssue({ code: "custom", message: "Enter a time in whole seconds, or as m:ss." });
      return z.NEVER;
    }
    return Number(match[1] ?? 0) * 3600 + Number(match[2]) * 60 + Number(match[3]);
  });

const checkbox = z
  .union([z.literal("on"), z.literal("")])
  .optional()
  .transform((value) => value === "on");

export const briefTypeSchema = z.enum(BRIEF_TYPES, { error: "Choose a brief type." });

const serviceTypeCode = z
  .string()
  .trim()
  .regex(/^[a-z0-9_]{1,40}$/, { error: "Choose a type of service." });

// --- Project details ---------------------------------------------------------------

export const projectDetailsSchema = z.object({
  title: requiredText(200, "Give the project a title."),
  briefType: briefTypeSchema,
  serviceTypeCode,
  summary: optionalText(5000),
  deadline: optionalDate,
  /** "" = use the default for the brief type. */
  requiresInterpretation: z
    .enum(["", "yes", "no"])
    .transform((value) => (value === "" ? null : value === "yes")),
  proposedAmount: money,
  proposedCurrency: currencyCode,
  clientId: optionalUuid,
  clientPrice: money,
  clientPriceCurrency: currencyCode,
  internalNotes: optionalText(5000),
});
export type ProjectDetails = z.infer<typeof projectDetailsSchema>;

// --- Brief ---------------------------------------------------------------------------

export const briefTextSchema = z.object({
  instructions: optionalText(5000),
  desiredOutcome: optionalText(5000),
  audience: optionalText(2000),
  coreMessage: optionalText(2000),
  brandConstraints: optionalText(5000),
  mandatoryContent: optionalText(5000),
  prohibitedContent: optionalText(5000),
});

export const deliverableSchema = z.object({
  id: optionalUuid,
  name: requiredText(200, "Each deliverable needs a name."),
  format: optionalText(100),
  resolution: optionalText(100),
  aspectRatio: optionalText(50),
  durationSeconds: wholeNumber(0, 86_400, "Duration must be whole seconds."),
  notes: optionalText(2000),
});

export const referenceSchema = z
  .object({
    id: optionalUuid,
    title: requiredText(200, "Each reference needs a title."),
    url: httpsUrl,
    startSeconds: timecodeSeconds,
    endSeconds: timecodeSeconds,
    observationNotes: optionalText(2000),
    priority: z.enum(REFERENCE_PRIORITIES, { error: "Choose essential or optional." }),
    category: optionalText(80),
    accessNotes: optionalText(1000),
  })
  .refine(
    (r) => r.startSeconds === null || r.endSeconds === null || r.endSeconds >= r.startSeconds,
    { error: "The end time must not be before the start time.", path: ["endSeconds"] },
  )
  .refine((r) => r.endSeconds === null || r.startSeconds !== null, {
    error: "Add a start time when you set an end time.",
    path: ["startSeconds"],
  });

export const deliverablesSchema = z
  .array(deliverableSchema)
  .max(MAX_DELIVERABLES, { error: `Add at most ${MAX_DELIVERABLES} deliverables.` });
export const referencesSchema = z
  .array(referenceSchema)
  .max(MAX_REFERENCES, { error: `Add at most ${MAX_REFERENCES} references.` });

export const briefSchema = briefTextSchema.extend({
  deliverables: deliverablesSchema,
  references: referencesSchema,
});

export const saveBriefSchema = briefSchema.extend({
  projectId: z.uuid(),
  changeSummary: optionalText(1000),
  requiresReacknowledgement: checkbox,
});

/**
 * Create only: included revision rounds for terms v1 (the form pre-fills 3). Afterwards the rounds
 * change only by agreeing new project terms. null = left empty: the database default (3) applies.
 */
export const createProjectSchema = projectDetailsSchema.extend({
  ...briefSchema.shape,
  revisionAllowance: wholeNumber(0, 20, "Use a whole number from 0 to 20."),
});

export const updateProjectSchema = projectDetailsSchema.extend({ projectId: z.uuid() });

// --- Status and archive ----------------------------------------------------------------

export const projectStatusChangeSchema = z.object({
  projectId: z.uuid(),
  status: z.enum(["draft", "open", "on_hold", "cancelled"], {
    error: "That status change is not available here.",
  }),
});

export const archiveProjectSchema = z.object({
  projectId: z.uuid(),
  archive: z.enum(["true", "false"]).transform((value) => value === "true"),
});

// --- Clients -----------------------------------------------------------------------------

const clientShape = {
  name: requiredText(200, "Enter the contact name."),
  company: optionalText(200),
  email: z
    .string()
    .trim()
    .toLowerCase()
    .pipe(z.email({ error: "Enter a valid email address." }).max(254)),
  phone: optionalText(40),
  notes: optionalText(5000),
};

export const createClientSchema = z.object(clientShape);
export const updateClientSchema = z.object({
  clientId: z.uuid(),
  ...clientShape,
  archived: checkbox,
});

export const mergeClientsSchema = z
  .object({ sourceId: z.uuid(), targetId: z.uuid({ error: "Choose the client to keep." }) })
  .refine((v) => v.sourceId !== v.targetId, {
    error: "Choose a different client to keep.",
    path: ["targetId"],
  });

// --- Inquiry conversion --------------------------------------------------------------------

export const convertInquirySchema = z.object({
  inquiryId: z.uuid(),
  title: optionalText(200),
  briefType: briefTypeSchema,
  deadline: optionalDate,
  clientId: optionalUuid,
});

// --- FormData parsing ----------------------------------------------------------------------

function text(formData: FormData, name: string) {
  const value = formData.get(name);
  return typeof value === "string" ? value : "";
}

export const DELIVERABLE_FIELDS = [
  "id",
  "name",
  "format",
  "resolution",
  "aspectRatio",
  "durationSeconds",
  "notes",
] as const;
export const REFERENCE_FIELDS = [
  "id",
  "title",
  "url",
  "startSeconds",
  "endSeconds",
  "observationNotes",
  "priority",
  "category",
  "accessNotes",
] as const;

/**
 * Rows are submitted as parallel lists named `<prefix>.<field>` (one input per row per field).
 * Rows with nothing typed in them (ignoring id and priority) are dropped.
 */
function rowsFor(formData: FormData, prefix: string, fields: readonly string[]) {
  const lists = fields.map((f) =>
    formData.getAll(`${prefix}.${f}`).map((v) => (typeof v === "string" ? v : "")),
  );
  const count = Math.max(0, ...lists.map((l) => l.length));
  const out: Record<string, string>[] = [];
  for (let i = 0; i < count; i++) {
    const row = Object.fromEntries(fields.map((f, j) => [f, lists[j][i] ?? ""]));
    const meaningful = fields.some((f) => f !== "id" && f !== "priority" && row[f].trim() !== "");
    if (meaningful) out.push(row);
  }
  return out;
}

/** Project form fields only; client fields live on the client forms. */
export const PROJECT_FIELDS = [
  "title",
  "briefType",
  "serviceTypeCode",
  "summary",
  "deadline",
  "requiresInterpretation",
  "proposedAmount",
  "proposedCurrency",
  "revisionAllowance",
  "clientId",
  "clientPrice",
  "clientPriceCurrency",
  "internalNotes",
  "instructions",
  "desiredOutcome",
  "audience",
  "coreMessage",
  "brandConstraints",
  "mandatoryContent",
  "prohibitedContent",
  "changeSummary",
] as const;

export function projectFormInput(formData: FormData) {
  const flat: Record<string, string> = Object.fromEntries(
    PROJECT_FIELDS.map((f) => [f, text(formData, f)]),
  );
  return {
    ...flat,
    projectId: text(formData, "projectId"),
    requiresReacknowledgement: text(formData, "requiresReacknowledgement"),
    deliverables: rowsFor(formData, "deliverable", DELIVERABLE_FIELDS),
    references: rowsFor(formData, "reference", REFERENCE_FIELDS),
  };
}

/** Flat values to refill after a failed submit. Rows live in client state. */
export function projectKeptValues(formData: FormData): Record<string, string> {
  return Object.fromEntries(PROJECT_FIELDS.map((f) => [f, text(formData, f).slice(0, 5000)]));
}

// --- Database payloads (jsonb keys from the Phase 4 database plan) ----------------------------

type Brief = z.infer<typeof briefSchema>;

export function briefPayload(b: Brief) {
  return {
    brief: {
      instructions: b.instructions,
      desired_outcome: b.desiredOutcome,
      audience: b.audience,
      core_message: b.coreMessage,
      brand_constraints: b.brandConstraints,
      mandatory_content: b.mandatoryContent,
      prohibited_content: b.prohibitedContent,
    },
    deliverables: b.deliverables.map((d, i) => ({
      ...(d.id ? { id: d.id } : {}),
      name: d.name,
      format: d.format,
      resolution: d.resolution,
      aspect_ratio: d.aspectRatio,
      duration_seconds: d.durationSeconds,
      notes: d.notes,
      sort_order: i,
    })),
    references: b.references.map((r, i) => ({
      ...(r.id ? { id: r.id } : {}),
      title: r.title,
      url: r.url,
      start_seconds: r.startSeconds,
      end_seconds: r.endSeconds,
      observation_notes: r.observationNotes,
      priority: r.priority,
      category: r.category,
      access_notes: r.accessNotes,
      sort_order: i,
    })),
  };
}

export function detailsPayload(d: ProjectDetails & { revisionAllowance?: number | null }) {
  return {
    title: d.title,
    brief_type: d.briefType,
    service_type_code: d.serviceTypeCode,
    summary: d.summary,
    deadline: d.deadline,
    ...(d.requiresInterpretation === null
      ? {}
      : { requires_interpretation: d.requiresInterpretation }),
    proposed_amount: d.proposedAmount,
    proposed_currency: d.proposedCurrency,
    ...(d.revisionAllowance == null ? {} : { revision_allowance: d.revisionAllowance }),
    client_id: d.clientId,
    client_price: d.clientPrice,
    client_price_currency: d.clientPriceCurrency,
    internal_notes: d.internalNotes,
  };
}

// --- Project terms (Phase 12A) ---------------------------------------------------------------

export const TERMS_STAGES = ["assigned", "in_progress", "in_review", "revision_requested"] as const;
export type TermsStage = (typeof TERMS_STAGES)[number];

/** Percentage 0..100 with at most two decimals; empty = not set. */
const percent = z
  .string()
  .trim()
  .transform((value, ctx) => {
    if (value === "") return null;
    const n = Number(value);
    if (!/^\d{1,3}(\.\d{1,2})?$/.test(value) || n > 100) {
      ctx.addIssue({ code: "custom", message: "Use a percentage from 0 to 100." });
      return z.NEVER;
    }
    return n;
  });

const days = z
  .string()
  .trim()
  .transform((value, ctx) => {
    const n = Number(value);
    if (!/^\d{1,3}$/.test(value) || n > 365) {
      ctx.addIssue({ code: "custom", message: "Use a whole number of days from 0 to 365." });
      return z.NEVER;
    }
    return n;
  });

/** "50, 50" -> [50, 50]: 1 to 10 whole percentages from 1 to 100 that add up to 100. */
const editorShares = z
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
        message: "List 1 to 10 whole percentages, e.g. 50, 50.",
      });
      return z.NEVER;
    }
    if (nums.reduce((a, b) => a + b, 0) !== 100) {
      ctx.addIssue({ code: "custom", message: "The editor pay milestones must add up to 100%." });
      return z.NEVER;
    }
    return nums;
  });

const stagePair = z
  .object({ editor: percent, client: percent })
  .refine((s) => (s.editor === null) === (s.client === null), {
    error: "Enter both percentages for a cancellation stage, or leave both empty.",
  });

export const termsDraftSchema = z.object({
  projectId: z.uuid(),
  includedRounds: wholeNumber(0, 20, "Use a whole number from 0 to 20.").pipe(
    z.number({ error: "Enter the included revision rounds (0 to 20)." }),
  ),
  extraRoundCharge: money,
  chargeCurrency: currencyCode,
  depositDays: days,
  balanceDays: days,
  editorPayDays: days,
  lateBalanceDays: days,
  editorShares,
  stages: z.object(
    Object.fromEntries(TERMS_STAGES.map((s) => [s, stagePair])) as Record<
      TermsStage,
      typeof stagePair
    >,
  ),
  changeReason: optionalText(2000),
});
export type TermsDraft = z.infer<typeof termsDraftSchema>;

export const TERMS_FIELDS = [
  "includedRounds",
  "extraRoundCharge",
  "chargeCurrency",
  "depositDays",
  "balanceDays",
  "editorPayDays",
  "lateBalanceDays",
  "editorShares",
  "changeReason",
] as const;

export function termsFormInput(formData: FormData) {
  return {
    projectId: text(formData, "projectId"),
    ...Object.fromEntries(TERMS_FIELDS.map((f) => [f, text(formData, f)])),
    stages: Object.fromEntries(
      TERMS_STAGES.map((s) => [
        s,
        {
          editor: text(formData, `stage.${s}.editor`),
          client: text(formData, `stage.${s}.client`),
        },
      ]),
    ),
  };
}

/** Flat values to refill the terms form after a failed submit. */
export function termsKeptValues(formData: FormData): Record<string, string> {
  const names = [
    ...TERMS_FIELDS,
    ...TERMS_STAGES.flatMap((s) => [`stage.${s}.editor`, `stage.${s}.client`]),
  ];
  return Object.fromEntries(names.map((f) => [f, text(formData, f).slice(0, 2000)]));
}

export function termsPayload(t: TermsDraft) {
  return {
    included_rounds: t.includedRounds,
    extra_round_charge: t.extraRoundCharge,
    charge_currency: t.extraRoundCharge === null ? null : t.chargeCurrency,
    deposit_days: t.depositDays,
    balance_days: t.balanceDays,
    editor_pay_days: t.editorPayDays,
    late_balance_days: t.lateBalanceDays,
    editor_milestone_shares: t.editorShares,
    stages: TERMS_STAGES.flatMap((s) => {
      const v = t.stages[s];
      return v.editor === null || v.client === null
        ? []
        : [{ stage: s, editor_earned_percent: v.editor, client_charge_percent: v.client }];
    }),
    change_reason: t.changeReason,
  };
}

export const agreeTermsSchema = z.object({
  projectId: z.uuid(),
  version: z.coerce.number().int().min(1),
  changeReason: optionalText(2000),
});
