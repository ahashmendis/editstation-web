import { expect, test, type Page } from "@playwright/test";

import {
  createAdminWithTotp,
  createClientProject,
  createDraftClientProject,
  createE2eClient,
  freshTotp,
  inviteClientUserDirect,
  revokeClientUserDirect,
  signInCodeFor,
  sql,
  lit,
  uniqueEmail,
  type AdminUser,
} from "./support/local-stack";

// Client area C1 against the LOCAL stack: admin invites a client user, the client signs in with
// the emailed code (read from Mailpit), sees only their own projects and payments, a second
// client cannot see the first's project, and the pages fit 375px.

async function adminSignIn(page: Page, admin: AdminUser) {
  await page.goto("/sign-in");
  await page.waitForLoadState("networkidle");
  await page.getByLabel("Email").fill(admin.email);
  await page.getByLabel("Password").fill(admin.password);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page).toHaveURL(/\/mfa/, { timeout: 30_000 });
  await page.waitForLoadState("networkidle");
  await page.getByLabel("6-digit code").fill(await freshTotp(admin.totpSecret, admin.enrolledStep));
  await page.getByRole("button", { name: "Verify", exact: true }).click();
  await expect(page).toHaveURL(/\/admin$/, { timeout: 30_000 });
}

async function clientSignIn(page: Page, email: string) {
  await page.goto("/client/sign-in");
  await page.waitForLoadState("networkidle");
  await page.getByLabel("Email").fill(email);
  await page.getByRole("button", { name: "Email me a sign-in code" }).click();
  await expect(page.getByLabel("8-digit code")).toBeVisible({ timeout: 30_000 });
  await page.getByLabel("8-digit code").fill(await signInCodeFor(email));
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await expect(page).toHaveURL(/\/client$/, { timeout: 30_000 });
}

async function noHorizontalScroll(page: Page) {
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(
    true,
  );
}

