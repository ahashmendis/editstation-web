import type { NotificationKind } from "@/features/notifications/constants";
import { siteUrl } from "@/lib/seo/site";

import { EMAIL_FOOTER_TEXT, escapeHtml, paragraphRow, renderEmailLayout } from "./layout";

/**
 * Notification email content (spec 2026-11-17 §A, decision 2). The subject and heading are the
 * notification title; the body is fixed text and a sign-in link to /notifications. The
 * notification body is never an input here: it can name a project. Admin summaries carry counts
 * per kind only.
 */

export type RenderedEmail = { subject: string; html: string; text: string };

export const INDIVIDUAL_BODY_TEXT = "Open EDITSTATION to read the details";
const BUTTON_LABEL = "Open notifications";

export function notificationsUrl(): string {
  return `${siteUrl()}/notifications`;
}

/** Keeps the subject one short line whatever the title holds. */
function subjectLine(title: string): string {
  const oneLine = title.replace(/\s+/g, " ").trim();
  return oneLine.length > 150 ? `${oneLine.slice(0, 149)}…` : oneLine || "EDITSTATION update";
}

export function renderIndividualEmail(input: { title: string }): RenderedEmail {
  const subject = subjectLine(input.title);
  const href = notificationsUrl();
  const html = renderEmailLayout({
    preheader: `${INDIVIDUAL_BODY_TEXT}.`,
    heading: subject,
    rowsHtml: paragraphRow(`${INDIVIDUAL_BODY_TEXT}.`),
    buttonLabel: BUTTON_LABEL,
    buttonHref: href,
  });
  const text = [
    "EDITSTATION",
    "",
    subject,
    "",
    `${INDIVIDUAL_BODY_TEXT}:`,
    href,
    "",
    EMAIL_FOOTER_TEXT,
  ].join("\n");
  return { subject, html, text };
}

/** Plural labels for the admin summary. Typed against the enum so a new kind must be added. */
export const DIGEST_KIND_LABELS: Record<NotificationKind, string> = {
  inquiry_new: "New client inquiries",
  application_new: "New editor applications",
  applicant_response: "Applicant responses",
  counteroffer: "Counteroffers",
  submission: "Work submissions",
  asset_inaccessible: "Inaccessible asset reports",
  project_auto_held: "Projects put on hold automatically",
  late_balance_payable: "Late-balance payments due",
  adjustment_answered: "Adjustment answers",
  payout_details_changed: "Payout detail changes",
  interest_registered: "Opportunity interest",
  application_decision: "Application decisions",
  application_request: "Application requests",
  invitation: "Project invitations",
  assignment_confirmed: "Confirmed assignments",
  revision_requested: "Revision requests",
  payment_paid: "Payments marked paid",
  adjustment_offered: "Adjustment offers",
  opportunity_selected: "Opportunity selections",
  opportunity_not_selected: "Opportunities closed",
};

function kindLabel(kind: string): string {
  return Object.hasOwn(DIGEST_KIND_LABELS, kind)
    ? DIGEST_KIND_LABELS[kind as NotificationKind]
    : "Other updates";
}

/** counts: kind -> number, as returned by worker_claim_admin_digest. */
export function renderAdminDigestEmail(input: { counts: Record<string, number> }): RenderedEmail {
  const lines = Object.entries(input.counts)
    .filter(([, n]) => Number.isInteger(n) && n > 0)
    .map(([kind, n]) => ({ label: kindLabel(kind), n }))
    .sort((a, b) => a.label.localeCompare(b.label));
  const total = lines.reduce((sum, l) => sum + l.n, 0);
  const subject = `EDITSTATION daily summary: ${total} new ${total === 1 ? "update" : "updates"}`;
  const href = notificationsUrl();

  const listRows = lines
    .map(
      (l) =>
        `<tr><td style="padding: 0 0 8px; font-size: 15px; line-height: 1.5; color: #2b2140">${escapeHtml(l.label)}: <strong>${l.n}</strong></td></tr>`,
    )
    .join("\n");

  const html = renderEmailLayout({
    preheader: `${total} new ${total === 1 ? "update" : "updates"} since your last summary.`,
    heading: "Your daily summary",
    rowsHtml: `${paragraphRow("New since your last summary:")}\n${listRows}\n${paragraphRow(`${INDIVIDUAL_BODY_TEXT}.`)}`,
    buttonLabel: BUTTON_LABEL,
    buttonHref: href,
  });
  const text = [
    "EDITSTATION",
    "",
    "Your daily summary",
    "",
    "New since your last summary:",
    ...lines.map((l) => `- ${l.label}: ${l.n}`),
    "",
    `${INDIVIDUAL_BODY_TEXT}:`,
    href,
    "",
    EMAIL_FOOTER_TEXT,
  ].join("\n");
  return { subject, html, text };
}
