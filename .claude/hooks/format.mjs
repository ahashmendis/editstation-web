#!/usr/bin/env node
// PostToolUse: format the file Claude just edited with the project's Prettier.
// Deterministic and non-blocking: respects .prettierignore, skips unknown file types,
// never fails the tool call. `npm run check` remains the gate.
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

let input;
try {
  input = JSON.parse(readFileSync(0, "utf8"));
} catch {
  process.exit(0);
}

// The project root is two levels above this file; avoids MSYS-style CLAUDE_PROJECT_DIR on Windows.
const projectDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const target = input.tool_input?.file_path;
const prettier = path.join(projectDir, "node_modules", "prettier", "bin", "prettier.cjs");
if (!target || !existsSync(prettier)) process.exit(0);

const abs = path.resolve(projectDir, target);
const rel = path.relative(projectDir, abs);
if (rel.startsWith("..") || path.isAbsolute(rel) || !existsSync(abs)) process.exit(0);

try {
  execFileSync(process.execPath, [prettier, "--write", "--ignore-unknown", "--log-level", "warn", rel], {
    cwd: projectDir,
    stdio: ["ignore", "ignore", "pipe"],
    timeout: 20000,
  });
} catch (error) {
  // Usually a syntax error in the edited file; surface it briefly without blocking.
  const message = String(error.stderr ?? error.message).split("\n").slice(0, 3).join(" ");
  process.stderr.write(`prettier skipped ${rel}: ${message}\n`);
}
process.exit(0);
