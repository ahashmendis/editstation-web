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

test.describe("signed-out access gates", () => {
  for (const path of ["/apply", "/editor", "/admin", "/admin/applications", "/mfa"]) {
    test(`${path} redirects to sign-in and keeps the destination`, async ({ page }) => {
      await page.goto(path);
      await expect(page).toHaveURL(/\/sign-in\?next=/);
      expect(new URL(page.url()).searchParams.get("next")).toBe(path);
    });
  }
});
