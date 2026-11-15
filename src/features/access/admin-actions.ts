"use server";

import { refresh, revalidatePath } from "next/cache";

import { userMessageFromDbError } from "@/features/applications/db-errors";
import { validationError, type FormState } from "@/features/authentication/schemas";
import { requireAdmin } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

import {
  addNoteSchema,
  assetActionSchema,
  assetRowsFromForm,
  assetsPayload,
  confirmAssignmentSchema,
  earlyAccessSchema,
  grantAccessInput,
  grantAccessSchema,
  grantRemovalSchema,
  makeOfferSchema,
  reassignSchema,
  recordGrantSchema,
  resolveReportSchema,
  respondSchema,
  revokeAccessSchema,
  saveAssetsSchema,
  withdrawOfferSchema,
} from "./schemas";

type Failure = { code: string; message: string };

function failed(error: Failure, values?: FormState["values"]): FormState {
  return { status: "error", message: userMessageFromDbError(error), values };
}

function done(message: string): FormState {
  refresh();
  return { status: "success", message };
}

function projectPaths(projectId: string) {
  revalidatePath("/admin/projects");
  revalidatePath(`/admin/projects/${projectId}`);
  revalidatePath("/admin/access-review");
}

/** Optional text parameters are left out when empty (the database default is null). */
const opt = <K extends string>(key: K, value: string | null) =>
  (value === null ? {} : { [key]: value }) as { [P in K]?: string };

// --- Assets and early access ---------------------------------------------------------------

export async function saveAssetsAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = saveAssetsSchema.safeParse({
    projectId: formData.get("projectId"),
    assets: assetRowsFromForm(formData),
  });
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_save_assets", {
    p_project_id: parsed.data.projectId,
    p_items: assetsPayload(parsed.data.assets),
  });
  if (error) return failed(error);
  projectPaths(parsed.data.projectId);
  return done("Assets saved.");
}

export async function setEarlyAccessAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = earlyAccessSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const v = parsed.data;
  const supabase = await createClient();
  const { error } =
    v.target === "reference"
      ? await supabase.rpc("admin_set_reference_early_access", {
          p_reference_id: v.targetId,
          p_value: v.value,
        })
      : await supabase.rpc("admin_set_asset_early_access", {
          p_asset_id: v.targetId,
          p_value: v.value,
        });
  if (error) return failed(error);
  projectPaths(v.projectId);
  return done(v.value ? "Shown in the opportunity summary." : "Hidden from the summary.");
}

// --- Editors: access ---------------------------------------------------------------------------

export async function grantAccessAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = grantAccessSchema.safeParse(grantAccessInput(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_grant_project_access", {
    p_project_id: parsed.data.projectId,
    p_editor_ids: parsed.data.editorIds,
    p_reason: parsed.data.reason,
  });
  if (error) return failed(error);
  projectPaths(parsed.data.projectId);
  const added = Number(data ?? 0);
  return done(
    added === 0
      ? "Those editors already had access."
      : `${added} ${added === 1 ? "editor" : "editors"} invited.`,
  );
}

export async function revokeAccessAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = revokeAccessSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_revoke_project_access", {
    p_project_id: parsed.data.projectId,
    p_editor_id: parsed.data.editorId,
  });
  if (error) return failed(error);
  projectPaths(parsed.data.projectId);
  return done("Access removed.");
}

// --- Editors: offers and negotiation -------------------------------------------------------

export async function makeOfferAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = makeOfferSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, keptOfferValues(formData));
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_make_offer", {
    p_project_id: v.projectId,
    p_editor_id: v.editorId,
    p_amount: v.amount as number,
    ...opt("p_currency", v.currency),
    ...opt("p_message", v.message),
  });
  if (error) return failed(error, keptOfferValues(formData));
  projectPaths(v.projectId);
  return done("Offer sent.");
}

function keptOfferValues(formData: FormData): FormState["values"] {
  const pick = (name: string) => {
    const value = formData.get(name);
    return typeof value === "string" ? value.slice(0, 2000) : "";
  };
  return { amount: pick("amount"), currency: pick("currency"), message: pick("message") };
}

