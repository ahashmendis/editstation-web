import { execFileSync, execSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import { totp, totpStep } from "./totp";

// Test-only helpers for the LOCAL Supabase stack (`npm run db:start`). Keys are read at runtime
// from `supabase status -o env` and kept in memory only: nothing is written to disk or env files.
// Every helper refuses to run unless the API is on 127.0.0.1/localhost.

type LocalEnv = {
  apiUrl: string;
  mailpitUrl: string;
  publishableKey: string;
  serviceRoleKey: string;
  dbContainer: string;
};

let cached: LocalEnv | null = null;

function parseEnv(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const line of text.split(/\r?\n/)) {
    const match = /^([A-Z_]+)=(.*)$/.exec(line.trim());
    if (match) out[match[1]] = match[2].replace(/^"(.*)"$/, "$1");
  }
  return out;
}

function assertLocal(url: string) {
  const host = new URL(url).hostname;
  if (host !== "127.0.0.1" && host !== "localhost") {
    throw new Error(`Refusing to run e2e helpers against a non-local Supabase (${host}).`);
  }
}

export function localEnv(): LocalEnv {
  if (cached) return cached;
  const raw = execSync("npx supabase status -o env", {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  });
  const env = parseEnv(raw);
  const projectId = /^project_id\s*=\s*"([^"]+)"/m.exec(
    readFileSync("supabase/config.toml", "utf8"),
  )?.[1];
  const apiUrl = env.API_URL;
  const serviceRoleKey = env.SERVICE_ROLE_KEY || env.SECRET_KEY;
  const publishableKey = env.PUBLISHABLE_KEY || env.ANON_KEY;
  if (!apiUrl || !serviceRoleKey || !publishableKey || !projectId) {
    throw new Error("Local Supabase is not running. Start it with `npm run db:start`.");
  }
  assertLocal(apiUrl);
  const mailpitUrl = env.MAILPIT_URL || env.INBUCKET_URL || "http://127.0.0.1:54324";
  assertLocal(mailpitUrl);
  cached = {
    apiUrl,
    mailpitUrl,
    publishableKey,
    serviceRoleKey,
    dbContainer: `supabase_db_${projectId}`,
  };
  return cached;
}

const noSession = { auth: { persistSession: false, autoRefreshToken: false } };

function serviceClient(): SupabaseClient {
  const env = localEnv();
  return createClient(env.apiUrl, env.serviceRoleKey, noSession);
}

/** Runs SQL as `postgres` inside the local database container. Returns trimmed stdout. */
export function sql(statement: string, user: "postgres" | "supabase_admin" = "postgres"): string {
  const env = localEnv();
  return execFileSync(
    "docker",
    [
      "exec",
      "-i",
      env.dbContainer,
      "psql",
      "-U",
      user,
      "-d",
      "postgres",
      "-v",
      "ON_ERROR_STOP=1",
      "-q",
      "-t",
      "-A",
    ],
    { input: statement, encoding: "utf8" },
  ).trim();
}

/** Only values we generate (uuids, e2e emails) are interpolated; still quote them safely. */
export const lit = (value: string) => `'${value.replace(/'/g, "''")}'`;

export type TestUser = { id: string; email: string; password: string };

export function uniqueEmail(role: string): string {
  return `e2e-${role}-${Date.now()}-${randomUUID().slice(0, 8)}@example.test`;
}

export const TEST_PASSWORD = `E2e-${randomUUID().slice(0, 12)}9x`;

/** Creates a confirmed account (no email sent). Gets editor_profiles with no access, like sign-up. */
export async function createConfirmedUser(role: string): Promise<TestUser> {
  const email = uniqueEmail(role);
  const { data, error } = await serviceClient().auth.admin.createUser({
    email,
    password: TEST_PASSWORD,
    email_confirm: true,
  });
  if (error || !data.user) throw error ?? new Error("createUser returned no user");
  return { id: data.user.id, email, password: TEST_PASSWORD };
}

