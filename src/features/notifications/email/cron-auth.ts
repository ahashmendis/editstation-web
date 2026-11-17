import "server-only";

import { createHash, timingSafeEqual } from "node:crypto";

function sha256(value: string): Buffer {
  return createHash("sha256").update(value, "utf8").digest();
}

/** Constant-time `Authorization: Bearer <secret>` check. Rejects everything when the secret is unset. */
export function isAuthorised(header: string | null, secret: string | undefined): boolean {
  if (!secret) return false;
  const presented = header?.startsWith("Bearer ") ? header.slice("Bearer ".length) : "";
  // Hashing gives equal-length inputs, so timingSafeEqual never throws or leaks the length.
  const match = timingSafeEqual(sha256(presented), sha256(secret));
  return match && presented.length > 0;
}
