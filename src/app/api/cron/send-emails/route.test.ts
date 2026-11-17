import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));

type RpcCall = { fn: string; args: Record<string, unknown> };
const rpcCalls: RpcCall[] = [];
let rpcResults: Record<string, { data: unknown; error: { code: string } | null }> = {};

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    rpc: async (fn: string, args: Record<string, unknown>) => {
      rpcCalls.push({ fn, args });
      return rpcResults[fn] ?? { data: null, error: null };
    },
  }),
}));

const { POST } = await import("./route");
const { isAuthorised } = await import("@/features/notifications/email/cron-auth");
const { parseSender } = await import("@/features/notifications/email/brevo");

const SECRET = "test-cron-secret-0123456789";

function request(auth?: string): Request {
  return new Request("http://localhost/api/cron/send-emails", {
    method: "POST",
    headers: auth ? { authorization: auth } : {},
  });
}

const fetchMock = vi.fn<typeof fetch>();

beforeEach(() => {
  rpcCalls.length = 0;
  rpcResults = {
    worker_claim_admin_digest: {
      data: [
        {
          id: 7,
          email: "admin@test.local",
          counts: { inquiry_new: 2 },
          total: 2,
          claimed_at: "2026-11-17T10:00:00+00:00",
        },
      ],
      error: null,
    },
    worker_claim_emails: {
      data: [
        {
          id: 1,
          email: "editor@test.local",
          title: "Project invitation",
          kind: "invitation",
          claimed_at: "2026-11-17T10:00:01+00:00",
        },
        {
          id: 2,
          email: "applicant@test.local",
          title: "More information requested",
          kind: "application_request",
          claimed_at: "2026-11-17T10:00:01+00:00",
        },
      ],
      error: null,
    },
    worker_mark_email: { data: null, error: null },
  };
  vi.stubEnv("CRON_SECRET", SECRET);
  vi.stubEnv("BREVO_API_KEY", "brevo-test-key");
  vi.stubEnv("SUPABASE_SECRET_KEY", "sb_secret_test");
  vi.stubEnv("SITE_URL", "https://www.editstation.work");
  vi.stubEnv("EMAIL_FROM", "");
  fetchMock.mockReset();
  fetchMock.mockResolvedValue(new Response("{}", { status: 201 }));
  vi.stubGlobal("fetch", fetchMock);
});

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("isAuthorised", () => {
  it("accepts only the exact bearer secret", () => {
    expect(isAuthorised(`Bearer ${SECRET}`, SECRET)).toBe(true);
    expect(isAuthorised(`Bearer ${SECRET}x`, SECRET)).toBe(false);
    expect(isAuthorised(SECRET, SECRET)).toBe(false);
    expect(isAuthorised("Bearer ", SECRET)).toBe(false);
    expect(isAuthorised(null, SECRET)).toBe(false);
  });

  it("rejects everything when the secret is not set", () => {
    expect(isAuthorised("Bearer ", undefined)).toBe(false);
    expect(isAuthorised("Bearer ", "")).toBe(false);
    expect(isAuthorised("Bearer anything", "")).toBe(false);
  });
});

describe("parseSender", () => {
  it("parses a named sender and falls back to the default", () => {
    expect(parseSender("EDITSTATION <no-reply@editstation.work>")).toEqual({
      name: "EDITSTATION",
      email: "no-reply@editstation.work",
    });
    expect(parseSender(undefined)).toEqual({
      name: "EDITSTATION",
      email: "no-reply@editstation.work",
    });
    expect(parseSender("ops@editstation.work")).toEqual({ email: "ops@editstation.work" });
    expect(parseSender("not a sender")).toEqual({
      name: "EDITSTATION",
      email: "no-reply@editstation.work",
    });
  });
});

