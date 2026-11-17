"use server";

import { refresh, revalidatePath } from "next/cache";

import { userMessageFromDbError } from "@/features/applications/db-errors";
import { validationError, type FormState } from "@/features/authentication/schemas";
import { requireAdmin } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";

import {
  bankDetailsSchema,
  inviteClientUserSchema,
  publishUpdateSchema,
  revokeClientUserSchema,
  withdrawUpdateSchema,
} from "./schemas";

type Failure = { code: string; message: string };

function failed(error: Failure, values?: FormState["values"]): FormState {
  return { status: "error", message: userMessageFromDbError(error), values };
}

function done(message: string, path: string): FormState {
  revalidatePath(path);
  refresh();
  return { status: "success", message };
}

/**
 * Invite a client user (design "Accounts and sign-in"). Chosen over Supabase's invite API: the
 * account is created server-side with the service key (confirmed email, no password anyone
 * knows, so no password sign-in exists and no emailed invite link can be replayed); the person then signs in
 * at /client/sign-in with a one-time code sent to that mailbox. The database function then
 * authorises the admin (MFA) and links the account, refusing admins, editors, applicants and
 * self-registered accounts. If it refuses, an account created here is deleted again.
 */
export async function inviteClientUserAction(
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  await requireAdmin();
  const parsed = inviteClientUserSchema.safeParse(Object.fromEntries(formData));
  const values = { email: String(formData.get("email") ?? "").slice(0, 254) };
  if (!parsed.success) return validationError(parsed.error, values);

  let service: ReturnType<typeof createServiceClient>;
  try {
    service = createServiceClient();
  } catch {
    // Deployment configuration, not a database error: say what is missing, never the key.
    return {
      status: "error",
      message: "Client invitations are not set up on this server yet (secret key missing).",
      values,
    };
  }
  let createdUserId: string | null = null;
  // No password is given (Supabase stores a random one nobody knows). app_metadata can be set
  // only with the service key; the database links only accounts carrying this flag.
  const created = await service.auth.admin.createUser({
    email: parsed.data.email,
    email_confirm: true,
    app_metadata: { client_invite: true },
  });
  if (created.data.user) {
    createdUserId = created.data.user.id;
  } else if (created.error && created.error.code !== "email_exists") {
    return { status: "error", message: "Something went wrong. Please try again.", values };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_invite_client_user", {
    p_client_id: parsed.data.clientId,
    p_email: parsed.data.email,
  });
  if (error) {
    if (createdUserId) {
      const rollback = await service.auth.admin.deleteUser(createdUserId);
      // Server log only: ids and codes, never the email or a key. An orphan account has no access
      // (no client_users row, no known password) but should be removed in Supabase Auth.
      if (rollback.error) {
        console.error("client invite: rollback of the new auth account failed", {
          userId: createdUserId,
          code: rollback.error.code ?? rollback.error.status,
        });
      }
    }
    return failed(error, values);
  }
  return done(
    `Client access added. Ask them to sign in at /client/sign-in with ${parsed.data.email}; they will get a one-time code by email.`,
    "/admin/clients",
  );
}

export async function revokeClientUserAction(
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  await requireAdmin();
  const parsed = revokeClientUserSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_revoke_client_user", {
    p_client_user_id: parsed.data.clientUserId,
  });
  if (error) return failed(error);
  return done("Client access removed. It stops working on their next request.", "/admin/clients");
}

export async function publishClientUpdateAction(
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  await requireAdmin();
  const parsed = publishUpdateSchema.safeParse(Object.fromEntries(formData));
  const values = { body: String(formData.get("body") ?? "").slice(0, 5000) };
  if (!parsed.success) return validationError(parsed.error, values);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_publish_client_update", {
    p_project_id: parsed.data.projectId,
    p_body: parsed.data.body,
  });
  if (error) return failed(error, values);
  return done("Update published to the client.", `/admin/projects/${parsed.data.projectId}`);
}

export async function withdrawClientUpdateAction(
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  await requireAdmin();
  const parsed = withdrawUpdateSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_withdraw_client_update", {
    p_update_id: parsed.data.updateId,
  });
  if (error) return failed(error);
  return done(
    "Update withdrawn. The client no longer sees it.",
    `/admin/projects/${parsed.data.projectId}`,
  );
}

export async function setBankDetailsAction(
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  await requireAdmin();
  const parsed = bankDetailsSchema.safeParse(Object.fromEntries(formData));
  const values = { details: String(formData.get("details") ?? "").slice(0, 2000) };
  if (!parsed.success) return validationError(parsed.error, values);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_bank_details", {
    p_details: parsed.data.details,
  });
  if (error) return failed(error, values);
  return done(
    parsed.data.details === ""
      ? "Bank details cleared. Clients no longer see a bank details panel."
      : "Bank details saved. Clients see them on their Payments page.",
    "/admin/settings",
  );
}
