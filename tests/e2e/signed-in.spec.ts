import { expect, test, type Page } from "@playwright/test";

import {
  activateEditor,
  confirmAssignmentAwaitingDeposit,
  confirmationLinkFor,
  createAdminWithTotp,
  createConfirmedUser,
  createOpenProject,
  createProjectWithOffer,
  freshTotp,
  registerInterestAs,
  resetInquiryThrottle,
  sql,
  TEST_PASSWORD,
  uniqueEmail,
  type TestUser,
} from "./support/local-stack";

// Signed-in flows against the LOCAL stack. Each test creates its own uniquely named accounts
// (e2e-…@example.test), so the suite needs no seed data and can be repeated; `npm run db:reset`
// clears the accumulated test accounts.

async function signIn(page: Page, user: Pick<TestUser, "email" | "password">) {
  await page.goto("/sign-in");
  // Wait for hydration so the click submits through the form action, not a bare GET.
  await page.waitForLoadState("networkidle");
  await page.getByLabel("Email").fill(user.email);
  await page.getByLabel("Password").fill(user.password);
  await page.getByRole("button", { name: "Sign in" }).click();
  // The redirect target may still be compiling under `next dev` when the suite runs in parallel.
  await expect(page).not.toHaveURL(/\/sign-in/, { timeout: 30_000 });
}

