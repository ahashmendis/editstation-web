import { z } from "zod";

import { httpsUrl } from "@/features/applications/schemas";

import {
  ACCESS_REASONS,
  ASSET_ACCESS_TYPES,
  ASSET_PROVIDERS,
  MAX_ASSETS,
  MAX_INVITES,
  RESPOND_ACTIONS,
} from "./constants";

// Optional fields may be absent from a form (e.g. accept/decline send no amount): absent = empty.
const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max, { error: `Use at most ${max} characters.` })
    .optional()
    .transform((value) => (value === undefined || value === "" ? null : value));

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

/** Pay: a positive amount with at most 2 decimals. Empty is "not given". */
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

/** Empty means "keep the project's or the offer's currency". */
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

const message = optionalText(2000);

// --- Assets ------------------------------------------------------------------------------------

export const assetProviderSchema = z.enum(ASSET_PROVIDERS, { error: "Choose a provider." });

export const assetRowSchema = z.object({
  id: optionalUuid,
  label: requiredText(200, "Each asset needs a label."),
  url: httpsUrl,
  provider: assetProviderSchema,
  kind: optionalText(40),
  notes: optionalText(2000),
  description: optionalText(2000),
  accessInstructions: optionalText(2000),
});

export const assetsSchema = z
  .array(assetRowSchema)
  .max(MAX_ASSETS, { error: `Add at most ${MAX_ASSETS} assets.` });

export const saveAssetsSchema = z.object({ projectId: z.uuid(), assets: assetsSchema });

export const ASSET_FIELDS = [
  "id",
  "label",
  "url",
  "provider",
  "kind",
  "notes",
  "description",
  "accessInstructions",
] as const;

/**
 * Rows are submitted as parallel lists named `asset.<field>`. Rows with nothing typed in them
 * (ignoring id and provider) are dropped.
 */
export function assetRowsFromForm(formData: FormData) {
  const lists = ASSET_FIELDS.map((f) =>
    formData.getAll(`asset.${f}`).map((v) => (typeof v === "string" ? v : "")),
  );
  const count = Math.max(0, ...lists.map((l) => l.length));
  const rows: Record<string, string>[] = [];
  for (let i = 0; i < count; i++) {
    const row = Object.fromEntries(ASSET_FIELDS.map((f, j) => [f, lists[j][i] ?? ""]));
    const meaningful = ASSET_FIELDS.some(
      (f) => f !== "id" && f !== "provider" && row[f].trim() !== "",
    );
    if (meaningful) rows.push(row);
  }
  return rows;
}

export function assetsPayload(assets: z.infer<typeof assetsSchema>) {
  return assets.map((a, i) => ({
    ...(a.id ? { id: a.id } : {}),
    label: a.label,
    url: a.url,
    provider: a.provider,
    kind: a.kind,
    notes: a.notes,
    description: a.description,
    access_instructions: a.accessInstructions,
    sort_order: i,
  }));
}

// --- Early access ------------------------------------------------------------------------------

export const earlyAccessSchema = z.object({
  projectId: z.uuid(),
  targetId: z.uuid(),
  target: z.enum(["reference", "asset"]),
  value: z.enum(["true", "false"]).transform((v) => v === "true"),
});

// --- Project access and offers ------------------------------------------------------------------

export const grantAccessSchema = z.object({
  projectId: z.uuid(),
  editorIds: z
    .array(z.uuid())
    .min(1, { error: "Choose at least one editor." })
    .max(MAX_INVITES, { error: `Choose at most ${MAX_INVITES} editors at once.` }),
  reason: z.enum(ACCESS_REASONS, { error: "Choose why they are being invited." }),
});

export function grantAccessInput(formData: FormData) {
  return {
    projectId: formData.get("projectId"),
    editorIds: Array.from(new Set(formData.getAll("editorIds").map(String))),
    reason: formData.get("reason"),
  };
}

export const revokeAccessSchema = z.object({ projectId: z.uuid(), editorId: z.uuid() });

export const makeOfferSchema = z.object({
  projectId: z.uuid(),
  editorId: z.uuid(),
  amount: optionalAmount.refine((v) => v !== null, { error: "Enter the amount you are offering." }),
  currency: optionalCurrency,
  message,
});

/** Admin answering a counteroffer, or an editor answering an offer. */
export const respondSchema = z
  .object({
    projectId: z.uuid(),
    assignmentId: z.uuid(),
    action: z.enum(RESPOND_ACTIONS, { error: "Choose accept, counter or decline." }),
    amount: optionalAmount,
    currency: optionalCurrency,
    message,
  })
  .refine((v) => v.action !== "counter" || v.amount !== null, {
    error: "Enter the amount you are proposing.",
    path: ["amount"],
  });

export const withdrawOfferSchema = z.object({
  projectId: z.uuid(),
  assignmentId: z.uuid(),
  message,
});

export const confirmAssignmentSchema = z.object({
  projectId: z.uuid(),
  assignmentId: z.uuid(),
});

export const reassignSchema = z.object({
  projectId: z.uuid(),
  assignmentId: z.uuid(),
  message,
});

// --- Folder shares -----------------------------------------------------------------------------

export const recordGrantSchema = z.object({
  projectId: z.uuid(),
  editorId: z.uuid({ error: "Choose an editor." }),
  email: z
    .string()
    .trim()
    .toLowerCase()
    .pipe(z.email({ error: "Enter the email the folder was shared with." }).max(254)),
  provider: assetProviderSchema,
  accessType: z.enum(ASSET_ACCESS_TYPES, { error: "Choose how the folder is shared." }),
  folderUrl: z
    .string()
    .trim()
    .transform((v) => (v === "" ? null : v))
    .pipe(httpsUrl.nullable()),
});

/** Request or confirm removal of a share; projectId is empty on the access review page. */
export const grantRemovalSchema = z.object({
  grantId: z.uuid(),
  projectId: optionalUuid,
});

// --- Asset access (KB7, KB7a) ------------------------------------------------------------------

export const assetActionSchema = z.object({ projectId: z.uuid(), assetId: z.uuid() });

export const reportAssetSchema = z.object({
  projectId: z.uuid(),
  assetId: z.uuid(),
  note: requiredText(1000, "Say what happens when you try to open it."),
});

export const resolveReportSchema = z.object({ projectId: z.uuid(), reportId: z.uuid() });

// --- Notes -------------------------------------------------------------------------------------

export const addNoteSchema = z.object({
  projectId: z.uuid(),
  note: requiredText(4000, "Write a note first."),
});
