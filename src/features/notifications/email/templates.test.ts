import { afterEach, describe, expect, it, vi } from "vitest";

import { escapeHtml } from "./layout";
import { INDIVIDUAL_BODY_TEXT, renderAdminDigestEmail, renderIndividualEmail } from "./templates";

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("escapeHtml", () => {
  it("escapes the five HTML special characters", () => {
    expect(escapeHtml(`<a href="x">'&'</a>`)).toBe(
      "&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;",
    );
  });
});

describe("renderIndividualEmail", () => {
  it("uses the title as subject and heading, escaped in HTML", () => {
    const email = renderIndividualEmail({ title: `Revision <b>"requested"</b>` });
    expect(email.subject).toBe(`Revision <b>"requested"</b>`);
    expect(email.html).toContain("Revision &lt;b&gt;&quot;requested&quot;&lt;/b&gt;");
    expect(email.html).not.toContain("<b>");
  });

  it("has the fixed body text, the wordmark and a link to /notifications from SITE_URL", () => {
    vi.stubEnv("SITE_URL", "https://www.editstation.work/");
    const email = renderIndividualEmail({ title: "Project invitation" });
    expect(email.html).toContain(INDIVIDUAL_BODY_TEXT);
    expect(email.html).toContain('EDIT<span style="color: #7a2fd0">STATION</span>');
    expect(email.html).toContain('href="https://www.editstation.work/notifications"');
    expect(email.text).toContain(INDIVIDUAL_BODY_TEXT);
    expect(email.text).toContain("https://www.editstation.work/notifications");
    expect(email.text).not.toMatch(/<[a-z]/i);
  });

  it("never takes a notification body, even if one is passed by mistake", () => {
    const leaky = {
      title: "Payment marked paid",
      body: 'A payment for "Secret Project" was paid.',
    };
    const email = renderIndividualEmail(leaky);
    expect(email.html).not.toContain("Secret Project");
    expect(email.text).not.toContain("Secret Project");
  });

  it("keeps the subject on one short line", () => {
    const email = renderIndividualEmail({ title: `Line one\r\nBcc: x@y.z ${"a".repeat(300)}` });
    expect(email.subject).not.toMatch(/[\r\n]/);
    expect(email.subject.length).toBeLessThanOrEqual(150);
  });
});

describe("renderAdminDigestEmail", () => {
  it("lists counts per kind with readable labels and a total in the subject", () => {
    const email = renderAdminDigestEmail({ counts: { inquiry_new: 2, submission: 1 } });
    expect(email.subject).toBe("EDITSTATION daily summary: 3 new updates");
    expect(email.html).toContain("New client inquiries: <strong>2</strong>");
    expect(email.html).toContain("Work submissions: <strong>1</strong>");
    expect(email.text).toContain("- New client inquiries: 2");
    expect(email.text).toContain("- Work submissions: 1");
  });

  it("uses the singular for one update and a generic label for an unknown kind", () => {
    const email = renderAdminDigestEmail({ counts: { "<script>": 1 } });
    expect(email.subject).toBe("EDITSTATION daily summary: 1 new update");
    expect(email.html).toContain("Other updates: <strong>1</strong>");
    expect(email.html).not.toContain("<script>");
  });

  it("ignores non-positive or non-integer counts", () => {
    const email = renderAdminDigestEmail({ counts: { inquiry_new: 0, submission: 1.5 } });
    expect(email.subject).toBe("EDITSTATION daily summary: 0 new updates");
    expect(email.html).not.toContain("<strong>");
  });

  it("links to /notifications", () => {
    vi.stubEnv("SITE_URL", "https://www.editstation.work");
    const email = renderAdminDigestEmail({ counts: { counteroffer: 1 } });
    expect(email.html).toContain('href="https://www.editstation.work/notifications"');
  });
});
