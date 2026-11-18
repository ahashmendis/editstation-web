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
  openProjectAsAdmin,
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

  test("a client sends a new project; the admin sees it from the client and converts it", async ({
    browser,
  }) => {
    test.setTimeout(180_000);
    const admin = await createAdminWithTotp();
    const suffix = Date.now();
    const clientName = `E2E Client R ${suffix}`;
    const client = createE2eClient(clientName);
    const email = await inviteClientUserDirect(admin.id, client, "client-r");
    const description = `E2E request ${suffix}: a launch film for our new product.`;
    const projectTitle = `E2E project from request ${suffix}`;

    // Client: New project from the overview; a validation error keeps the input.
    const cContext = await browser.newContext();
    const cPage = await cContext.newPage();
    await clientSignIn(cPage, email);
    await cPage.getByRole("main").getByRole("link", { name: "New project" }).click();
    await expect(cPage).toHaveURL(/\/client\/projects\/new$/, { timeout: 30_000 });
    await cPage.waitForLoadState("networkidle");
    await expect(cPage.getByLabel("Type of editing")).toBeVisible({ timeout: 30_000 });
    await expect(cPage.getByRole("textbox", { name: "Email", exact: true })).toHaveCount(0);
    await cPage.getByLabel("Type of editing").selectOption("long_form");
    await cPage.getByLabel("Expected deliverables (optional)").fill("One 3-minute film");
    await cPage.getByRole("button", { name: "Send request" }).click();
    await expect(cPage.getByText("Please fix the highlighted fields.")).toBeVisible({
      timeout: 30_000,
    });
    await expect(cPage.getByLabel("Expected deliverables (optional)")).toHaveValue(
      "One 3-minute film",
    );
    await cPage.getByLabel("Project description").fill(description);
    await cPage.getByLabel("When would you like it by? (optional)").fill("2099-03-01");
    await cPage.getByLabel("Link 1", { exact: true }).fill("https://example.com/style");
    await cPage.getByRole("checkbox", { name: /privacy notice/ }).check();
    await cPage.getByRole("button", { name: "Send request" }).click();
    await expect(cPage.getByText("The studio will review your request")).toBeVisible({
      timeout: 30_000,
    });
    await cPage.getByRole("link", { name: "See my requests" }).click();
    await expect(cPage).toHaveURL(/\/client\/requests$/);
    const request = cPage.getByTestId("client-request").filter({ hasText: description });
    await expect(request).toBeVisible();
    await expect(request.getByText("Received", { exact: true })).toBeVisible();
    await expect(request.getByRole("link", { name: "Open the project" })).toHaveCount(0);

    // 375px: no horizontal scroll on the new pages.
    await cPage.setViewportSize({ width: 375, height: 812 });
    for (const path of ["/client/projects/new", "/client/requests"]) {
      await cPage.goto(path);
      await expect(cPage.getByRole("heading").first()).toBeVisible();
      await noHorizontalScroll(cPage);
    }
    await cPage.setViewportSize({ width: 1280, height: 800 });

    // Admin: the lead is marked as coming from the client account, and converts it.
    const adminContext = await browser.newContext();
    const adminPage = await adminContext.newPage();
    await adminSignIn(adminPage, admin);
    await adminPage.goto("/admin/inquiries");
    await expect(
      adminPage.getByText(`From client: ${clientName} (client account)`).first(),
    ).toBeVisible();
    await adminPage.getByRole("link", { name: clientName }).first().click();
    await expect(adminPage).toHaveURL(/\/admin\/inquiries\/[0-9a-f-]{36}$/, { timeout: 30_000 });
    await expect(adminPage.getByText(description)).toBeVisible({ timeout: 30_000 });
    await expect(
      adminPage.getByText(`${clientName} (client account)`, { exact: true }),
    ).toBeVisible();
    await adminPage.waitForLoadState("networkidle");
    await adminPage.getByLabel("Project title (optional)").fill(projectTitle);
    await adminPage.getByLabel("Brief type").selectOption("fully_instructed");
    await expect(adminPage.getByLabel("Client", { exact: true })).toHaveCount(0);
    await adminPage.getByRole("button", { name: "Convert to project" }).click();
    // Conversion plus the redirect compiles the admin project page under `next dev`: allow time.
    await expect(adminPage).toHaveURL(/\/admin\/projects\/[0-9a-f-]{36}$/, { timeout: 60_000 });
    const projectId = adminPage.url().split("/").at(-1)!;
    expect(
      sql(`select client_id from public.project_internal where project_id = ${lit(projectId)};`),
    ).toBe(client);
    await adminContext.close();

    // Client: accepted; once the studio opens the project it is linked and listed.
    await cPage.goto("/client/requests");
    await expect(request.getByText("Accepted as a project")).toBeVisible();
    await expect(request.getByRole("link", { name: "Open the project" })).toHaveCount(0);
    openProjectAsAdmin(admin.id, projectId);
    await cPage.reload();
    await request.getByRole("link", { name: "Open the project" }).click();
    await expect(cPage).toHaveURL(new RegExp(`/client/projects/${projectId}$`), {
      timeout: 30_000,
    });
    await expect(cPage.getByRole("heading", { name: projectTitle })).toBeVisible();
    await cPage.goto("/client/projects");
    await expect(cPage.getByRole("link", { name: projectTitle })).toBeVisible();
    await cContext.close();
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
