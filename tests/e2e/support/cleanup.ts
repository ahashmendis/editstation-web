import { cleanupE2eData } from "./local-stack";

// Used as both globalSetup (leftovers from an aborted run) and globalTeardown, so the local
// database is clean for `npm run db:test` after `npm run test:e2e`.
export default function cleanup() {
  cleanupE2eData();
}
