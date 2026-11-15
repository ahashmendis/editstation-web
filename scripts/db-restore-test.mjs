#!/usr/bin/env node
// Backup/restore drill for the LOCAL Supabase database (docs/RUNBOOKS.md, "Backup and restore").
//
// 1. pg_dump the local `postgres` database (custom format) inside the local DB container.
// 2. Restore it into a scratch database `restore_check` in the same local container.
// 3. Compare row counts of every table in public, private and auth, the applied migrations,
//    function counts, and RLS coverage of public tables. Exit 1 on any difference.
// 4. Drop the scratch database and the dump (pass --keep to keep both for inspection).
//
// Local only: talks to the `supabase_db_<project_id>` Docker container via `docker exec`. It never
// links a project, pushes, or connects to a hosted database.

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const keep = process.argv.includes("--keep");
const projectId = /^project_id\s*=\s*"([^"]+)"/m.exec(
  readFileSync("supabase/config.toml", "utf8"),
)?.[1];
if (!projectId) throw new Error("project_id not found in supabase/config.toml");

const container = `supabase_db_${projectId}`;
const SOURCE = "postgres";
const SCRATCH = "restore_check";
const SUPERUSER = "supabase_admin"; // local image superuser; `postgres` cannot restore everything
const DUMP = "/tmp/editstation-restore-check.dump";

function inContainer(args, input) {
  return execFileSync("docker", ["exec", "-i", container, ...args], {
    encoding: "utf8",
    input,
    stdio: ["pipe", "pipe", "pipe"],
  });
}

function query(db, sql) {
  return inContainer(["psql", "-U", SUPERUSER, "-d", db, "-v", "ON_ERROR_STOP=1", "-qtA"], sql)
    .trim()
    .split("\n")
    .filter(Boolean);
}

const running = execFileSync("docker", ["ps", "--format", "{{.Names}}"], { encoding: "utf8" });
if (!running.split(/\r?\n/).includes(container)) {
  console.error(`Local database container ${container} is not running. Run \`npm run db:start\`.`);
  process.exit(1);
}

const CHECKS = {
  rows: `
    select format('%s.%s', table_schema, table_name),
           (xpath('/row/c/text()', query_to_xml(
             format('select count(*) as c from %I.%I', table_schema, table_name),
             false, true, '')))[1]::text
    from information_schema.tables
    where table_schema in ('public', 'private', 'auth') and table_type = 'BASE TABLE'
    order by 1;`,
  migrations: `select version from supabase_migrations.schema_migrations order by 1;`,
  functions: `
    select n.nspname, count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private') group by 1 order by 1;`,
  publicTablesWithoutRls: `
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity order by 1;`,
};

// Source results are taken just before the dump. If the app writes in between (sign-ins, session
// refreshes), counts can drift: the script then says so, and re-running with the dev server
// stopped gives a clean comparison.
const before = Object.fromEntries(
  Object.entries(CHECKS).map(([name, sql]) => [name, query(SOURCE, sql).join("\n")]),
);

console.log(`Dumping local database "${SOURCE}"…`);
inContainer(["pg_dump", "-U", SUPERUSER, "-d", SOURCE, "-Fc", "-f", DUMP]);

console.log(`Restoring into scratch database "${SCRATCH}"…`);
inContainer(["dropdb", "-U", SUPERUSER, "--if-exists", SCRATCH]);
inContainer(["createdb", "-U", SUPERUSER, "-T", "template0", SCRATCH]);
try {
  inContainer(["pg_restore", "-U", SUPERUSER, "-d", SCRATCH, "--exit-on-error", DUMP]);
} catch (error) {
  console.error("pg_restore failed:\n", error.stderr || error.message);
  process.exit(1);
}

let failures = 0;
for (const [name, sql] of Object.entries(CHECKS)) {
  const source = before[name];
  const restored = query(SCRATCH, sql).join("\n");
  if (source !== restored) {
    failures++;
    console.error(`MISMATCH in ${name}:\n--- source\n${source}\n--- restored\n${restored}`);
    if (query(SOURCE, sql).join("\n") !== source) {
      console.error("The source database changed during the drill. Stop `npm run dev` and re-run.");
    }
  }
}

const rows = query(SCRATCH, CHECKS.rows).map((line) => line.split("|"));
const total = rows.reduce((sum, [, count]) => sum + Number(count), 0);
const noRls = query(SCRATCH, CHECKS.publicTablesWithoutRls);
if (noRls.length) {
  failures++;
  console.error(`Restored public tables without RLS: ${noRls.join(", ")}`);
}
const migrations = query(SCRATCH, CHECKS.migrations).length;

if (!keep) {
  inContainer(["dropdb", "-U", SUPERUSER, "--if-exists", SCRATCH]);
  inContainer(["rm", "-f", DUMP]);
} else {
  console.log(`Kept database "${SCRATCH}" and ${container}:${DUMP}.`);
}

if (failures) {
  console.error(`Restore check FAILED (${failures} check(s)).`);
  process.exit(1);
}
console.log(
  `Restore check passed: ${rows.length} tables, ${total} rows, ${migrations} migrations match; ` +
    "all public tables have RLS.",
);
