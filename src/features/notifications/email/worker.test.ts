import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));

import { runEmailWorker, RUN_TIME_BUDGET_MS, type EmailWorkerStore } from "./worker";

afterEach(() => vi.useRealTimers());

const ok = async () => ({ ok: true as const });

function store(overrides: Partial<EmailWorkerStore> = {}): EmailWorkerStore {
  return {
    claimDigests: async () => [],
    claimEmails: async () => [],
    mark: async () => {},
    ...overrides,
  };
}

describe("runEmailWorker", () => {
  it("keeps the digests already sent when claiming individual emails fails", async () => {
    const result = await runEmailWorker(
      store({
        claimDigests: async () => [{ id: 1, email: "a@test.local", counts: { inquiry_new: 2 } }],
        claimEmails: async () => {
          throw new Error("db down");
        },
      }),
      ok,
    );
    expect(result).toEqual({ sent: 1, failed: 0, digests: 1 });
  });

  it("stops sending after the time budget and leaves the rest to be retried", async () => {
    vi.useFakeTimers();
    const marked: number[] = [];
    const slowSend = vi.fn(async () => {
      vi.advanceTimersByTime(RUN_TIME_BUDGET_MS + 1);
      return { ok: true as const };
    });
    const result = await runEmailWorker(
      store({
        claimEmails: async () => [
          { id: 1, email: "a@test.local", title: "One" },
          { id: 2, email: "b@test.local", title: "Two" },
        ],
        mark: async (id) => {
          marked.push(id);
        },
      }),
      slowSend,
    );
    expect(slowSend).toHaveBeenCalledTimes(1);
    expect(marked).toEqual([1]);
    expect(result.sent).toBe(1);
  });
});
