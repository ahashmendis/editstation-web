import { defineConfig, devices } from "@playwright/test";

// Smoke tests run against the local stack: `npm run db:start` must be running (the app reads
// service types from local Supabase). Reuses a dev server already on :3000; otherwise starts one.
// Never run these while `npm run build` is running, and never point them at a hosted environment.
const port = 3000;

export default defineConfig({
  testDir: "tests/e2e",
  // Signed-in tests create e2e-only accounts and projects; remove them before and after a run.
  // The setup also warms the signed-in pages so `next dev` compiles them before timed steps.
  globalSetup: "./tests/e2e/support/global-setup.ts",
  globalTeardown: "./tests/e2e/support/cleanup.ts",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  // `next dev` compiles pages on demand, so a loaded run can time out a step: retry once.
  retries: process.env.CI ? 2 : 1,
  workers: 2,
  reporter: process.env.CI ? "github" : "list",
  use: {
    baseURL: `http://localhost:${port}`,
    trace: "retain-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: {
    command: "npm run dev",
    url: `http://localhost:${port}`,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});
