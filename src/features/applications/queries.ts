import "server-only";

import { createClient } from "@/lib/supabase/server";

import { OPEN_STATUSES, type ApplicationStatus } from "./constants";

/** Throw on error. Lists and .single() always return data when there is no error. */
function check<T>(result: { data: T | null; error: unknown }): T {
  if (result.error) throw result.error;
  if (result.data === null) throw new Error("Unexpected empty result");
  return result.data;
}

/** Everything the applicant area needs, for the signed-in user only (RLS). */
export async function getApplicantView(userId: string) {
  const supabase = await createClient();

  const [profile, editor, options, selected, links, applications] = await Promise.all([
    supabase.from("profiles").select("full_name, phone, email").eq("id", userId).single(),
    supabase
      .from("editor_profiles")
      .select(
        "access_status, region, experience_years, experience_summary, availability, typical_turnaround, hardware, software_other",
      )
      .eq("user_id", userId)
      .single(),
    supabase.from("profile_options").select("kind, code, label").order("sort_order"),
    supabase.from("editor_profile_options").select("kind, code").eq("editor_id", userId),
    supabase
      .from("editor_portfolio_links")
      .select("url, label")
      .eq("editor_id", userId)
      .order("created_at"),
    supabase
      .from("editor_applications")
      .select("id, attempt, status, submitted_at, submitted_snapshot, decided_at, decision_message")
      .eq("editor_id", userId)
      .order("attempt", { ascending: false }),
  ]);

  const apps = check(applications);
  const latest = apps[0] ?? null;
  const requests = latest
    ? check(
        await supabase
          .from("application_requests")
          .select("id, kind, message, requested_at, response, response_link, responded_at")
          .eq("application_id", latest.id)
          .order("requested_at"),
      )
    : [];

  return {
    profile: check(profile),
    editor: check(editor),
    options: check(options),
    selected: check(selected),
    links: check(links),
    latest,
    requests,
  };
}

export type ApplicationFilter = "open" | "decided" | "drafts" | "all";

const FILTER_STATUSES: Record<ApplicationFilter, ApplicationStatus[] | null> = {
  open: OPEN_STATUSES,
  decided: ["approved", "rejected", "withdrawn"],
  drafts: ["draft"],
  all: null,
};

/** Admin list. RLS returns rows only to an MFA-verified admin. */
export async function listApplications(filter: ApplicationFilter) {
  const supabase = await createClient();
  let query = supabase
    .from("editor_applications")
    .select("id, editor_id, attempt, status, submitted_at, created_at")
    .order("submitted_at", { ascending: false, nullsFirst: false })
    .order("created_at", { ascending: false })
    .limit(200);
  const statuses = FILTER_STATUSES[filter];
  if (statuses) query = query.in("status", statuses);
  const apps = check(await query);

  const ids = [...new Set(apps.map((a) => a.editor_id))];
  const people = ids.length
    ? check(await supabase.from("profiles").select("id, full_name, email").in("id", ids))
    : [];
  const byId = new Map(people.map((p) => [p.id, p]));
  return apps.map((a) => ({ ...a, person: byId.get(a.editor_id) ?? null }));
}

/** Admin detail view of one application and the person behind it. */
export async function getApplicationDetail(applicationId: string) {
  const supabase = await createClient();
  const { data: app, error } = await supabase
    .from("editor_applications")
    .select(
      "id, editor_id, attempt, status, submitted_snapshot, submitted_at, terms_version, privacy_version, review_started_at, decided_at, decision_message, reopened_from, created_at",
    )
    .eq("id", applicationId)
    .maybeSingle();
  if (error) throw error;
  if (!app) return null;

  const [person, editor, requests, notes, attempts, activity] = await Promise.all([
    supabase.from("profiles").select("full_name, email, phone").eq("id", app.editor_id).single(),
    supabase
      .from("editor_profiles")
      .select("access_status, level, access_changed_at, access_change_reason")
      .eq("user_id", app.editor_id)
      .single(),
    supabase
      .from("application_requests")
      .select(
        "id, kind, message, requested_at, response, response_link, responded_at, assessment_result, assessment_notes, assessed_at",
      )
      .eq("application_id", app.id)
      .order("requested_at"),
    supabase
      .from("editor_vetting_notes")
      .select("id, note, created_at, author_id")
      .eq("application_id", app.id)
      .order("created_at", { ascending: false }),
    supabase
      .from("editor_applications")
      .select("id, attempt, status, submitted_at")
      .eq("editor_id", app.editor_id)
      .order("attempt", { ascending: false }),
    supabase
      .from("activity_logs")
      .select("id, action, created_at, details")
      .or(
        `and(entity_type.eq.editor_application,entity_id.eq.${app.id}),and(entity_type.eq.editor_profile,entity_id.eq.${app.editor_id})`,
      )
      .order("created_at", { ascending: false })
      .limit(30),
  ]);

  const allAttempts = check(attempts);
  return {
    app,
    person: check(person),
    editor: check(editor),
    requests: check(requests),
    notes: check(notes),
    attempts: allAttempts,
    isLatestAttempt: allAttempts[0]?.id === app.id,
    activity: check(activity),
  };
}
