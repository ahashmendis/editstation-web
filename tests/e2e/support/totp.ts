import { createHmac } from "node:crypto";

// Minimal RFC 6238 TOTP (SHA-1, 30 s, 6 digits) so e2e tests can pass admin MFA without adding a
// dependency. Test-only: never import this from app code.

const BASE32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

export function base32Decode(input: string): Buffer {
  const clean = input.replace(/=+$/, "").replace(/\s+/g, "").toUpperCase();
  let bits = 0;
  let value = 0;
  const out: number[] = [];
  for (const char of clean) {
    const index = BASE32.indexOf(char);
    if (index === -1) throw new Error(`Invalid base32 character: ${char}`);
    value = (value << 5) | index;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Buffer.from(out);
}

export function totpStep(timeMs = Date.now(), periodSeconds = 30): number {
  return Math.floor(timeMs / 1000 / periodSeconds);
}

export function totp(secretBase32: string, timeMs = Date.now(), digits = 6): string {
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(totpStep(timeMs)));
  const hmac = createHmac("sha1", base32Decode(secretBase32)).update(counter).digest();
  const offset = hmac[hmac.length - 1] & 0x0f;
  const code = (hmac.readUInt32BE(offset) & 0x7fffffff) % 10 ** digits;
  return code.toString().padStart(digits, "0");
}
