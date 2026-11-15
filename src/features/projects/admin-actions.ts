"use server";

import { refresh, revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { userMessageFromDbError } from "@/features/applications/db-errors";
import { validationError, type FormState } from "@/features/authentication/schemas";
import { requireAdmin } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

import {
  agreeTermsSchema,
  archiveProjectSchema,
  briefPayload,
  convertInquirySchema,
  createClientSchema,
  createProjectSchema,
  detailsPayload,
  mergeClientsSchema,
  projectFormInput,
  projectKeptValues,
  projectStatusChangeSchema,
  saveBriefSchema,
  termsDraftSchema,
  termsFormInput,
  termsKeptValues,
  termsPayload,
  updateClientSchema,
  updateProjectSchema,
} from "./schemas";

type Failure = { code: string; message: string };

function failed(error: Failure, values?: FormState["values"]): FormState {
  return { status: "error", message: userMessageFromDbError(error), values };
}

function done(message: string): FormState {
  refresh();
  return { status: "success", message };
}

function projectPaths(projectId?: string) {
  revalidatePath("/admin/projects");
  if (projectId) revalidatePath(`/admin/projects/${projectId}`);
}

function clientPayload(c: {
  name: string;
  company: string | null;
  email: string;
  phone: string | null;
  notes: string | null;
}) {
  return { name: c.name, company: c.company, email: c.email, phone: c.phone, notes: c.notes };
}

/** Create a project with its first brief version, then open its page. */
export async function createProjectAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = createProjectSchema.safeParse(projectFormInput(formData));
  if (!parsed.success) return validationError(parsed.error, projectKeptValues(formData));
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_create_project", {
    p_input: { ...detailsPayload(parsed.data), ...briefPayload(parsed.data) },
  });
  if (error) return failed(error, projectKeptValues(formData));
  projectPaths();
  redirect(`/admin/projects/${data}`);
}

/** Edit project details. Never creates a brief version. */
export async function updateProjectAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = updateProjectSchema.safeParse(projectFormInput(formData));
  if (!parsed.success) return validationError(parsed.error, projectKeptValues(formData));
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_update_project", {
    p_project_id: parsed.data.projectId,
    p_input: detailsPayload(parsed.data),
  });
  if (error) return failed(error, projectKeptValues(formData));
  projectPaths(parsed.data.projectId);
  return done("Details saved.");
}

/** Save the brief, deliverables and references. The database decides whether this is a new version. */
export async function saveBriefAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = saveBriefSchema.safeParse(projectFormInput(formData));
  if (!parsed.success) return validationError(parsed.error, projectKeptValues(formData));
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_save_brief", {
    p_project_id: parsed.data.projectId,
    p_input: {
      ...briefPayload(parsed.data),
      change_summary: parsed.data.changeSummary,
      requires_reacknowledgement: parsed.data.requiresReacknowledgement,
    },
  });
  if (error) return failed(error, projectKeptValues(formData));
  projectPaths(parsed.data.projectId);
  return done(`Brief saved. Current version: ${data}.`);
}

export async function setProjectStatusAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = projectStatusChangeSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_project_status", {
    p_project_id: parsed.data.projectId,
    p_status: parsed.data.status,
  });
  if (error) return failed(error);
  projectPaths(parsed.data.projectId);
  return done("Status updated.");
}

export async function archiveProjectAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = archiveProjectSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_archive_project", {
    p_project_id: parsed.data.projectId,
    p_archive: parsed.data.archive,
  });
  if (error) return failed(error);
  projectPaths(parsed.data.projectId);
  return done(parsed.data.archive ? "Project archived." : "Project restored.");
}

// --- Project terms (Phase 12A) ----------------------------------------------------------------

/** Save the terms draft (starts the next version when the latest one is agreed). */
export async function saveTermsDraftAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = termsDraftSchema.safeParse(termsFormInput(formData));
  if (!parsed.success) return validationError(parsed.error, termsKeptValues(formData));
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_save_terms_draft", {
    p_project_id: parsed.data.projectId,
    p_input: termsPayload(parsed.data),
  });
  if (error) return failed(error, termsKeptValues(formData));
  projectPaths(parsed.data.projectId);
  return done("Terms draft saved. Agree it to make it the project's terms.");
}

/** Agree a draft version. The database refuses a version that is no longer the draft. */
export async function agreeTermsAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  // The reason box exists only for version 2 and later.
  const parsed = agreeTermsSchema.safeParse({ changeReason: "", ...Object.fromEntries(formData) });
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_agree_terms", {
    p_project_id: parsed.data.projectId,
    p_version: parsed.data.version,
    ...(parsed.data.changeReason ? { p_change_reason: parsed.data.changeReason } : {}),
  });
  if (error) return failed(error);
  projectPaths(parsed.data.projectId);
  return done(`Terms version ${parsed.data.version} agreed.`);
}

// --- Clients -------------------------------------------------------------------------------

export async function createClientAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = createClientSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error, projectKeptValues(formData));
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_create_client", {
    p_input: clientPayload(parsed.data),
  });
  if (error) return failed(error, projectKeptValues(formData));
  revalidatePath("/admin/clients");
  return done("Client added.");
}

export async function updateClientAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = updateClientSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_update_client", {
    p_client_id: parsed.data.clientId,
    p_input: { ...clientPayload(parsed.data), archived: parsed.data.archived },
  });
  if (error) return failed(error);
  revalidatePath("/admin/clients");
  return done("Client saved.");
}

export async function mergeClientsAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = mergeClientsSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_merge_clients", {
    p_source: parsed.data.sourceId,
    p_target: parsed.data.targetId,
  });
  if (error) return failed(error);
  revalidatePath("/admin/clients");
  return done("Clients merged.");
}

// --- Inquiry conversion --------------------------------------------------------------------

/** Turn a confirmed inquiry into a draft project. Only an admin does this, never automatically. */
export async function convertInquiryAction(_prev: FormState, formData: FormData) {
  await requireAdmin();
  const parsed = convertInquirySchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return validationError(parsed.error);
  const v = parsed.data;
  // Only send what the admin set; the database fills the rest from the inquiry.
  const input = {
    brief_type: v.briefType,
    ...(v.title ? { title: v.title } : {}),
    ...(v.deadline ? { deadline: v.deadline } : {}),
    ...(v.clientId ? { client_id: v.clientId } : {}),
  };
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_convert_inquiry", {
    p_inquiry_id: v.inquiryId,
    p_input: input,
  });
  if (error) return failed(error);
  revalidatePath("/admin/inquiries");
  revalidatePath(`/admin/inquiries/${v.inquiryId}`);
  projectPaths();
  redirect(`/admin/projects/${data}`);
}
