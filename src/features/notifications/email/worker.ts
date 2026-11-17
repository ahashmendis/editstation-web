import "server-only";

import type { SendEmail } from "./brevo";
import { renderAdminDigestEmail, renderIndividualEmail } from "./templates";

/** Most emails one run sends (Brevo free-plan daily limit; the excess stays queued, oldest first). */
export const EMAILS_PER_RUN = 25;

/** Stop sending after this long so a run always ends inside the route's maxDuration (60 s). */
export const RUN_TIME_BUDGET_MS = 45_000;

/** claimed_at identifies the claim; it is passed back when reporting the result. */
export type ClaimedEmail = { id: number; email: string; title: string; claimed_at?: string };
export type ClaimedDigest = { id: number; email: string; counts: unknown; claimed_at?: string };

/** The three worker database functions, so the run can be tested without a database. */
export type EmailWorkerStore = {
  claimDigests(now: Date): Promise<ClaimedDigest[]>;
  claimEmails(limit: number): Promise<ClaimedEmail[]>;
  mark(id: number, ok: boolean, reason: string | null, claimedAt?: string): Promise<void>;
};

export type EmailRunResult = { sent: number; failed: number; digests: number };

function asCounts(value: unknown): Record<string, number> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const out: Record<string, number> = {};
  for (const [kind, n] of Object.entries(value)) {
    if (typeof n === "number") out[kind] = n;
  }
  return out;
}

/**
 * One worker run: the day's admin summaries first (at most one per admin), then individual emails
 * up to the per-run cap. Every claimed row is reported back; a failed report is counted as failed
 * and the row's lease lets the next run retry it.
 */
export async function runEmailWorker(
  store: EmailWorkerStore,
  send: SendEmail,
  now: Date = new Date(),
): Promise<EmailRunResult> {
  const result: EmailRunResult = { sent: 0, failed: 0, digests: 0 };

  /** Records the outcome; true only when the send succeeded and was recorded as sent. */
  const report = async (
    id: number,
    ok: boolean,
    reason: string | null,
    claimedAt?: string,
  ): Promise<boolean> => {
    try {
      await store.mark(id, ok, reason, claimedAt);
    } catch {
      result.failed += 1;
      return false;
    }
    if (ok) result.sent += 1;
    else result.failed += 1;
    return ok;
  };

  const digests = await store.claimDigests(now);
  for (const d of digests) {
    const rendered = renderAdminDigestEmail({ counts: asCounts(d.counts) });
    const outcome = await send({ to: d.email, ...rendered });
    if (await report(d.id, outcome.ok, outcome.ok ? null : outcome.reason, d.claimed_at)) {
      result.digests += 1;
    }
  }

  const remaining = EMAILS_PER_RUN - digests.length;
  if (remaining <= 0) return result;

  // A failure here must not discard the summaries already sent and recorded above.
  let emails: ClaimedEmail[] = [];
  try {
    emails = await store.claimEmails(remaining);
  } catch {
    return result;
  }
  const started = Date.now();
  for (const e of emails) {
    // Rows claimed but not sent in time are retried after their lease expires.
    if (Date.now() - started > RUN_TIME_BUDGET_MS) break;
    const rendered = renderIndividualEmail({ title: e.title });
    const outcome = await send({ to: e.email, ...rendered });
    await report(e.id, outcome.ok, outcome.ok ? null : outcome.reason, e.claimed_at);
  }
  return result;
}
