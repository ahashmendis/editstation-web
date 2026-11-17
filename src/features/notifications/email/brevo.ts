import "server-only";

import { SUPPORT_EMAIL } from "@/lib/site-contact";

/**
 * Brevo transactional email over plain fetch (no SDK dependency). Returns only whether Brevo
 * accepted the message and a short machine reason; never the response body, the address or the key.
 */

const BREVO_URL = "https://api.brevo.com/v3/smtp/email";
const DEFAULT_FROM = "EDITSTATION <no-reply@editstation.work>";
const SEND_TIMEOUT_MS = 8000;

export type OutgoingEmail = { to: string; subject: string; html: string; text: string };
export type SendResult = { ok: true } | { ok: false; reason: string };
export type SendEmail = (email: OutgoingEmail) => Promise<SendResult>;

/** Parses `Name <address>` or a bare address. Falls back to the default sender when malformed. */
export function parseSender(raw: string | undefined): { name?: string; email: string } {
  const value = raw?.trim() || DEFAULT_FROM;
  const match = /^(.*)<\s*([^<>\s]+@[^<>\s]+)\s*>$/.exec(value);
  if (match) {
    const name = match[1].trim().replace(/^"|"$/g, "");
    return name ? { name, email: match[2] } : { email: match[2] };
  }
  if (/^[^<>\s]+@[^<>\s]+$/.test(value)) return { email: value };
  return parseSender(DEFAULT_FROM);
}

export function createBrevoSender(apiKey: string, from: string | undefined): SendEmail {
  const sender = parseSender(from);
  return async (email) => {
    try {
      const response = await fetch(BREVO_URL, {
        method: "POST",
        headers: {
          "api-key": apiKey,
          "content-type": "application/json",
          accept: "application/json",
        },
        body: JSON.stringify({
          sender,
          // Replies go to the support inbox, not the unmonitored no-reply sender.
          replyTo: { email: SUPPORT_EMAIL, name: "EDITSTATION Support" },
          to: [{ email: email.to }],
          subject: email.subject,
          htmlContent: email.html,
          textContent: email.text,
        }),
        signal: AbortSignal.timeout(SEND_TIMEOUT_MS),
        cache: "no-store",
      });
      return response.ok ? { ok: true } : { ok: false, reason: `provider ${response.status}` };
    } catch (error) {
      const timedOut = error instanceof Error && error.name === "TimeoutError";
      return { ok: false, reason: timedOut ? "provider timeout" : "network error" };
    }
  };
}
