import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
vi.mock("next/cache", () => ({ refresh: vi.fn() }));

const USER = "11111111-1111-4111-8111-111111111111";
vi.mock("@/lib/auth/access", () => ({
  requireSignedIn: async () => ({ userId: USER, email: "me@example.test" }),
}));

type Call = { op: string; args: unknown[] };
let calls: Call[] = [];
let previousPath: string | null = null;
let rpcError: { code: string; message: string } | null = null;

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    from: () => ({
      select: () => ({
        eq: () => ({
          maybeSingle: async () => ({ data: { avatar_path: previousPath }, error: null }),
        }),
      }),
    }),
    rpc: async (...args: unknown[]) => {
      calls.push({ op: "rpc", args });
      return { error: rpcError };
    },
    storage: {
      from: (bucket: string) => ({
        upload: async (...args: unknown[]) => {
          calls.push({ op: `upload:${bucket}`, args });
          return { error: null };
        },
        remove: async (...args: unknown[]) => {
          calls.push({ op: `remove:${bucket}`, args });
          return { data: [], error: null };
        },
      }),
    },
  }),
}));

const { uploadAvatarAction } = await import("./actions");

const PNG = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0];
const form = (file: File | null) => {
  const fd = new FormData();
  if (file) fd.set("avatar", file);
  return fd;
};
const idle = { status: "idle" as const };

beforeEach(() => {
  calls = [];
  previousPath = null;
  rpcError = null;
});

describe("uploadAvatarAction", () => {
  it("refuses a file declared image/png whose bytes are not an image, before any storage call", async () => {
    const fake = new File([new TextEncoder().encode("<html><script>x</script>")], "a.png", {
      type: "image/png",
    });
    const result = await uploadAvatarAction(idle, form(fake));
    expect(result.status).toBe("error");
    expect(result.message).toBe("That file is not a JPEG, PNG or WebP picture.");
    expect(calls).toEqual([]);
  });

  it("refuses a file over 2 MB before reading or uploading it", async () => {
    const big = new File([new Uint8Array(2 * 1024 * 1024 + 1)], "big.png", { type: "image/png" });
    const result = await uploadAvatarAction(idle, form(big));
    expect(result.status).toBe("error");
    expect(result.message).toMatch(/2 MB/);
    expect(calls).toEqual([]);
  });

  it("refuses a missing file and a disallowed declared type", async () => {
    expect((await uploadAvatarAction(idle, form(null))).message).toMatch(/choose/i);
    const gif = new File([new Uint8Array(PNG)], "a.gif", { type: "image/gif" });
    expect((await uploadAvatarAction(idle, form(gif))).message).toMatch(/JPEG, PNG or WebP/);
    expect(calls).toEqual([]);
  });

  it("uploads to the user's own path with the detected type, saves, then removes stale objects", async () => {
    // Declared JPEG, real PNG: the bytes decide the extension and content type.
    const file = new File([new Uint8Array(PNG)], "me.jpg", { type: "image/jpeg" });
    const result = await uploadAvatarAction(idle, form(file));
    expect(result).toEqual({ status: "success", message: "Your picture is saved." });
    expect(calls.map((c) => c.op)).toEqual(["upload:avatars", "rpc", "remove:avatars"]);
    expect(calls[0].args[0]).toBe(`${USER}/avatar.png`);
    expect(calls[0].args[2]).toMatchObject({ contentType: "image/png", upsert: true });
    expect(calls[1].args).toEqual(["set_my_avatar", { p_path: `${USER}/avatar.png` }]);
    // Always, even with no previous picture recorded.
    expect(calls[2].args[0]).toEqual([`${USER}/avatar.jpg`, `${USER}/avatar.webp`]);
  });

  it("shows only the user-safe database message and removes the unused upload", async () => {
    rpcError = { code: "ES422", message: "The picture upload did not finish. Please try again." };
    const file = new File([new Uint8Array(PNG)], "me.png", { type: "image/png" });
    const result = await uploadAvatarAction(idle, form(file));
    expect(result).toEqual({
      status: "error",
      message: "The picture upload did not finish. Please try again.",
    });
    expect(calls.at(-1)).toEqual({ op: "remove:avatars", args: [[`${USER}/avatar.png`]] });

    rpcError = { code: "XX000", message: "internal detail" };
    calls = [];
    const leaked = await uploadAvatarAction(idle, form(file));
    expect(leaked.message).toBe("Something went wrong. Please try again.");
  });
});
