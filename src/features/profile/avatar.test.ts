import { describe, expect, it, vi } from "vitest";

import {
  AVATAR_URL_SECONDS,
  avatarPathsFor,
  detectImageType,
  initialsFor,
  signAvatarPaths,
  type AvatarStorageClient,
} from "./avatar";

const bytes = (...values: number[]) => new Uint8Array(values);
const ascii = (s: string) => Array.from(s, (c) => c.charCodeAt(0));

describe("detectImageType", () => {
  it("recognises JPEG, PNG and WebP by their magic bytes", () => {
    expect(detectImageType(bytes(0xff, 0xd8, 0xff, 0xe0, 0, 0))).toBe("jpg");
    expect(detectImageType(bytes(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0))).toBe("png");
    expect(detectImageType(bytes(...ascii("RIFF"), 1, 2, 3, 4, ...ascii("WEBPVP8 ")))).toBe("webp");
  });

  it("rejects other or truncated content whatever the declared type", () => {
    expect(detectImageType(bytes(...ascii("GIF89a")))).toBeNull();
    expect(detectImageType(bytes(...ascii("<svg xmlns")))).toBeNull();
    expect(detectImageType(bytes(...ascii("RIFF"), 1, 2, 3, 4, ...ascii("WAVE")))).toBeNull();
    expect(detectImageType(bytes(0x89, 0x50, 0x4e))).toBeNull();
    expect(detectImageType(bytes())).toBeNull();
  });
});

describe("avatarPathsFor", () => {
  it("lists one object per allowed extension in the user's own folder", () => {
    expect(avatarPathsFor("u1")).toEqual(["u1/avatar.jpg", "u1/avatar.png", "u1/avatar.webp"]);
  });
});

describe("initialsFor", () => {
  it("uses first and last name, a single name, or the email", () => {
    expect(initialsFor("Nimal Perera Fernando")).toBe("NF");
    expect(initialsFor("ahash")).toBe("AH");
    expect(initialsFor(null, "k.silva@example.com")).toBe("KS");
    expect(initialsFor("  ", null)).toBe("?");
  });
});

type SignResult = Awaited<
  ReturnType<ReturnType<AvatarStorageClient["storage"]["from"]>["createSignedUrls"]>
>;

/** Fake storage: `types` maps a path to its stored content type (missing = info fails). */
function fakeClient(types: Record<string, string>, result?: SignResult) {
  const info = vi.fn(async (path: string) =>
    path in types
      ? { data: { contentType: types[path] }, error: null }
      : { data: null, error: new Error("not found") },
  );
  const createSignedUrls = vi.fn(
    async (paths: string[]): Promise<SignResult> =>
      result ?? {
        data: paths.map((p) => ({ path: p, signedUrl: `https://x/${p}`, error: null })),
        error: null,
      },
  );
  const from = vi.fn().mockReturnValue({ info, createSignedUrls });
  return { client: { storage: { from } } as AvatarStorageClient, from, info, createSignedUrls };
}

describe("signAvatarPaths", () => {
  it("signs unique image paths in the avatars bucket with a short expiry", async () => {
    const { client, from, createSignedUrls } = fakeClient({
      "a/avatar.png": "image/png",
      "b/avatar.jpg": "image/jpeg",
      "c/avatar.webp": "image/webp; charset=binary",
    });
    const urls = await signAvatarPaths(client, [
      "a/avatar.png",
      null,
      "a/avatar.png",
      "b/avatar.jpg",
      "c/avatar.webp",
    ]);
    expect(from).toHaveBeenCalledWith("avatars");
    expect(createSignedUrls).toHaveBeenCalledWith(
      ["a/avatar.png", "b/avatar.jpg", "c/avatar.webp"],
      AVATAR_URL_SECONDS,
    );
    expect(AVATAR_URL_SECONDS).toBeLessThanOrEqual(600);
    expect(urls.size).toBe(3);
  });

  it("never signs an object whose stored type is not JPEG, PNG or WebP", async () => {
    const { client, createSignedUrls } = fakeClient({
      "a/avatar.png": "text/html",
      "b/avatar.jpg": "image/svg+xml",
      "c/avatar.webp": "",
      "d/avatar.png": "image/png",
    });
    const urls = await signAvatarPaths(client, [
      "a/avatar.png",
      "b/avatar.jpg",
      "c/avatar.webp",
      "e/avatar.png", // info fails (missing or not readable by this session)
      "d/avatar.png",
    ]);
    expect(createSignedUrls).toHaveBeenCalledWith(["d/avatar.png"], AVATAR_URL_SECONDS);
    expect(Array.from(urls.keys())).toEqual(["d/avatar.png"]);

    const none = fakeClient({ "a/avatar.png": "application/octet-stream" });
    expect((await signAvatarPaths(none.client, ["a/avatar.png"])).size).toBe(0);
    expect(none.createSignedUrls).not.toHaveBeenCalled();
  });

  it("treats a failed signed URL as no picture", async () => {
    const rowError = fakeClient(
      { "a/avatar.png": "image/png", "b/avatar.jpg": "image/jpeg" },
      {
        data: [
          { path: "a/avatar.png", signedUrl: "https://x/a", error: null },
          { path: "b/avatar.jpg", signedUrl: null, error: "Object not found" },
        ],
        error: null,
      },
    );
    const urls = await signAvatarPaths(rowError.client, ["a/avatar.png", "b/avatar.jpg"]);
    expect(Array.from(urls)).toEqual([["a/avatar.png", "https://x/a"]]);

    const failed = fakeClient(
      { "a/avatar.png": "image/png" },
      { data: null, error: new Error("down") },
    );
    expect((await signAvatarPaths(failed.client, ["a/avatar.png"])).size).toBe(0);
  });

  it("makes no call without paths and swallows storage exceptions", async () => {
    const none = fakeClient({});
    expect((await signAvatarPaths(none.client, [null, undefined])).size).toBe(0);
    expect(none.info).not.toHaveBeenCalled();
    expect(none.createSignedUrls).not.toHaveBeenCalled();

    const thrown = {
      storage: {
        from: () => ({
          info: () => Promise.reject(new Error("fetch failed")),
          createSignedUrls: () => Promise.reject(new Error("fetch failed")),
        }),
      },
    };
    expect((await signAvatarPaths(thrown as AvatarStorageClient, ["a/avatar.png"])).size).toBe(0);
  });
});