/** The admin's answer to an editor's counteroffer: accept, counter or decline. */
export async function respondCounterAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = respondSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, keptOfferValues(formData));
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_respond_counter", {
    p_assignment_id: v.assignmentId,
    p_action: v.action,
    ...(v.action === "counter" && v.amount !== null ? { p_amount: v.amount } : {}),
    ...(v.action === "counter" ? opt("p_currency", v.currency) : {}),
    ...opt("p_message", v.message),
  });
  if (error) return failed(error, keptOfferValues(formData));
  projectPaths(v.projectId);
  return done(
    v.action === "accept"
      ? "Counteroffer accepted."
      : v.action === "counter"
        ? "New offer sent."
        : "Counteroffer declined.",
  );
}

export async function withdrawOfferAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = withdrawOfferSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_withdraw_offer", {
    p_assignment_id: parsed.data.assignmentId,
    ...opt("p_message", parsed.data.message),
  });
  if (error) return failed(error);
  projectPaths(parsed.data.projectId);
  return done("Offer withdrawn.");
}

export async function confirmAssignmentAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = confirmAssignmentSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_confirm_assignment", {
    p_assignment_id: parsed.data.assignmentId,
  });
  if (error) return failed(error);
  projectPaths(parsed.data.projectId);
  return done("Assignment confirmed.");
}

export async function reassignAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = reassignSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_reassign", {
    p_assignment_id: parsed.data.assignmentId,
    ...opt("p_message", parsed.data.message),
  });
  if (error) return failed(error);
  projectPaths(parsed.data.projectId);
  return done("Editor removed. The project is open again.");
}

// --- Folder shares -----------------------------------------------------------------------------

export async function recordGrantAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = recordGrantSchema.safeParse(Object.fromEntries(formData));
  const kept = () => ({
    email: String(formData.get("email") ?? "").slice(0, 254),
    folderUrl: String(formData.get("folderUrl") ?? "").slice(0, 2048),
    accessType: String(formData.get("accessType") ?? "").slice(0, 40),
  });
  if (!parsed.success) return validationError(parsed.error, kept());
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_record_asset_grant", {
    p_project_id: v.projectId,
    p_editor_id: v.editorId,
    p_email: v.email,
    p_provider: v.provider,
    p_access_type: v.accessType,
    ...opt("p_folder_url", v.folderUrl),
  });
  if (error) return failed(error, kept());
  projectPaths(v.projectId);
  return done("Share recorded.");
}

/** KB7a-2: the client removes the editor's access; the admin records the request... */
export async function requestRemovalAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = grantRemovalSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_request_access_removal", {
    p_grant_id: parsed.data.grantId,
  });
  if (error) return failed(error);
  if (parsed.data.projectId) projectPaths(parsed.data.projectId);
  else revalidatePath("/admin/access-review");
  return done("Removal request recorded.");
}

/** ...and then the client's confirmation that the access is gone. */
export async function confirmRemovalAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = grantRemovalSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_confirm_access_removal", {
    p_grant_id: parsed.data.grantId,
  });
  if (error) return failed(error);
  if (parsed.data.projectId) projectPaths(parsed.data.projectId);
  else revalidatePath("/admin/access-review");
  return done("Removal confirmed. The share is closed.");
}

// --- Asset access (KB7, KB7a) ------------------------------------------------------------------

export async function verifyAssetAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = assetActionSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_verify_asset", { p_asset_id: parsed.data.assetId });
  if (error) return failed(error);
  projectPaths(parsed.data.projectId);
  return done("Asset access verified.");
}

export async function resolveReportAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = resolveReportSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_resolve_asset_report", {
    p_report_id: parsed.data.reportId,
  });
  if (error) return failed(error);
  projectPaths(parsed.data.projectId);
  return done("Report resolved.");
}

// --- Notes -------------------------------------------------------------------------------------

export async function addNoteAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = addNoteSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) {
    return validationError(parsed.error, {
      note: String(formData.get("note") ?? "").slice(0, 4000),
    });
  }
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_add_project_note", {
    p_project_id: parsed.data.projectId,
    p_note: parsed.data.note,
  });
  if (error) return failed(error, { note: parsed.data.note });
  projectPaths(parsed.data.projectId);
  return done("Note added.");
}