/** Local-only shortcut for the admin approval flow (covered by pgTAP): make an editor active. */
export function activateEditor(userId: string) {
  sql(`update public.editor_profiles set access_status = 'active' where user_id = ${lit(userId)};`);
}

/** Creates an admin with a verified TOTP factor and returns its secret for later codes. */
export async function createAdminWithTotp(): Promise<AdminUser> {
  const user = await createConfirmedUser("admin");
  sql(`select private.grant_admin_by_email(${lit(user.email)}, 'e2e');`);

  const env = localEnv();
  const client = createClient(env.apiUrl, env.publishableKey, noSession);
  const signIn = await client.auth.signInWithPassword({
    email: user.email,
    password: user.password,
  });
  if (signIn.error) throw signIn.error;
  const enroll = await client.auth.mfa.enroll({ factorType: "totp", friendlyName: "e2e" });
  if (enroll.error) throw enroll.error;
  const secret = enroll.data.totp.secret;
  const verify = await client.auth.mfa.challengeAndVerify({
    factorId: enroll.data.id,
    code: totp(secret),
  });
  if (verify.error) throw verify.error;
  return { ...user, totpSecret: secret, enrolledStep: totpStep() };
}

export type AdminUser = TestUser & { totpSecret: string; enrolledStep: number };

/** A code from a later 30 s window than `afterStep`, so a code is never reused. */
export async function freshTotp(secret: string, afterStep: number): Promise<string> {
  while (totpStep() <= afterStep) await new Promise((r) => setTimeout(r, 500));
  return totp(secret);
}

/**
 * Creates an open project and sends `editorId` an offer, through the real admin functions
 * (run as the given admin with an aal2 claim). Returns the project id.
 */
export function createProjectWithOffer(adminId: string, editorId: string, title: string): string {
  const projectId = randomUUID();
  sql(`
    insert into public.projects (id, title, brief_type, status, first_opened_at)
    values (${lit(projectId)}, ${lit(title)}, 'fully_instructed', 'open', now());
    begin;
    select set_config('request.jwt.claims',
      json_build_object('sub', ${lit(adminId)}, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    set local role authenticated;
    select public.admin_grant_project_access(${lit(projectId)}, array[${lit(editorId)}]::uuid[], 'invited');
    select public.admin_make_offer(${lit(projectId)}, ${lit(editorId)}, 5000);
    commit;
  `);
  return projectId;
}

/** Creates an open project with no editors yet (title must start with `E2E project `). */
export function createOpenProject(title: string): string {
  const projectId = randomUUID();
  sql(`
    insert into public.projects (id, title, brief_type, status, first_opened_at, proposed_amount)
    values (${lit(projectId)}, ${lit(title)}, 'fully_instructed', 'open', now(), 20000);
  `);
  return projectId;
}

/** Registers `editorId`'s interest in the project's opportunity through the real function. */
export function registerInterestAs(editorId: string, projectId: string) {
  // Looked up as postgres: the API role cannot read project_id (column-level grant).
  const opportunityId = sql(
    `select id from public.project_opportunities where project_id = ${lit(projectId)};`,
  );
  sql(`
    begin;
    select set_config('request.jwt.claims',
      json_build_object('sub', ${lit(editorId)}, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    set local role authenticated;
    select public.editor_register_interest(${lit(opportunityId)});
    commit;
  `);
}

/**
 * Phase 12C: takes a project from createProjectWithOffer to a confirmed assignment whose brief the
 * editor has confirmed, with agreed terms and a client price, so only the client deposit is
 * missing before work can start. Runs each step as the right identity (aal2 admin, editor).
 */
