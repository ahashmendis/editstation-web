import "server-only";

import { createClient } from "@/lib/supabase/server";

import type { ProjectFilter } from "./constants";

function check<T>(result: { data: T | null; error: unknown }): T {
  if (result.error) throw result.error;
  if (result.data === null) throw new Error("Unexpected empty result");
  return result.data;
}

/** Admin project list (RLS: MFA admins only). */
export async function listProjects(filter: ProjectFilter) {
  const supabase = await createClient();
  let query = supabase
    .from("projects")
    .select(
      "id, title, brief_type, status, deadline, archived_at, current_brief_version, updated_at",
    )
    .order("updated_at", { ascending: false })
    .limit(200);
  if (filter === "archived") query = query.not("archived_at", "is", null);
  else {
    query = query.is("archived_at", null);
    if (filter === "active") query = query.neq("status", "cancelled");
    else if (filter !== "all") query = query.eq("status", filter);
  }
  return check(await query);
}

/** Options for project and conversion forms. */
export async function getProjectFormOptions() {
  const supabase = await createClient();
  const [services, clients] = await Promise.all([
    supabase.from("service_types").select("code, label, active").order("sort_order"),
    supabase
      .from("clients")
      .select("id, name, company, email")
      .is("merged_into_id", null)
      .is("archived_at", null)
      .order("name")
      .limit(200),
  ]);
  return { services: check(services), clients: check(clients) };
}

export async function getProjectDetail(projectId: string) {
  const supabase = await createClient();
  const { data: project, error } = await supabase
    .from("projects")
    .select("*")
    .eq("id", projectId)
    .maybeSingle();
  if (error) throw error;
  if (!project) return null;

  const [internal, versions, deliverables, references, activity] = await Promise.all([
    supabase
      .from("project_internal")
      .select("client_id, client_price, client_price_currency, internal_notes, source_inquiry_id")
      .eq("project_id", projectId)
      .maybeSingle(),
    supabase
      .from("brief_versions")
      .select("*")
      .eq("project_id", projectId)
      .order("version", { ascending: false }),
    supabase
      .from("project_deliverables")
      .select("*")
      .eq("project_id", projectId)
      .order("sort_order")
      .order("id"),
    supabase
      .from("project_references")
      .select("*")
      .eq("project_id", projectId)
      .order("sort_order")
      .order("id"),
    supabase
      .from("activity_logs")
      .select("id, action, created_at")
      .eq("entity_type", "project")
      .eq("entity_id", projectId)
      .order("created_at", { ascending: false })
      .limit(30),
  ]);
  if (internal.error) throw internal.error;

  const versionRows = check(versions);
  return {
    project,
    internal: internal.data,
    versions: versionRows,
    currentBrief: versionRows.find((v) => v.version === project.current_brief_version) ?? null,
    deliverables: check(deliverables),
    references: check(references),
    activity: check(activity),
  };
}

export async function listClients() {
  const supabase = await createClient();
  return check(
    await supabase
      .from("clients")
      .select("id, name, company, email, phone, notes, archived_at, merged_into_id")
      .order("name")
      .limit(500),
  );
}

/** For the inquiry page: the project an inquiry was converted into, if any. */
export async function getConvertedProject(projectId: string | null) {
  if (!projectId) return null;
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("projects")
    .select("id, title")
    .eq("id", projectId)
    .maybeSingle();
  if (error) throw error;
  return data;
}

/** One client for a select, even if archived or merged (so editing a project never drops it). */
export async function getClientOption(clientId: string) {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("clients")
    .select("id, name, company, email")
    .eq("id", clientId)
    .maybeSingle();
  if (error) throw error;
  return data;
}
