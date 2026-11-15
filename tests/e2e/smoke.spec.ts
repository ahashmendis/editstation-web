import { expect, test } from "@playwright/test";

// Smoke tests for the public surface and the signed-out access gates. They create no data, so
// they are safe to repeat against the local database.

test.describe("public site", () => {
  test("home page offers two separate entry points", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator('main a[href="/inquire"]').first()).toBeVisible();
    await expect(page.locator('main a[href="/sign-up"]').first()).toBeVisible();
  });

  test("inquiry form loads service types and lists missing fields on empty submit", async ({
    page,
  }) => {
    await page.goto("/inquire");
    const service = page.getByLabel("Type of editing");
    await expect(service).toBeVisible();
    // Service types come from the database: more than the "Choose…" placeholder means Supabase is up.
    await expect(service.locator("option")).not.toHaveCount(1);

    await page.getByRole("button", { name: "Send inquiry" }).click();
    await expect(page.getByText("Please tell us your name.")).toBeVisible();
    await expect(page.getByText("Please describe the project.")).toBeVisible();
    await expect(page.getByText("Please choose a type of service.")).toBeVisible();
  });

  test("inquiry form works at phone width without horizontal scroll", async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto("/inquire");
    await expect(page.getByLabel("Your name")).toBeVisible();
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );
    expect(overflow).toBeLessThanOrEqual(0);
  });
});

test("unknown pages show the not-found page with a 404 status", async ({ page }) => {
  const response = await page.goto("/definitely-not-a-page");
  expect(response?.status()).toBe(404);
  await expect(page.getByRole("heading", { name: "Page not found" })).toBeVisible();
});

test.describe("signed-out access gates", () => {
  for (const path of [
    "/apply",
    "/editor",
    "/admin",
    "/admin/applications",
    "/admin/projects",
    "/admin/projects/new",
    "/admin/clients",
    "/admin/access-review",
    "/editor/projects/6f3c2d1e-0b4a-4c6d-8e9f-1a2b3c4d5e6f",
    "/editor/earnings",
    "/admin/earnings",
    "/admin/earnings/7a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d",
    "/admin/activity",
    "/notifications",
    "/mfa",
  ]) {
    test(`${path} redirects to sign-in and keeps the destination`, async ({ page }) => {
      await page.goto(path);
      await expect(page).toHaveURL(/\/sign-in\?next=/);
      expect(new URL(page.url()).searchParams.get("next")).toBe(path);
    });
  }
});