export function confirmAssignmentAwaitingDeposit(
  adminId: string,
  editorId: string,
  projectId: string,
  clientPrice: number,
  /** Optional terms draft (e.g. a cancellation schedule) saved before agreeing. */
  terms?: Record<string, unknown>,
) {
  const as = (uid: string, aal: string) => `
    select set_config('request.jwt.claims',
      json_build_object('sub', ${lit(uid)}, 'role', 'authenticated', 'aal', ${lit(aal)})::text, true);
    set local role authenticated;`;
  const asg = `(select id from public.assignments where project_id = ${lit(projectId)} order by created_at desc limit 1)`;
  sql(`
    update public.projects set deadline = '2099-12-31' where id = ${lit(projectId)};
    -- Projects inserted directly have no project_internal row (admin_create_project adds one).
    insert into public.project_internal (project_id) values (${lit(projectId)}) on conflict do nothing;
    insert into public.brief_versions (project_id, version, instructions, deliverables)
    values (${lit(projectId)}, 1, 'Cut it', '[{"name": "Main"}]') on conflict do nothing;
    begin;
    ${as(adminId, "aal2")}
    select public.admin_update_project(${lit(projectId)}, jsonb_build_object('client_price', ${clientPrice}));
    ${terms ? `select public.admin_save_terms_draft(${lit(projectId)}, ${lit(JSON.stringify(terms))}::jsonb);` : ""}
    select public.admin_agree_terms(${lit(projectId)}, 1);
    ${as(editorId, "aal1")}
    select public.editor_respond_offer(${asg}, 'accept');
    ${as(adminId, "aal2")}
    select public.admin_confirm_assignment(${asg});
    ${as(editorId, "aal1")}
    select public.editor_confirm_brief(${asg}, 1, '2099-12-31', 5000, 'LKR');
    commit;
  `);
}

/**
 * Removes everything the signed-in e2e tests created (accounts `e2e-…@example.test`, projects
 * titled `E2E project …`, inquiries from e2e emails) and every row that references them, found by
 * walking foreign keys. pgTAP tests count rows in a clean database, so e2e data must not stay
 * behind. Runs as the local superuser with triggers off (replica mode) because history tables are
 * append-only by design; this is acceptable only for throwaway local test data and only ever runs
 * against the local container.
 */
export function cleanupE2eData() {
  sql(
    `
    begin;
    set local session_replication_role = replica;
    create temp table doomed (rel regclass, row_ctid tid, primary key (rel, row_ctid)) on commit drop;
    insert into doomed select 'auth.users'::regclass, ctid from auth.users
      where email like 'e2e-%@example.test';
    insert into doomed select 'public.projects'::regclass, ctid from public.projects
      where title like 'E2E project %';
    insert into doomed select 'public.client_inquiries'::regclass, ctid from public.client_inquiries
      where email like 'e2e-%@example.test';
    -- Client area tests create client records with e2e emails (their client_users and
    -- project_internal rows are found through the foreign keys below).
    insert into doomed select 'public.clients'::regclass, ctid from public.clients
      where email like 'e2e-%@example.test';
    do $cleanup$
    declare
      fk record;
      added int;
      changed boolean := true;
    begin
      while changed loop
        changed := false;
        for fk in
          select c.conrelid::regclass as child, a.attname as child_col,
                 c.confrelid::regclass as parent, pa.attname as parent_col
          from pg_constraint c
          join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
          join pg_attribute pa on pa.attrelid = c.confrelid and pa.attnum = c.confkey[1]
          where c.contype = 'f' and cardinality(c.conkey) = 1
            and c.confrelid in (select distinct rel from doomed)
            -- Settings rows are kept (an e2e admin may have changed one); see below.
            and c.conrelid <> 'public.app_settings'::regclass
        loop
          execute format(
            'insert into doomed select %L::regclass, ch.ctid from %s ch join %s p on ch.%I = p.%I
             where p.ctid in (select row_ctid from doomed where rel = %L::regclass)
             on conflict do nothing',
            fk.child, fk.child, fk.parent, fk.child_col, fk.parent_col, fk.parent);
          get diagnostics added = row_count;
          changed := changed or added > 0;
        end loop;
      end loop;
    end
    $cleanup$;
    do $purge$
    declare r regclass;
    begin
      -- Audit rows point at entities by text id, not by foreign key: collect the ids first.
      create temp table doomed_ids (id text primary key) on commit drop;
      for r in select distinct rel from doomed loop
        execute format(
          'insert into doomed_ids select coalesce(to_jsonb(t) ->> ''id'', to_jsonb(t) ->> ''user_id'')
           from %s t where t.ctid in (select row_ctid from doomed where rel = %L::regclass)
             and coalesce(to_jsonb(t) ->> ''id'', to_jsonb(t) ->> ''user_id'') is not null
           on conflict do nothing', r, r);
      end loop;
      update public.app_settings set updated_by = null where updated_by::text in (select id from doomed_ids);
      delete from public.activity_logs where entity_id in (select id from doomed_ids)
        or actor_id::text in (select id from doomed_ids);
      -- Notifications point at entities by id too (e.g. interest_registered to every admin about
      -- an e2e project, opportunity_not_selected about an e2e opportunity).
      delete from public.notifications where entity_id::text in (select id from doomed_ids);
      for r in select distinct rel from doomed loop
        execute format('delete from %s where ctid in (select row_ctid from doomed where rel = %L::regclass)', r, r);
      end loop;
    end
    $purge$;
    delete from private.inquiry_throttle;
    commit;
    `,
    "supabase_admin",
  );
}

