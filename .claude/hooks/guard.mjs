#!/usr/bin/env node
// PreToolUse guard for EDITSTATION. Deterministic: no network, no model calls.
//   deny: reading or writing environment files (.env.example is allowed)
//   deny: editing migrations already committed to git (create a new migration instead)
//   ask:  git push/commit and history rewrites, hosted Supabase and Vercel operations,
//         non-local database URLs, shell access to env files or migration files
// Fails open on malformed input so a hook bug never blocks all work; the permission
// rules in .claude/settings.json cover the same commands as a second layer.
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export function isEnvFile(filePath) {
  const base = path.basename(String(filePath).replaceAll("\\", "/"));
  return /^\.env(\..+)?$/.test(base) && base !== ".env.example";
}

const ENV_REF = /(^|[\s/\\'"=(])(\.env(?:\.[\w.-]+)?)(?=$|[\s'"`;|&)<>])/g;

export function envFilesInCommand(command) {
  const found = [];
  for (const match of command.matchAll(ENV_REF)) {
    if (match[2] !== ".env.example") found.push(match[2]);
  }
  return found;
}

const BASH_ASK_RULES = [
  [/\bgit\s+push\b/, "git push needs the owner's approval"],
  [/\bgit\s+commit\b/, "git commit needs the owner's approval"],
  [/\bgit\s+reset\s+[^;&|]*--hard\b/, "git reset --hard discards work"],
  [/\bgit\s+clean\s+-\w*f/, "git clean deletes untracked files (brand assets live untracked)"],
  [/\bgit\s+(checkout|restore)\s+[^;&|]*--\s/, "discarding working-tree changes"],
  [/\bgit\s+branch\s+-D\b/, "force-deleting a branch"],
  [
    /\bsupabase\s+(link|unlink|login|projects|orgs|secrets|branches|functions\s+deploy|db\s+push|db\s+dump|db\s+pull|migration\s+(repair|up|squash)|storage|sso|domains|vanity-subdomains|network-restrictions|postgres-config)\b/,
    "Supabase command that can touch a hosted project",
  ],
  [/--linked\b|--project-ref\b/, "targets a hosted Supabase project"],
  [/\bvercel\b/, "Vercel command (deploys or hosted environment variables)"],
];

const NON_LOCAL_DB_URL = /postgres(?:ql)?:\/\/[^\s'"]*@(?!127\.0\.0\.1[:/]|localhost[:/]|\[::1\][:/])/;
const MIGRATION_WRITE =
  /(\brm\b|\bmv\b|\bcp\b|\bsed\s+-i|\bperl\s+-[a-z]*i|\btee\b|>{1,2}\s*["']?[^\s"']*supabase[/\\]migrations|Set-Content|Out-File|Remove-Item|Move-Item)/;

export function checkBash(rawCommand) {
  const command = String(rawCommand).replace(/(^|[;&|]\s*)rtk\s+/g, "$1");
  for (const [pattern, reason] of BASH_ASK_RULES) {
    if (pattern.test(command)) return { decision: "ask", reason };
  }
  if (NON_LOCAL_DB_URL.test(command)) {
    return { decision: "ask", reason: "database URL is not local" };
  }
  const envs = envFilesInCommand(command);
  if (envs.length > 0) {
    return { decision: "ask", reason: `shell command references ${envs.join(", ")}` };
  }
  if (/supabase[/\\]migrations[/\\]/.test(command) && MIGRATION_WRITE.test(command)) {
    return { decision: "ask", reason: "shell command may modify migration files" };
  }
  return null;
}

export function isCommittedMigration(filePath, projectDir) {
  const abs = path.resolve(projectDir, String(filePath));
  const rel = path.relative(projectDir, abs).replaceAll("\\", "/");
  if (!/^supabase\/migrations\/[^/]+\.sql$/.test(rel)) return false;
  try {
    execFileSync("git", ["cat-file", "-e", `HEAD:${rel}`], { cwd: projectDir, stdio: "ignore" });
    return true;
  } catch (error) {
    // Exit status 128 = not in HEAD (a new, uncommitted migration). Anything else: fail closed.
    return error.status === 128 ? false : existsSync(abs);
  }
}

const EDIT_TOOLS = new Set(["Edit", "Write", "MultiEdit", "NotebookEdit"]);
const FILE_TOOLS = new Set([...EDIT_TOOLS, "Read"]);

export function evaluate(input, projectDir) {
  const tool = input.tool_name;
  const args = input.tool_input ?? {};
  if (tool === "Bash" || tool === "PowerShell") return checkBash(args.command ?? "");
  const target = args.file_path ?? args.notebook_path ?? (tool === "Grep" ? args.path : undefined);
  if (!target) return null;
  if ((FILE_TOOLS.has(tool) || tool === "Grep") && isEnvFile(target)) {
    return { decision: "deny", reason: "environment files are protected; use .env.example" };
  }
  if (EDIT_TOOLS.has(tool) && isCommittedMigration(target, projectDir)) {
    return {
      decision: "deny",
      reason:
        "this migration is committed (treated as applied); create a new one with `supabase migration new <name>`",
    };
  }
  return null;
}

function main() {
  let input;
  try {
    input = JSON.parse(readFileSync(0, "utf8"));
  } catch {
    process.exit(0);
  }
  // The project root is two levels above this file; avoids MSYS-style CLAUDE_PROJECT_DIR on Windows.
  const projectDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
  const result = evaluate(input, projectDir);
  if (!result) process.exit(0);
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: result.decision,
        permissionDecisionReason: `EDITSTATION guard: ${result.reason}`,
      },
    }),
  );
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}
