import { defineConfig, devices } from "@playwright/test";

// Smoke tests run against the local stack: `npm run db:start` must be running (the app reads
// service types from local Supabase). Reuses a dev server already on :3000; otherwise starts one.
// Never run these while `npm run build` is running, and never point them at a hosted environment.
const port = 3000;

export default defineConfig({
  testDir: "tests/e2e",
  // Signed-in tests create e2e-only accounts and projects; remove them before and after a run.
  globalSetup: "./tests/e2e/support/cleanup.ts",
  globalTeardown: "./tests/e2e/support/cleanup.ts",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
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