/** Clears the local per-IP inquiry throttle so repeated local runs stay under the hourly limit. */
export function resetInquiryThrottle() {
  sql("delete from private.inquiry_throttle;");
}

/** Waits for the newest email to `to` in Mailpit and returns the auth link inside it. */
export async function confirmationLinkFor(to: string): Promise<string> {
  const { mailpitUrl } = localEnv();
  const query = encodeURIComponent(`to:"${to}"`);
  for (let attempt = 0; attempt < 40; attempt++) {
    const search = await fetch(`${mailpitUrl}/api/v1/search?query=${query}`);
    const { messages } = (await search.json()) as { messages?: { ID: string }[] };
    if (messages?.length) {
      const message = await fetch(`${mailpitUrl}/api/v1/message/${messages[0].ID}`);
      const { HTML, Text } = (await message.json()) as { HTML?: string; Text?: string };
      const body = `${HTML ?? ""}\n${Text ?? ""}`.replace(/&amp;/g, "&");
      const link = /https?:\/\/[^\s"'<>]+\/auth\/confirm\?[^\s"'<>]+/.exec(body)?.[0];
      if (link) return link;
    }
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error(`No confirmation email for ${to} in Mailpit.`);
}

/** Waits for the newest email to `to` in Mailpit and returns the 8-digit sign-in code inside it. */
export async function signInCodeFor(to: string): Promise<string> {
  const { mailpitUrl } = localEnv();
  const query = encodeURIComponent(`to:"${to}"`);
  for (let attempt = 0; attempt < 40; attempt++) {
    const search = await fetch(`${mailpitUrl}/api/v1/search?query=${query}`);
    const { messages } = (await search.json()) as { messages?: { ID: string }[] };
    if (messages?.length) {
      const message = await fetch(`${mailpitUrl}/api/v1/message/${messages[0].ID}`);
      const { HTML, Text } = (await message.json()) as { HTML?: string; Text?: string };
      const code = />\s*(\d{8})\s*</.exec(HTML ?? "")?.[1] ?? /\b(\d{8})\b/.exec(Text ?? "")?.[1];
      if (code) return code;
    }
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error(`No sign-in code email for ${to} in Mailpit.`);
}

/** Creates a client record (email `e2e-…@example.test`) and returns its id. */
export function createE2eClient(name: string): string {
  const id = randomUUID();
  sql(
    `insert into public.clients (id, name, email) values (${lit(id)}, ${lit(name)}, ${lit(uniqueEmail("clientrec"))});`,
  );
  return id;
}

/**
 * Creates a project (title must start with `E2E project `) for a client, with agreed terms, a
 * client price and its two client milestones, through the real admin functions (aal2 admin).
 */
export function createClientProject(
  adminId: string,
  clientId: string,
  title: string,
  clientPrice: number,
): string {
  const projectId = randomUUID();
  sql(`
    insert into public.projects (id, title, brief_type, status, first_opened_at, deadline)
    values (${lit(projectId)}, ${lit(title)}, 'fully_instructed', 'open', now(), '2099-12-31');
    insert into public.project_internal (project_id, client_id) values (${lit(projectId)}, ${lit(clientId)});
    insert into public.project_deliverables (project_id, name, format) values (${lit(projectId)}, 'Main film', 'MP4');
    begin;
    select set_config('request.jwt.claims',
      json_build_object('sub', ${lit(adminId)}, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    set local role authenticated;
    select public.admin_update_project(${lit(projectId)}, jsonb_build_object('client_price', ${clientPrice}));
    select public.admin_agree_terms(${lit(projectId)}, 1);
    select public.admin_create_client_milestones(${lit(projectId)});
    commit;
  `);
  return projectId;
}

/** Creates a draft project (title must start with `E2E project `) linked to a client. */
export function createDraftClientProject(clientId: string, title: string): string {
  const projectId = randomUUID();
  sql(`
    insert into public.projects (id, title, brief_type, status)
    values (${lit(projectId)}, ${lit(title)}, 'fully_instructed', 'draft');
    insert into public.project_internal (project_id, client_id) values (${lit(projectId)}, ${lit(clientId)});
  `);
  return projectId;
}

/**
 * Invites a client user without the UI: creates the password-less account like the admin action
 * does, then links it through the real admin function (aal2 admin). Returns the email.
 */
export async function inviteClientUserDirect(
  adminId: string,
  clientId: string,
  role: string,
): Promise<string> {
  const email = uniqueEmail(role);
  const { error } = await serviceClient().auth.admin.createUser({
    email,
    email_confirm: true,
    app_metadata: { client_invite: true },
  });
  if (error) throw error;
  sql(`
    begin;
    select set_config('request.jwt.claims',
      json_build_object('sub', ${lit(adminId)}, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    set local role authenticated;
    select public.admin_invite_client_user(${lit(clientId)}, ${lit(email)});
    commit;
  `);
  return email;
}

/** Revokes a client user's access through the real admin function (aal2 admin). */
export function revokeClientUserDirect(adminId: string, email: string) {
  // Looked up as postgres: no API role can read client_users.
  const clientUserId = sql(`
    select cu.id from public.client_users cu join public.profiles p on p.id = cu.user_id
    where p.email = ${lit(email)} and cu.revoked_at is null;
  `);
  sql(`
    begin;
    select set_config('request.jwt.claims',
      json_build_object('sub', ${lit(adminId)}, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    set local role authenticated;
    select public.admin_revoke_client_user(${lit(clientUserId)});
    commit;
  `);
}

/**
 * Completes a converted draft (one deliverable, brief instructions) and opens it through the real
 * admin functions (aal2 admin).
 */
export function openProjectAsAdmin(adminId: string, projectId: string) {
  sql(`
    insert into public.project_deliverables (project_id, name, format) values (${lit(projectId)}, 'Main film', 'MP4');
    begin;
    select set_config('request.jwt.claims',
      json_build_object('sub', ${lit(adminId)}, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    set local role authenticated;
    select public.admin_save_brief(${lit(projectId)},
      '{"brief": {"instructions": "Cut the launch film"}, "change_summary": "e2e"}');
    select public.admin_set_project_status(${lit(projectId)}, 'open', 'e2e');
    commit;
  `);
}
