import "server-only";

import { createBrevoSender } from "@/features/notifications/email/brevo";
import { isAuthorised } from "@/features/notifications/email/cron-auth";
import { runEmailWorker, type EmailWorkerStore } from "@/features/notifications/email/worker";
import { createServiceClient } from "@/lib/supabase/service";

/**
 * Email worker, called every 5 minutes by the hosted scheduler (pg_cron + pg_net, see
 * docs/RUNBOOKS.md "Notification emails") with `Authorization: Bearer <CRON_SECRET>`. It is the
 * only user of the service key. Responses carry counts only; logs carry no address, key or
 * provider/database message.
 */

export const maxDuration = 60;

const NO_STORE = { "cache-control": "no-store" };

function json(body: Record<string, unknown>, status: number): Response {
  return Response.json(body, { status, headers: NO_STORE });
}

function serviceStore(): EmailWorkerStore {
  const supabase = createServiceClient();
  return {
    async claimDigests(now) {
      const { data, error } = await supabase.rpc("worker_claim_admin_digest", {
        p_now: now.toISOString(),
      });
      if (error) throw new Error(`claim digest failed (${error.code})`);
      return data ?? [];
    },
    async claimEmails(limit) {
      const { data, error } = await supabase.rpc("worker_claim_emails", { p_limit: limit });
      if (error) throw new Error(`claim emails failed (${error.code})`);
      return data ?? [];
    },
    async mark(id, ok, reason, claimedAt) {
      const { error } = await supabase.rpc("worker_mark_email", {
        p_id: id,
        p_ok: ok,
        ...(reason ? { p_error: reason } : {}),
        ...(claimedAt ? { p_claimed_at: claimedAt } : {}),
      });
      if (error) throw new Error(`mark failed (${error.code})`);
    },
  };
}

export async function POST(request: Request): Promise<Response> {
  if (!isAuthorised(request.headers.get("authorization"), process.env.CRON_SECRET)) {
    return json({ error: "unauthorized" }, 401);
  }
  const apiKey = process.env.BREVO_API_KEY;
  if (!apiKey || !process.env.SUPABASE_SECRET_KEY) {
    // Nothing is claimed, so no attempt is used up while the deployment is misconfigured.
    return json({ error: "not configured" }, 503);
  }

  try {
    const result = await runEmailWorker(
      serviceStore(),
      createBrevoSender(apiKey, process.env.EMAIL_FROM),
    );
    return json(result, 200);
  } catch (error) {
    // Our own messages carry only a database error code, never an address or provider text.
    console.error("send-emails run failed:", error instanceof Error ? error.message : "unknown");
    return json({ error: "run failed" }, 500);
  }
}
