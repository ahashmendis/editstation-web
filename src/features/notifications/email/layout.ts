/**
 * Shared look for notification emails: the same inline-styled card as the auth emails in
 * supabase/templates/ (wordmark EDIT+STATION, purple button, footer). Pure functions; every
 * caller-supplied string is escaped here.
 */

const FONT = "-apple-system, &quot;Segoe UI&quot;, Roboto, Helvetica, Arial, sans-serif";

export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

export type EmailLayoutInput = {
  /** Hidden inbox preview line (plain text, escaped here). */
  preheader: string;
  /** Heading (plain text, escaped here). */
  heading: string;
  /** Already-safe HTML rows built by the templates (each a full <tr>). */
  rowsHtml: string;
  buttonLabel: string;
  buttonHref: string;
};

export function paragraphRow(text: string): string {
  return `<tr><td style="padding: 0 0 16px; font-size: 15px; line-height: 1.6; color: #2b2140">${escapeHtml(text)}</td></tr>`;
}

export function renderEmailLayout(input: EmailLayoutInput): string {
  return `<!doctype html>
<html lang="en">
  <body style="margin: 0; padding: 0; background: #f5f2fa">
    <span style="display: none; max-height: 0; overflow: hidden; opacity: 0">${escapeHtml(input.preheader)}</span>
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background: #f5f2fa; padding: 32px 12px">
      <tr>
        <td align="center">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width: 520px; background: #ffffff; border-radius: 12px; padding: 32px; font-family: ${FONT}">
            <tr>
              <td style="padding: 0 0 24px; font-size: 20px; font-weight: 700; letter-spacing: 0.02em; color: #2b2140">EDIT<span style="color: #7a2fd0">STATION</span></td>
            </tr>
            <tr>
              <td style="padding: 0 0 16px; font-size: 20px; font-weight: 600; color: #2b2140">${escapeHtml(input.heading)}</td>
            </tr>
            ${input.rowsHtml}
            <tr>
              <td style="padding: 8px 0 24px">
                <a href="${escapeHtml(input.buttonHref)}" style="display: inline-block; background: #5a1da6; color: #ffffff; text-decoration: none; font-weight: 600; font-size: 15px; padding: 12px 22px; border-radius: 8px">${escapeHtml(input.buttonLabel)}</a>
              </td>
            </tr>
            <tr>
              <td style="padding: 8px 0 0; font-size: 13px; line-height: 1.5; color: #6b6280">You receive this because you have an EDITSTATION account. Sign in to see the details.</td>
            </tr>
            <tr>
              <td style="padding: 24px 0 0; border-top: 1px solid #ece7f5; font-size: 12px; line-height: 1.5; color: #8a8199">EDITSTATION, a Lenscape Studios production network. This is an automated message; please do not reply.</td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>
`;
}

export const EMAIL_FOOTER_TEXT =
  "EDITSTATION, a Lenscape Studios production network. This is an automated message; please do not reply.";
