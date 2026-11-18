import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
vi.mock("next/navigation", () => ({ redirect: vi.fn() }));
vi.mock("@/lib/auth/access", () => ({ getAccess: vi.fn(), homePathFor: vi.fn() }));

let calls: { fn: string; args: Record<string, unknown> }[] = [];
let rpcError: { code: string; message: string } | null = null;

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    rpc: async (fn: string, args: Record<string, unknown>) => {
      calls.push({ fn, args });
      return { data: rpcError ? null : "c9000000-0000-4000-8000-000000000001", error: rpcError };
    },
  }),
}));

const { submitClientProjectAction } = await import("./actions");

const idle = { status: "idle" as const };
const form = (entries: Record<string, string>) => {
  const fd = new FormData();
  for (const [k, v] of Object.entries(entries)) fd.set(k, v);
  return fd;
};
const valid = {
  serviceType: "long_form",
  description: "Our launch film",
  budgetRangeId: "discuss",
  acceptPrivacy: "on",
  // Contact fields are never sent to the database, even if a crafted form includes them.
  email: "spoof@example.com",
  contactName: "Someone Else",
};

beforeEach(() => {
  calls = [];
  rpcError = null;
});

describe("submitClientProjectAction", () => {
  it("pretends success for a filled honeypot and calls nothing", async () => {
    const result = await submitClientProjectAction(
      idle,
      form({ ...valid, website: "http://spam" }),
    );
    expect(result.status).toBe("success");
    expect(calls).toHaveLength(0);
  });

  it("requires the privacy checkbox and keeps the input", async () => {
    const rest: Record<string, string> = { ...valid };
    delete rest.acceptPrivacy;
    const result = await submitClientProjectAction(idle, form(rest));
    expect(result.status).toBe("error");
    expect(result.fieldErrors?.acceptPrivacy).toBeDefined();
    expect(result.values?.description).toBe("Our launch film");
    expect(calls).toHaveLength(0);
  });

  it("keeps the input on a validation error", async () => {
    const result = await submitClientProjectAction(idle, form({ ...valid, description: " " }));
    expect(result.status).toBe("error");
    expect(result.fieldErrors?.description).toBeDefined();
    expect(result.values?.serviceType).toBe("long_form");
    expect(calls).toHaveLength(0);
  });

  it("sends only project fields to client_submit_project", async () => {
    const result = await submitClientProjectAction(idle, form(valid));
    expect(result.status).toBe("success");
    expect(calls).toHaveLength(1);
    expect(calls[0].fn).toBe("client_submit_project");
    expect(Object.keys(calls[0].args).sort()).toEqual(
      [
        "p_budget_range_id",
        "p_client_notes",
        "p_description",
        "p_expected_deadline",
        "p_expected_deliverables",
        "p_links",
        "p_privacy_notice_version",
        "p_service_type",
      ].sort(),
    );
  });

  it("shows only the user-safe database message", async () => {
    rpcError = { code: "ES409", message: "You have sent several project requests today." };
    const result = await submitClientProjectAction(idle, form(valid));
    expect(result).toMatchObject({
      status: "error",
      message: "You have sent several project requests today.",
    });
    rpcError = { code: "42P01", message: "relation does not exist" };
    const raw = await submitClientProjectAction(idle, form(valid));
    expect(raw.message).not.toContain("relation");
  });
});
