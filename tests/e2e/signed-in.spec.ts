import { expect, test, type Page } from "@playwright/test";

import {
  activateEditor,
  confirmAssignmentAwaitingDeposit,
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

test.describe("project terms (Phase 12A)", () => {
  test("admin saves and agrees terms; the editor sees only the editor-safe summary", async ({
    browser,
  }) => {
    test.setTimeout(120_000);
    const admin = await createAdminWithTotp();
    const editor = await createConfirmedUser("editor-terms");
    activateEditor(editor.id);
    const title = `E2E project terms ${Date.now()}`;
    const projectId = createProjectWithOffer(admin.id, editor.id, title);

    const adminContext = await browser.newContext();
    const page = await adminContext.newPage();
    await signIn(page, admin);
    await page.goto("/mfa");
    await page
      .getByLabel("6-digit code")
      .fill(await freshTotp(admin.totpSecret, admin.enrolledStep));
    await page.getByRole("button", { name: "Verify", exact: true }).click();
    await expect(page).toHaveURL(/\/admin$/);

    await page.goto(`/admin/projects/${projectId}`);
    await expect(page.getByRole("heading", { name: "No terms agreed yet" })).toBeVisible();
    await page.waitForLoadState("networkidle");
    await page.getByLabel("Client charge per extra round").fill("7777");
    // Retried: under a parallel run the click can land before the form has hydrated. Saving the
    // same draft twice is harmless.
    await expect(async () => {
      await page.getByRole("button", { name: "Save draft" }).click();
      await expect(page.getByText("Terms draft saved.")).toBeVisible({ timeout: 5_000 });
    }).toPass({ timeout: 30_000 });
    // The refreshed draft summary shows the saved charge before agreeing.
    await expect(page.getByText("7777 LKR").first()).toBeVisible();
    await page.getByRole("button", { name: "Agree version 1" }).click();
    await page.getByRole("button", { name: "Confirm" }).click();
    await expect(page.getByRole("heading", { name: "In force: version 1" })).toBeVisible({
      timeout: 30_000,
    });
    await adminContext.close();

    const editorContext = await browser.newContext();
    const editorPage = await editorContext.newPage();
    await signIn(editorPage, editor);
    await editorPage.goto(`/editor/projects/${projectId}`);
    await expect(editorPage.getByText("Agreed terms, version 1.")).toBeVisible();
    await expect(editorPage.getByText("Included client revision rounds")).toBeVisible();
    await expect(editorPage.getByText("50% / 50% of your agreed pay")).toBeVisible();
    await expect(editorPage.getByText("7777")).toHaveCount(0);
    await editorContext.close();
  });
});

test.describe("client billing (Phase 12C)", () => {
  test("work waits for a verified client deposit; the editor sees only a status", async ({
    browser,
  }) => {
    test.setTimeout(150_000);
    const admin = await createAdminWithTotp();
    const editor = await createConfirmedUser("editor-billing");
    activateEditor(editor.id);
    const title = `E2E project billing ${Date.now()}`;
    const projectId = createProjectWithOffer(admin.id, editor.id, title);
    confirmAssignmentAwaitingDeposit(admin.id, editor.id, projectId, 86420);

    const editorContext = await browser.newContext();
    const editorPage = await editorContext.newPage();
    await signIn(editorPage, editor);
    await editorPage.goto(`/editor/projects/${projectId}`);
    await expect(editorPage.getByText("Waiting for the client deposit").first()).toBeVisible();
    await expect(editorPage.getByText("86420")).toHaveCount(0);
    await expect(editorPage.getByText("43210")).toHaveCount(0);

    const adminContext = await browser.newContext();
    const page = await adminContext.newPage();
    await signIn(page, admin);
    await page.goto("/mfa");
    await page
      .getByLabel("6-digit code")
      .fill(await freshTotp(admin.totpSecret, admin.enrolledStep));
    await page.getByRole("button", { name: "Verify", exact: true }).click();
    await expect(page).toHaveURL(/\/admin$/);

    await page.goto(`/admin/projects/${projectId}`);
    await expect(page.getByText("No client milestones yet")).toBeVisible();
    await page.waitForLoadState("networkidle");
    // Retried: the click can land before the form has hydrated; the database refuses nothing here.
    await expect(async () => {
      await page.getByRole("button", { name: "Create milestones" }).click();
      await expect(page.getByText("2 client milestones created.")).toBeVisible({ timeout: 5_000 });
    }).toPass({ timeout: 30_000 });
    await expect(page.getByText("1. Deposit (50%): 43210 LKR")).toBeVisible();

    await page.getByRole("button", { name: "Mark invoice issued" }).first().click();
    await page.getByRole("button", { name: "Confirm" }).click();
    // The issue form disappears once the invoice is recorded; the milestone shows the issue date.
    await expect(page.getByText(/^Issued /)).toBeVisible({ timeout: 30_000 });

    await page.getByLabel("Transfer reference").first().fill("E2E-BANK-1");
    await page.getByRole("button", { name: "Record transfer" }).first().click();
    await expect(page.getByText("Received, not verified")).toBeVisible({ timeout: 30_000 });
    await page.getByRole("button", { name: "Verify transfer" }).click();
    await page.getByRole("button", { name: "Confirm" }).click();
    await expect(page.getByText("Deposit verified", { exact: true })).toBeVisible({
      timeout: 30_000,
    });
    await adminContext.close();

    await editorPage.reload();
    await expect(editorPage.getByText("Ready to start")).toBeVisible();
    await expect(editorPage.getByText("E2E-BANK-1")).toHaveCount(0);
    await editorContext.close();
  });
});
