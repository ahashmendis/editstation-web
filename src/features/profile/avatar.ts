// Profile pictures: limits, file checks and signed-URL creation. Pure (no server-only import) so
// it can be unit tested; callers pass a Supabase client bound to the right session.
// Owner decisions 2026-11-17: visible only to the owner and admins; private bucket; 2 MB;
// JPEG, PNG or WebP; object path `<user_id>/avatar.<ext>`.

export const AVATAR_BUCKET = "avatars";
export const AVATAR_MAX_BYTES = 2 * 1024 * 1024;
/** Signed URLs are short-lived and created per request, never shared across users. */
export const AVATAR_URL_SECONDS = 300;
export const AVATAR_LIMITS_TEXT = "JPEG, PNG or WebP, up to 2 MB.";
export const AVATAR_ACCEPT = "image/jpeg,image/png,image/webp";

export type AvatarExt = "jpg" | "png" | "webp";

export const AVATAR_TYPES: Record<AvatarExt, string> = {
  jpg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
};

/** Every object name a user's picture can have (used to clean up old extensions). */
export function avatarPathsFor(userId: string): string[] {
  return (Object.keys(AVATAR_TYPES) as AvatarExt[]).map((ext) => avatarPath(userId, ext));
}

export function avatarPath(userId: string, ext: AvatarExt): string {
  return `${userId}/avatar.${ext}`;
}

/** The file's real type from its first bytes; null when it is not a JPEG, PNG or WebP. */
export function detectImageType(bytes: Uint8Array): AvatarExt | null {
  const at = (i: number) => bytes[i];
  if (bytes.length >= 3 && at(0) === 0xff && at(1) === 0xd8 && at(2) === 0xff) return "jpg";
  if (
    bytes.length >= 8 &&
    [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].every((b, i) => at(i) === b)
  ) {
    return "png";
  }
  const ascii = (from: number, to: number) => String.fromCharCode(...bytes.subarray(from, to));
  if (bytes.length >= 12 && ascii(0, 4) === "RIFF" && ascii(8, 12) === "WEBP") return "webp";
  return null;
}

/** Up to two letters for the fallback, from the name, else the email. */
export function initialsFor(name: string | null | undefined, email?: string | null): string {
  const words = (name ?? "").trim().split(/\s+/).filter(Boolean);
  if (words.length >= 2) return (words[0][0] + words[words.length - 1][0]).toUpperCase();
  if (words.length === 1) return words[0].slice(0, 2).toUpperCase();
  const local = (email ?? "").split("@")[0].replace(/[^a-z0-9]/gi, "");
  return local ? local.slice(0, 2).toUpperCase() : "?";
}

const SAFE_STORED_TYPES = new Set(Object.values(AVATAR_TYPES));

/** The part of the Supabase client this module uses. */
export type AvatarStorageClient = {
  storage: {
    from(bucket: string): {
      info(path: string): Promise<{ data: { contentType?: string | null } | null; error: unknown }>;
      createSignedUrls(
        paths: string[],
        expiresIn: number,
      ): Promise<{
        data: { path: string | null; signedUrl: string | null; error: string | null }[] | null;
        error: unknown;
      }>;
    };
  };
};

/** True when the stored object's content type is one we allow (JPEG, PNG or WebP). */
async function hasSafeStoredType(
  bucket: ReturnType<AvatarStorageClient["storage"]["from"]>,
  path: string,
): Promise<boolean> {
  try {
    const { data, error } = await bucket.info(path);
    if (error || !data?.contentType) return false;
    return SAFE_STORED_TYPES.has(data.contentType.split(";")[0].trim().toLowerCase());
  } catch {
    return false;
  }
}

/**
 * Signed URLs for the given object paths, keyed by path. Storage RLS decides what the session may
 * read (owner or MFA admin). An object is signed only when its stored content type is JPEG, PNG or
 * WebP: a direct Storage API upload skips the app's magic-byte check, so anything else (for
 * example an HTML or SVG file) is treated as no picture and never served from a signed URL.
 * Missing, unreadable or failed paths are simply absent, so the UI falls back to initials; storage
 * errors never reach the user.
 */
export async function signAvatarPaths(
  client: AvatarStorageClient,
  paths: (string | null | undefined)[],
): Promise<Map<string, string>> {
  const unique = Array.from(new Set(paths.filter((p): p is string => Boolean(p))));
  const urls = new Map<string, string>();
  if (unique.length === 0) return urls;
  try {
    const bucket = client.storage.from(AVATAR_BUCKET);
    const checked = await Promise.all(unique.map((p) => hasSafeStoredType(bucket, p)));
    const safe = unique.filter((_, i) => checked[i]);
    if (safe.length === 0) return urls;
    const { data, error } = await bucket.createSignedUrls(safe, AVATAR_URL_SECONDS);
    if (error || !data) return urls;
    for (const row of data) {
      if (row.path && row.signedUrl && !row.error && safe.includes(row.path)) {
        urls.set(row.path, row.signedUrl);
      }
    }
  } catch {
    // Storage unreachable (for example the local stack without storage-api): fall back.
  }
  return urls;
}