test("client inquiry submits without an account", async ({ page }) => {
  resetInquiryThrottle();
  await page.goto("/inquire");
  await page.waitForLoadState("networkidle");
  await page.getByLabel("Your name").fill("E2E Client");
  await page.getByLabel("Email").fill(uniqueEmail("client"));
  const service = page.getByLabel("Type of editing");
  await expect(service.locator("option")).not.toHaveCount(1);
  await service.selectOption({ index: 1 });
  await page.getByLabel("Project description").fill("A short promo edit for an e2e test run.");
  await page.locator('input[name="acceptPrivacy"]').check();
  await page.getByRole("button", { name: "Send inquiry" }).click();
  await expect(page.getByText("We've received your project details")).toBeVisible({
    timeout: 30_000,
  });
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
    await page.waitForLoadState("networkidle");
    await expect(page.getByText("Enter your verification code")).toBeVisible();
    await page
      .getByLabel("6-digit code")
      .fill(await freshTotp(admin.totpSecret, admin.enrolledStep));
    await page.getByRole("button", { name: "Verify", exact: true }).click();
    // /admin may still be compiling under `next dev` while tests run in parallel.
    await expect(page).toHaveURL(/\/admin$/, { timeout: 30_000 });

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
    await page.waitForLoadState("networkidle");
    await page
      .getByLabel("6-digit code")
      .fill(await freshTotp(admin.totpSecret, admin.enrolledStep));
    await page.getByRole("button", { name: "Verify", exact: true }).click();
    // /admin may still be compiling under `next dev` while tests run in parallel.
    await expect(page).toHaveURL(/\/admin$/, { timeout: 30_000 });

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
    await page.waitForLoadState("networkidle");
    await page
      .getByLabel("6-digit code")
      .fill(await freshTotp(admin.totpSecret, admin.enrolledStep));
    await page.getByRole("button", { name: "Verify", exact: true }).click();
    // /admin may still be compiling under `next dev` while tests run in parallel.
    await expect(page).toHaveURL(/\/admin$/, { timeout: 30_000 });

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

test.describe("cancellation settlement (Phase 12D part 2)", () => {
  test("a changed earned amount needs a reason; the typed amount is kept", async ({ browser }) => {
    test.setTimeout(150_000);
    const admin = await createAdminWithTotp();
    const editor = await createConfirmedUser("editor-settle");
    activateEditor(editor.id);
    const projectId = createProjectWithOffer(
      admin.id,
      editor.id,
      `E2E project settle ${Date.now()}`,
    );
    confirmAssignmentAwaitingDeposit(admin.id, editor.id, projectId, 20000, {
      stages: [{ stage: "assigned", editor_earned_percent: 10, client_charge_percent: 5 }],
    });

    const context = await browser.newContext();
    const page = await context.newPage();
    await signIn(page, admin);
    await page.goto("/mfa");
    await page.waitForLoadState("networkidle");
    await page
      .getByLabel("6-digit code")
      .fill(await freshTotp(admin.totpSecret, admin.enrolledStep));
    await page.getByRole("button", { name: "Verify", exact: true }).click();
    await expect(page).toHaveURL(/\/admin$/, { timeout: 30_000 });

    await page.goto(`/admin/projects/${projectId}`);
    await expect(page.getByText("Cancellation settlement")).toBeVisible();
    // 10% of the 5000 LKR agreed pay.
    const earned = page.getByLabel(/Editor earned, only to change the proposed 500 LKR/);
    await expect(earned).toBeVisible();
    await page.waitForLoadState("networkidle");
    await expect(async () => {
      await earned.fill("600");
      await page.getByRole("button", { name: "Cancel the project and settle" }).click();
      await page.getByRole("button", { name: "Confirm" }).click();
      await expect(
        page.getByText("Give the reason for changing the editor's earned amount."),
      ).toBeVisible({ timeout: 5_000 });
    }).toPass({ timeout: 30_000 });
    await expect(earned).toHaveValue("600");
    await expect(page.getByLabel("Reason for a changed amount")).toHaveAttribute(
      "aria-required",
      "true",
    );
    await context.close();
  });
});

test.describe("payout details (Phase 12E, locked)", () => {
  // The turn-on path is exercised and immediately reversed; never leave the flag on.
  test.afterEach(() => {
    sql(
      `insert into public.app_settings (key, value) values ('payout_details_enabled', 'false'::jsonb)
       on conflict (key) do update set value = 'false'::jsonb`,
    );
  });

  test("the editor sees 'not available yet'; the admin sees the PDPA warning and OFF", async ({
    browser,
  }) => {
    test.setTimeout(120_000);
    const admin = await createAdminWithTotp();
    const editor = await createConfirmedUser("editor-payout");
    activateEditor(editor.id);

    const editorContext = await browser.newContext();
    const editorPage = await editorContext.newPage();
    await signIn(editorPage, editor);
    await editorPage.goto("/editor/earnings");
    await expect(editorPage.getByRole("heading", { name: "Payout details" })).toBeVisible({
      timeout: 30_000,
    });
    await expect(editorPage.getByText("Not available yet")).toBeVisible();
    await expect(editorPage.getByLabel("Account number")).toHaveCount(0);
    await editorContext.close();

    const context = await browser.newContext();
    const page = await context.newPage();
    await signIn(page, admin);
    await page.goto("/mfa");
    await page.waitForLoadState("networkidle");
    await page
      .getByLabel("6-digit code")
      .fill(await freshTotp(admin.totpSecret, admin.enrolledStep));
    await page.getByRole("button", { name: "Verify", exact: true }).click();
    await expect(page).toHaveURL(/\/admin$/, { timeout: 30_000 });

    await page.goto("/admin/settings");
    await expect(page.getByText("Editor payout details")).toBeVisible({ timeout: 30_000 });
    await expect(page.getByText("OFF (locked)")).toBeVisible();
    await expect(
      page.getByText("Keep this OFF until counsel confirms PDPA handling."),
    ).toBeVisible();
    // Turning it on needs the confirmation box (nothing is changed here).
    await page.waitForLoadState("networkidle");
    await page.getByRole("button", { name: "Turn payout details on" }).click();
    await page.getByRole("button", { name: "Confirm" }).click();
    await expect(page.getByText("Tick the box to confirm.")).toBeVisible();
    await expect(page.getByText("OFF (locked)")).toBeVisible();

    // With the box ticked it turns on (no data is entered), then straight back off.
    await page.getByLabel(/Counsel has confirmed/).check();
    await page.getByRole("button", { name: "Turn payout details on" }).click();
    await page.getByRole("button", { name: "Confirm" }).click();
    await expect(page.getByText("Payout details are now ON.")).toBeVisible({ timeout: 30_000 });
    await expect(page.getByText("ON", { exact: true })).toBeVisible();
    await page.getByLabel("I want to lock payout details again.").check();
    await page.getByRole("button", { name: "Turn payout details off" }).click();
    await page.getByRole("button", { name: "Confirm" }).click();
    await expect(page.getByText("OFF (locked)", { exact: true })).toBeVisible({ timeout: 30_000 });

    await page.goto(`/admin/earnings?editor=${editor.id}`);
    await expect(page.getByRole("heading", { name: /^Payout account/ })).toBeVisible({
      timeout: 30_000,
    });
    await expect(page.getByText("Marking paid:")).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Record: verified outside the app" }),
    ).toBeVisible();
    await context.close();
  });
});

test.describe("open opportunities", () => {
  test("publish, register interest, choose one editor; the other sees Not selected", async ({
    browser,
  }) => {
    test.setTimeout(180_000);
    const admin = await createAdminWithTotp();
    const [editorA, editorB] = await Promise.all([
      createConfirmedUser("editor-opp-a"),
      createConfirmedUser("editor-opp-b"),
    ]);
    activateEditor(editorA.id);
    activateEditor(editorB.id);
    const suffix = Date.now();
    // The project title stands in for client-identifying text: editors must never see it.
    const projectTitle = `E2E project CLIENTNAME ${suffix}`;
    const summaryTitle = `Promo cut ${suffix}`;
    const projectId = createOpenProject(projectTitle);

    // Admin publishes a summary (pay hidden).
    const adminContext = await browser.newContext();
    const page = await adminContext.newPage();
    await signIn(page, admin);
    await page.goto("/mfa");
    await page.waitForLoadState("networkidle");
    await page
      .getByLabel("6-digit code")
      .fill(await freshTotp(admin.totpSecret, admin.enrolledStep));
    await page.getByRole("button", { name: "Verify", exact: true }).click();
    await expect(page).toHaveURL(/\/admin$/, { timeout: 30_000 });
    await page.goto(`/admin/projects/${projectId}`);
    await expect(page.getByText("Open opportunity", { exact: true })).toBeVisible({
      timeout: 30_000,
    });
    await page.waitForLoadState("networkidle");
    await page.getByLabel("Title editors see").fill(summaryTitle);
    await page.getByLabel("Deliverables summary").fill("One 60 second cut and a 15 second teaser.");
    // Retried for hydration; once published the form becomes the edit form ("Save summary").
    const saveSummary = page.getByRole("button", { name: "Save summary" });
    await expect(async () => {
      if ((await saveSummary.count()) === 0) {
        await page
          .getByRole("button", { name: "Publish to active editors" })
          .click({ timeout: 5_000 });
        await page.getByRole("button", { name: "Confirm" }).click({ timeout: 5_000 });
      }
      await expect(saveSummary).toBeVisible({ timeout: 15_000 });
    }).toPass({ timeout: 60_000 });
    await expect(
      page.getByText("Published. Active editors can now see the summary."),
    ).toBeVisible();

    // Editor A registers interest with a proposed rate; editor B registers without one.
    const contextA = await browser.newContext();
    const pageA = await contextA.newPage();
    await signIn(pageA, editorA);
    await pageA.goto("/editor/opportunities");
    await expect(pageA.getByText(summaryTitle)).toBeVisible({ timeout: 30_000 });
    await expect(pageA.getByText(/These summaries are confidential/)).toBeVisible();
    await expect(pageA.getByText("CLIENTNAME")).toHaveCount(0);
    await pageA.waitForLoadState("networkidle");
    // Other runs may have open opportunities too: act only inside this one's card.
    const cardA = pageA.getByRole("listitem").filter({ hasText: summaryTitle });
    await cardA.getByLabel("Your proposed rate (optional)").fill("30000");
    await cardA.getByLabel("Short note (optional)").fill("Cut similar promos last month.");
    // Retried for hydration; once registered the form is replaced by the status and Withdraw.
    const interested = cardA.getByText("Interested", { exact: true });
    await expect(async () => {
      if ((await interested.count()) === 0) {
        await cardA.getByRole("button", { name: "Register interest" }).click({ timeout: 5_000 });
      }
      await expect(interested).toBeVisible({ timeout: 15_000 });
    }).toPass({ timeout: 60_000 });
    await expect(
      cardA.getByText("Your interest: proposed 30,000 LKR", { exact: false }),
    ).toBeVisible();
    await expect(cardA.getByRole("button", { name: "Withdraw interest" })).toBeVisible();
    registerInterestAs(editorB.id, projectId);

    // Admin sees both and chooses editor A through the offer fields.
    await page.reload();
    await expect(page.getByRole("heading", { name: "Interested editors (2)" })).toBeVisible({
      timeout: 30_000,
    });
    await expect(page.getByText("Proposed 30,000 LKR (a signal only)")).toBeVisible();
    await page.waitForLoadState("networkidle");
    const firstChoose = page.getByRole("button", { name: "Choose this editor" }).first();
    const chosen = page.getByText(/^An editor was chosen on/);
    await expect(async () => {
      if ((await chosen.count()) === 0) {
        await firstChoose.click({ timeout: 5_000 });
        await page.getByRole("button", { name: "Confirm" }).click({ timeout: 5_000 });
      }
      await expect(chosen).toBeVisible({ timeout: 15_000 });
    }).toPass({ timeout: 60_000 });
    await adminContext.close();

    // The first listed interest is the earliest: editor A. A sees Selected, B sees Not selected.
    await pageA.reload();
    await expect(cardA.getByText("Selected", { exact: true })).toBeVisible({ timeout: 30_000 });
    await cardA.getByRole("link", { name: "Open the project" }).click();
    await expect(pageA).toHaveURL(new RegExp(`/editor/projects/${projectId}$`));
    await contextA.close();

    const contextB = await browser.newContext();
    const pageB = await contextB.newPage();
    await signIn(pageB, editorB);
    await pageB.goto("/editor/opportunities");
    await expect(pageB.getByText(summaryTitle)).toBeVisible({ timeout: 30_000 });
    const cardB = pageB.getByRole("listitem").filter({ hasText: summaryTitle });
    await expect(cardB.getByText("Not selected", { exact: true })).toBeVisible();
    await expect(cardB.getByRole("button", { name: "Register interest" })).toHaveCount(0);
    // Works at 375px without horizontal scroll.
    await pageB.setViewportSize({ width: 375, height: 812 });
    await expect(pageB.getByText(summaryTitle)).toBeVisible();
    expect(
      await pageB.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
    ).toBe(true);
    await contextB.close();
  });
});
