import { z } from "zod";

import { MAX_PORTFOLIO_LINKS } from "./constants";

const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max, { error: `Use at most ${max} characters.` })
    .transform((value) => (value === "" ? null : value));

export const httpsUrl = z
  .string()
  .trim()
  .max(2048)
  .refine(
    (value) => {
      try {
        const url = new URL(value);
        return url.protocol === "https:" && !/\s/.test(value);
      } catch {
        return false;
      }
    },
    { error: "Use a full link starting with https://" },
  );

const portfolioLink = z.object({
  url: httpsUrl,
  label: optionalText(120),
});

/** The editor profile form. Drafts may be partial; the database checks completeness on submit. */
export const editorProfileSchema = z.object({
  fullName: optionalText(200),
  phone: optionalText(40),
  region: optionalText(120),
  experienceYears: z
    .string()
    .trim()
    .transform((value, ctx) => {
      if (value === "") return null;
      const years = Number(value);
      if (!Number.isInteger(years) || years < 0 || years > 60) {
        ctx.addIssue({ code: "custom", message: "Enter a whole number from 0 to 60." });
        return z.NEVER;
      }
      return years;
    }),
  experienceSummary: optionalText(2000),
  availability: optionalText(500),
  typicalTurnaround: optionalText(200),
  hardware: optionalText(500),
  softwareOther: optionalText(200),
  specialisations: z.array(z.string().regex(/^[a-z0-9_]{1,40}$/)).max(20),
  software: z.array(z.string().regex(/^[a-z0-9_]{1,40}$/)).max(20),
  links: z
    .array(portfolioLink)
    .max(MAX_PORTFOLIO_LINKS, { error: `Add at most ${MAX_PORTFOLIO_LINKS} links.` }),
});

export type EditorProfileInput = z.infer<typeof editorProfileSchema>;

/** Read the profile form's FormData into the schema's input shape. */
export function profileFormInput(formData: FormData) {
  const text = (name: string) => {
    const value = formData.get(name);
    return typeof value === "string" ? value : "";
  };
  const urls = formData.getAll("linkUrl").map(String);
  const labels = formData.getAll("linkLabel").map(String);
  return {
    fullName: text("fullName"),
    phone: text("phone"),
    region: text("region"),
    experienceYears: text("experienceYears"),
    experienceSummary: text("experienceSummary"),
    availability: text("availability"),
    typicalTurnaround: text("typicalTurnaround"),
    hardware: text("hardware"),
    softwareOther: text("softwareOther"),
    specialisations: formData.getAll("specialisations").map(String),
    software: formData.getAll("software").map(String),
    links: urls
      .map((url, i) => ({ url, label: labels[i] ?? "" }))
      .filter((link) => link.url.trim() !== "" || link.label.trim() !== ""),
  };
}

export const requestResponseSchema = z
  .object({
    requestId: z.uuid(),
    response: optionalText(4000),
    responseLink: z
      .string()
      .trim()
      .transform((value) => (value === "" ? null : value))
      .pipe(httpsUrl.nullable()),
  })
  .refine((data) => data.response !== null || data.responseLink !== null, {
    error: "Add a response or a link.",
    path: ["response"],
  });

// --- Admin forms -------------------------------------------------------------

const requiredText = (max: number, message: string) =>
  z
    .string()
    .trim()
    .min(1, { error: message })
    .max(max, { error: `Use at most ${max} characters.` });

export const applicationIdSchema = z.object({ applicationId: z.uuid() });

export const createRequestSchema = z.object({
  applicationId: z.uuid(),
  kind: z.enum(["info", "test"]),
  message: requiredText(4000, "Write what you need from the applicant."),
});

export const assessmentSchema = z.object({
  requestId: z.uuid(),
  result: z.enum(["passed", "failed", "inconclusive"]),
  notes: optionalText(4000),
});

export const approveSchema = z.object({
  applicationId: z.uuid(),
  level: z.enum(["junior", "professional", "specialist"], { error: "Choose an initial level." }),
  message: optionalText(2000),
});

export const rejectSchema = z.object({
  applicationId: z.uuid(),
  message: optionalText(2000),
});

export const vettingNoteSchema = z.object({
  applicationId: z.uuid(),
  note: requiredText(4000, "Write a note."),
});

export const reopenSchema = z.object({ editorId: z.uuid() });

export const editorAccessSchema = z.object({
  editorId: z.uuid(),
  status: z.enum(["active", "suspended", "revoked"]),
  reason: requiredText(1000, "Give a reason."),
});
