// Run: node --test .claude/hooks/guard.test.mjs
import assert from "node:assert/strict";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { checkBash, evaluate, isEnvFile } from "./guard.mjs";

const projectDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const decide = (tool, tool_input) => evaluate({ tool_name: tool, tool_input }, projectDir)?.decision ?? "pass";
const bash = (command) => checkBash(command)?.decision ?? "pass";

test("environment files", () => {
  for (const f of [".env", ".env.local", "C:\\x\\.env.production.local", "/a/.env.development"]) {
    assert.equal(isEnvFile(f), true, f);
  }
  for (const f of [".env.example", "env.ts", ".envrc.md", "src/lib/env.ts"]) {
    assert.equal(isEnvFile(f), false, f);
  }
  assert.equal(decide("Read", { file_path: path.join(projectDir, ".env.local") }), "deny");
  assert.equal(decide("Edit", { file_path: path.join(projectDir, ".env.local") }), "deny");
  assert.equal(decide("Write", { file_path: path.join(projectDir, ".env.example") }), "pass");
  assert.equal(decide("Grep", { pattern: "KEY", path: ".env.local" }), "deny");
});

test("committed migrations are protected, new ones are not", () => {
  const applied = path.join(projectDir, "supabase", "migrations", "20261111122133_phase1_auth_access.sql");
  assert.equal(decide("Edit", { file_path: applied }), "deny");
  assert.equal(decide("Write", { file_path: applied }), "deny");
  assert.equal(decide("Read", { file_path: applied }), "pass");
  const fresh = path.join(projectDir, "supabase", "migrations", "29991231000000_new.sql");
  assert.equal(decide("Write", { file_path: fresh }), "pass");
  assert.equal(decide("Edit", { file_path: path.join(projectDir, "src", "app", "page.tsx") }), "pass");
});

test("risky shell commands ask", () => {
  for (const c of [
    "git push",
    "rtk git push origin main",
    "git push --force",
    "git add -A && git commit -m x",
    "git reset --hard HEAD~1",
    "git clean -fd",
    "git checkout -- src/app/page.tsx",
    "npx supabase link --project-ref abc",
    "supabase db push",
    "npx supabase db reset --linked",
    "supabase migration repair --status applied 1",
    "npx vercel --prod",
    "psql postgresql://postgres:pw@db.abc.supabase.co:5432/postgres",
    "cat .env.local",
    "cp .env.example .env.local",
    "rm supabase/migrations/20261111122133_phase1_auth_access.sql",
    "sed -i s/a/b/ supabase/migrations/x.sql",
  ]) {
    assert.equal(bash(c), "ask", c);
  }
});

test("routine shell commands pass", () => {
  for (const c of [
    "git status",
    "rtk git diff",
    "git log --oneline -5",
    "npm run check",
    "npm run db:test",
    "npm run db:reset",
    "npx supabase status",
    "npx supabase migration new add_projects",
    "psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c 'select 1'",
    "node -e \"console.log(process.env.NODE_ENV)\"",
    "cat .env.example",
    "ls supabase/migrations",
    "grep -n create supabase/migrations/x.sql",
  ]) {
    assert.equal(bash(c), "pass", c);
  }
});