describe("POST /api/cron/send-emails", () => {
  it("rejects a missing or wrong secret without touching the database", async () => {
    for (const auth of [undefined, "Bearer wrong", SECRET]) {
      const res = await POST(request(auth));
      expect(res.status).toBe(401);
    }
    expect(rpcCalls).toHaveLength(0);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("rejects every request when CRON_SECRET is unset", async () => {
    vi.stubEnv("CRON_SECRET", "");
    const res = await POST(request("Bearer "));
    expect(res.status).toBe(401);
    expect(rpcCalls).toHaveLength(0);
  });

  it("claims nothing when the sender is not configured", async () => {
    vi.stubEnv("BREVO_API_KEY", "");
    const res = await POST(request(`Bearer ${SECRET}`));
    expect(res.status).toBe(503);
    expect(rpcCalls).toHaveLength(0);
  });

  it("sends the summary and the individual emails, marks each and returns counts only", async () => {
    const res = await POST(request(`Bearer ${SECRET}`));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ sent: 3, failed: 0, digests: 1 });

    expect(rpcCalls.map((c) => c.fn)).toEqual([
      "worker_claim_admin_digest",
      "worker_mark_email",
      "worker_claim_emails",
      "worker_mark_email",
      "worker_mark_email",
    ]);
    expect(rpcCalls[2].args).toEqual({ p_limit: 24 });
    expect(rpcCalls.filter((c) => c.fn === "worker_mark_email").map((c) => c.args)).toEqual([
      { p_id: 7, p_ok: true, p_claimed_at: "2026-11-17T10:00:00+00:00" },
      { p_id: 1, p_ok: true, p_claimed_at: "2026-11-17T10:00:01+00:00" },
      { p_id: 2, p_ok: true, p_claimed_at: "2026-11-17T10:00:01+00:00" },
    ]);

    expect(fetchMock).toHaveBeenCalledTimes(3);
    const [url, init] = fetchMock.mock.calls[1];
    expect(url).toBe("https://api.brevo.com/v3/smtp/email");
    expect((init?.headers as Record<string, string>)["api-key"]).toBe("brevo-test-key");
    const body = JSON.parse(String(init?.body));
    expect(body.sender).toEqual({ name: "EDITSTATION", email: "no-reply@editstation.work" });
    expect(body.to).toEqual([{ email: "editor@test.local" }]);
    expect(body.subject).toBe("Project invitation");
    expect(body.htmlContent).toContain("https://www.editstation.work/notifications");
    expect(body.textContent).toContain("Open EDITSTATION to read the details");
  });

  it("reports provider failures with a short reason and never echoes them", async () => {
    fetchMock.mockResolvedValue(new Response('{"message":"secret detail"}', { status: 400 }));
    const res = await POST(request(`Bearer ${SECRET}`));
    expect(res.status).toBe(200);
    const text = await res.text();
    expect(JSON.parse(text)).toEqual({ sent: 0, failed: 3, digests: 0 });
    expect(text).not.toContain("secret detail");
    expect(rpcCalls.filter((c) => c.fn === "worker_mark_email").map((c) => c.args)).toEqual([
      { p_id: 7, p_ok: false, p_error: "provider 400", p_claimed_at: "2026-11-17T10:00:00+00:00" },
      { p_id: 1, p_ok: false, p_error: "provider 400", p_claimed_at: "2026-11-17T10:00:01+00:00" },
      { p_id: 2, p_ok: false, p_error: "provider 400", p_claimed_at: "2026-11-17T10:00:01+00:00" },
    ]);
  });

  it("treats a network error as a failed attempt", async () => {
    fetchMock.mockRejectedValue(new TypeError("fetch failed for editor@test.local"));
    const res = await POST(request(`Bearer ${SECRET}`));
    expect(await res.json()).toEqual({ sent: 0, failed: 3, digests: 0 });
    expect(rpcCalls.at(-1)?.args).toEqual({
      p_id: 2,
      p_ok: false,
      p_error: "network error",
      p_claimed_at: "2026-11-17T10:00:01+00:00",
    });
  });

  it("returns a generic 500 when claiming fails, without logging addresses or details", async () => {
    rpcResults.worker_claim_admin_digest = { data: null, error: { code: "ES403" } };
    const log = vi.spyOn(console, "error").mockImplementation(() => {});
    const res = await POST(request(`Bearer ${SECRET}`));
    expect(res.status).toBe(500);
    expect(await res.json()).toEqual({ error: "run failed" });
    const logged = log.mock.calls.flat().join(" ");
    expect(logged).toContain("ES403");
    expect(logged).not.toMatch(/@|brevo-test-key|sb_secret/);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("counts a failed result report as failed", async () => {
    rpcResults.worker_mark_email = { data: null, error: { code: "ES409" } };
    const res = await POST(request(`Bearer ${SECRET}`));
    expect(await res.json()).toEqual({ sent: 0, failed: 3, digests: 0 });
  });
});