test.describe("client area (C1)", () => {
  test("admin invites; the client signs in by code and sees only their own projects and payments", async ({
    browser,
  }) => {
    test.setTimeout(180_000);
    const admin = await createAdminWithTotp();
    const suffix = Date.now();
    const clientX = createE2eClient(`E2E Client X ${suffix}`);
    const clientY = createE2eClient(`E2E Client Y ${suffix}`);
    const titleX = `E2E project client X ${suffix}`;
    const titleY = `E2E project client Y ${suffix}`;
    const projectX = createClientProject(admin.id, clientX, titleX, 50000);
    const projectY = createClientProject(admin.id, clientY, titleY, 30000);
    // A draft project of client X: never shown to the client.
    const titleDraft = `E2E project client X draft ${suffix}`;
    const projectDraft = createDraftClientProject(clientX, titleDraft);
    const emailY = await inviteClientUserDirect(admin.id, clientY, "client-y");

    // Admin invites the client X user on the client record and publishes an update.
    const emailX = uniqueEmail("client-x");
    const adminContext = await browser.newContext();
    const adminPage = await adminContext.newPage();
    await adminSignIn(adminPage, admin);
    await adminPage.goto("/admin/clients");
    const summary = adminPage.locator("summary", { hasText: `E2E Client X ${suffix}` });
    await summary.click();
    await adminPage.waitForLoadState("networkidle");
    const record = adminPage.locator("details").filter({ has: summary });
    await record.getByLabel("Email of the person to invite").fill(emailX);
    await expect(async () => {
      await record.getByRole("button", { name: "Invite client user" }).click();
      await expect(record.getByText("Client access added.")).toBeVisible({ timeout: 5_000 });
    }).toPass({ timeout: 30_000 });
    await expect(record.getByText(emailX, { exact: true })).toBeVisible();

    await adminPage.goto(`/admin/projects/${projectX}`);
    await adminPage.waitForLoadState("networkidle");
    await adminPage.getByLabel("New update for the client").fill("E2E rough cut is underway.");
    await expect(async () => {
      await adminPage.getByRole("button", { name: "Publish update" }).click();
      await expect(adminPage.getByText("Update published to the client.")).toBeVisible({
        timeout: 5_000,
      });
    }).toPass({ timeout: 30_000 });
    await adminContext.close();

    // Client X: code sign-in, own project and payments only.
    const xContext = await browser.newContext();
    const xPage = await xContext.newPage();
    await clientSignIn(xPage, emailX);
    await expect(xPage.getByRole("link", { name: titleX })).toBeVisible();
    await expect(xPage.getByText(titleY)).toHaveCount(0);
    await expect(xPage.getByText(titleDraft)).toHaveCount(0);
    await expect(
      xPage.getByRole("link", { name: "EDITSTATION dashboard" }).first(),
    ).toHaveAttribute("href", "/client");
    // No editor or admin links in the client navigation.
    await expect(xPage.locator('a[href^="/editor"], a[href^="/admin"]')).toHaveCount(0);

    await xPage.goto(`/client/projects/${projectX}`);
    await expect(xPage.getByRole("heading", { name: titleX })).toBeVisible();
    await expect(xPage.getByText("Planning").first()).toBeVisible();
    await expect(xPage.getByText("E2E rough cut is underway.")).toBeVisible();
    await expect(xPage.getByText("Main film")).toBeVisible();
    await expect(xPage.getByText("25,000.00 LKR").first()).toBeVisible();
    // No deadline is shown to clients in C1 (the project's deadline is 31 Dec 2099).
    await expect(xPage.getByText("2099")).toHaveCount(0);

    await xPage.goto("/client/projects");
    await expect(xPage.getByRole("link", { name: titleX })).toBeVisible();
    await expect(xPage.getByText(titleDraft)).toHaveCount(0);
    await xPage.goto(`/client/projects/${projectDraft}`);
    await expect(xPage.getByRole("heading", { name: /not found/i })).toBeVisible();

    await xPage.goto("/client/payments");
    await expect(xPage.getByRole("link", { name: titleX })).toBeVisible();
    await expect(xPage.getByText("15,000.00 LKR")).toHaveCount(0);

    // Client X cannot open client Y's project, and other areas send them home.
    await xPage.goto(`/client/projects/${projectY}`);
    await expect(xPage.getByText(titleY)).toHaveCount(0);
    await expect(xPage.getByRole("heading", { name: /not found|couldn.t find/i })).toBeVisible();
    for (const path of ["/editor", "/apply", "/admin"]) {
      await xPage.goto(path);
      await expect(xPage).toHaveURL(/\/client$/);
    }

    // 375px: no horizontal scroll on the client pages.
    await xPage.setViewportSize({ width: 375, height: 812 });
    for (const path of [
      "/client",
      "/client/projects",
      `/client/projects/${projectX}`,
      "/client/payments",
    ]) {
      await xPage.goto(path);
      await expect(xPage.getByRole("heading").first()).toBeVisible();
      await noHorizontalScroll(xPage);
    }
    await xPage.setViewportSize({ width: 1280, height: 800 });

    // Client Y: sees only their project; client X's is not available.
    const yContext = await browser.newContext();
    const yPage = await yContext.newPage();
    await clientSignIn(yPage, emailY);
    await expect(yPage.getByRole("link", { name: titleY })).toBeVisible();
    await expect(yPage.getByText(titleX)).toHaveCount(0);
    await yPage.goto(`/client/projects/${projectX}`);
    await expect(yPage.getByText(titleX)).toHaveCount(0);
    await yPage.goto("/client/payments");
    await expect(yPage.getByText("15,000.00 LKR").first()).toBeVisible();
    await expect(yPage.getByText("25,000.00 LKR")).toHaveCount(0);
    await yContext.close();

    // Revocation applies on the next request.
    revokeClientUserDirect(admin.id, emailX);
    await xPage.goto("/client/projects");
    await expect(xPage).toHaveURL(/\/client\/access-ended$/);
    await expect(xPage.getByText(titleX)).toHaveCount(0);
    await xContext.close();
  });

  test("the code sign-in never creates an account and never says whether an email is invited", async ({
    page,
  }) => {
    const email = uniqueEmail("not-invited");
    await page.goto("/client/sign-in");
    await page.waitForLoadState("networkidle");
    await page.getByLabel("Email").fill(email);
    await page.getByRole("button", { name: "Email me a sign-in code" }).click();
    await expect(page.getByText("If this email has client access")).toBeVisible({
      timeout: 30_000,
    });
    await expect(page.getByLabel("8-digit code")).toBeVisible();
    expect(sql(`select count(*) from auth.users where email = ${lit(email)};`)).toBe("0");
  });
});
