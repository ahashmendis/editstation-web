import { cleanupE2eData } from "./local-stack";

// Runs after the dev server is up: clears leftovers from an aborted run, then requests the pages
// the signed-in tests use so `next dev` compiles them before the first timed sign-in.
const WARM_PATHS = [
  "/inquire",
  "/sign-in",
  "/editor",
  "/mfa",
  "/admin",
  "/editor/earnings",
  "/editor/opportunities",
  "/admin/earnings",
  "/client/sign-in",
  "/admin/clients",
  "/client/projects/new",
  "/client/requests",
  "/admin/inquiries",
];

export default async function globalSetup() {
  cleanupE2eData();
  const base = "http://localhost:3000";
  for (const path of WARM_PATHS) {
    try {
      await fetch(`${base}${path}`, { redirect: "manual", signal: AbortSignal.timeout(60_000) });
    } catch {
      // Warming is best effort; the tests still run (and wait) if a page is slow.
    }
  }
}
