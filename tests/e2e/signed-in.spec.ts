import { expect, test, type Page } from "@playwright/test";

import {
  activateEditor,
  confirmationLinkFor,
  createAdminWithTotp,
  createConfirmedUser,
  createProjectWithOffer,
  freshTotp,
  resetInquiryThrottle,
  TEST_PASSWORD,
  uniqueEmail,
  type TestUser,
} from "./support/local-stack";

// Signed-in flows against the LOCAL stack. Each test creates its own uniquely named accounts
// (e2e-…@example.test), so the suite needs no seed data and can be repeated; `npm run db:reset`
// clears the accumulated test accounts.

async function signIn(page: Page, user: Pick<TestUser, "email" | "password">) {
  await page.goto("/sign-in");
  await page.getByLabel("Email").fill(user.email);
  await page.getByLabel("Password").fill(user.password);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page).not.toHaveURL(/\/sign-in/);
}

test("client inquiry submits without an account", async ({ page }) => {
  resetInquiryThrottle();
  await page.goto("/inquire");
  await page.getByLabel("Your name").fill("E2E Client");
  await page.getByLabel("Email").fill(uniqueEmail("client"));
  const service = page.getByLabel("Type of editing");
  await expect(service.locator("option")).not.toHaveCount(1);
  await service.selectOption({ index: 1 });
  await page.getByLabel("Project description").fill("A short promo edit for an e2e test run.");
  await page.locator('input[name="acceptPrivacy"]').check();
  await page.getByRole("button", { name: "Send inquiry" }).click();
  await expect(page.getByText("We've received your project details")).toBeVisible();
});

test.describe("pending applicant", () => {
  test("sign-up, email confirmation, gated /apply; /editor and /admin stay closed", async ({
    page,
  }) => {
    const email = uniqueEmail("applicant");
    await page.goto("/sign-up");
    await page.getByLabel("Email").fill(email);
    await page.getByLabel("Password", { exact: true }).fill(TEST_PASSWORD);
    await page.getByLabel("Confirm password").fill(TEST_PASSWORD);
    await page.getByRole("button", { name: "Create account" }).click();
    await expect(page.getByRole("button", { name: "Create account" })).toHaveCount(0);

    await page.goto(await confirmationLinkFor(email));
    await expect(page).toHaveURL(/\/apply$/);
    await expect(page.getByRole("heading", { name: "Your editor application" })).toBeVisible();

    for (const path of ["/editor", "/editor/earnings", "/admin", "/admin/projects"]) {
      await page.goto(path);
      await expect(page).toHaveURL(/\/apply$/);
    }
  });
});

test.describe("active editors", () => {
  test("each editor sees only their own offered project", async ({ browser }) => {
    test.setTimeout(90_000);
    const admin = await createAdminWithTotp();
    const [editorA, editorB] = await Promise.all([
      createConfirmedUser("editor-a"),
      createConfirmedUser("editor-b"),
    ]);
    activateEditor(editorA.id);
    activateEditor(editorB.id);
    const suffix = Date.now();
    const titleA = `E2E project A ${suffix}`;
    const titleB = `E2E project B ${suffix}`;
    createProjectWithOffer(admin.id, editorA.id, titleA);
    const projectB = createProjectWithOffer(admin.id, editorB.id, titleB);

    const context = await browser.newContext();
    const page = await context.newPage();
    await signIn(page, editorA);
    await expect(page).toHaveURL(/\/editor$/);
    await expect(page.getByRole("link", { name: titleA })).toBeVisible();
    await expect(page.getByText(titleB)).toHaveCount(0);

    // Another editor's project by direct URL: not found, never its data.
    // (The page streams inside <Suspense>, so notFound() renders the 404 UI with a 200 status.)
    await page.goto(`/editor/projects/${projectB}`);
    await expect(page.getByRole("heading", { name: "Page not found" })).toBeVisible();
    await expect(page.getByText(titleB)).toHaveCount(0);

    // Active editors are still not admins.
    await page.goto("/admin");
    await expect(page).toHaveURL(/\/editor$/);
    await context.close();
  });
});

test.describe("admin with MFA", () => {
  test("password alone is not enough; a TOTP code opens the admin area", async ({ page }) => {
    test.setTimeout(90_000);
    const admin = await createAdminWithTotp();

    await signIn(page, admin);
    await expect(page).toHaveURL(/\/mfa/);
    await page.goto("/admin/activity");
    await expect(page).toHaveURL(/\/mfa/);

    await page.goto("/mfa");
    await expect(page.getByText("Enter your verification code")).toBeVisible();
    await page
      .getByLabel("6-digit code")
      .fill(await freshTotp(admin.totpSecret, admin.enrolledStep));
    await page.getByRole("button", { name: "Verify", exact: true }).click();
    await expect(page).toHaveURL(/\/admin$/);

    await page.goto("/admin/activity");
    await expect(page).toHaveURL(/\/admin\/activity$/);
    await expect(page.getByRole("heading").first()).toBeVisible();
  });
});
