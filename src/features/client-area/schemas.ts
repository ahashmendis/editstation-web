import { z } from "zod";

import { emailSchema } from "@/features/authentication/schemas";

// ---------------------------------------------------------------------------
// Forms
// ---------------------------------------------------------------------------

export const requestCodeSchema = z.object({ email: emailSchema });

// Mirrors supabase/config.toml [auth.email] otp_length = 8.
export const verifyCodeSchema = z.object({
  email: emailSchema,
  code: z
    .string()
    .trim()
    .regex(/^\d{8}$/, { error: "Enter the 8-digit code from the email." }),
});

export const inviteClientUserSchema = z.object({
  clientId: z.uuid({ error: "Choose a client." }),
  email: emailSchema,
});

export const revokeClientUserSchema = z.object({
  clientUserId: z.uuid({ error: "Choose a client user." }),
});

export const publishUpdateSchema = z.object({
  projectId: z.uuid({ error: "Choose a project." }),
  body: z
    .string()
    .trim()
    .min(1, { error: "Write the update first." })
    .max(5000, { error: "Keep the update to 5000 characters or fewer." }),
});

export const withdrawUpdateSchema = z.object({
  projectId: z.uuid({ error: "Choose a project." }),
  updateId: z.uuid({ error: "Choose an update." }),
});

export const bankDetailsSchema = z.object({
  details: z
    .string()
    .trim()
    .max(2000, { error: "Keep the bank details to 2000 characters or fewer." }),
});

// ---------------------------------------------------------------------------
// Database function results (client-safe projections). Unknown keys are dropped by Zod, so the
// app can never render a field the projection did not promise.
// ---------------------------------------------------------------------------

const milestone = z.object({
  id: z.string(),
  seq: z.number(),
  kind: z.string(),
  amount: z.number(),
  currency: z.string(),
  due_date: z.string().nullable(),
  invoice_issued_at: z.string().nullable(),
  received_at: z.string().nullable(),
  payment_status: z.string(),
});
export type ClientMilestone = z.infer<typeof milestone>;

export const clientProjectSchema = z.object({
  id: z.string(),
  title: z.string(),
  client_status: z.string(),
  created_at: z.string(),
  deliverables: z.array(
    z.object({
      name: z.string(),
      format: z.string().nullable(),
      resolution: z.string().nullable(),
      aspect_ratio: z.string().nullable(),
      duration_seconds: z.number().nullable(),
    }),
  ),
  updates: z.array(z.object({ id: z.string(), body: z.string(), published_at: z.string() })),
  milestones: z.array(milestone),
});
export type ClientProject = z.infer<typeof clientProjectSchema>;

export const clientPaymentInfoSchema = z.object({
  bank_details: z.string().nullable(),
  projects: z.array(
    z.object({ project_id: z.string(), title: z.string(), milestones: z.array(milestone) }),
  ),
});
export type ClientPaymentInfo = z.infer<typeof clientPaymentInfoSchema>;

export const adminClientUpdatesSchema = z.object({
  client_status: z.string(),
  has_client: z.boolean(),
  visible_to_client: z.boolean(),
  active_client_users: z.number(),
  updates: z.array(
    z.object({
      id: z.string(),
      body: z.string(),
      published: z.boolean(),
      created_at: z.string(),
      withdrawn_at: z.string().nullable(),
    }),
  ),
});
export type AdminClientUpdates = z.infer<typeof adminClientUpdatesSchema>;
