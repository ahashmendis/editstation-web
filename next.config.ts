import type { NextConfig } from "next";

// Phase 11 security review: baseline response headers for every route. The app is never meant
// to be framed (clickjacking on admin actions), sniffed, or to leak full URLs (tokens in
// /auth/confirm links) to other sites via Referer.
const securityHeaders = [
  { key: "X-Frame-Options", value: "DENY" },
  { key: "Content-Security-Policy", value: "frame-ancestors 'none'" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
];

// Same switch as src/lib/seo/site.ts (not imported: this file loads before the "@/" alias exists).
const indexingEnabled = () => process.env.SEO_INDEXING === "on";

// Belt and braces for search engines: the pages also set a robots meta tag, but the header covers
// route handlers and non-HTML responses. noindex is not security; access control is separate.
const NOINDEX_HEADER = { key: "X-Robots-Tag", value: "noindex, nofollow" };
const PRIVATE_SOURCES = [
  "/admin/:path*",
  "/editor/:path*",
  "/apply/:path*",
  "/auth/:path*",
  "/mfa",
  "/notifications",
  "/sign-in",
  "/sign-up",
  "/forgot-password",
  "/reset-password",
];

const nextConfig: NextConfig = {
  async headers() {
    return [
      { source: "/(.*)", headers: securityHeaders },
      // Whole site stays out of search until SEO_INDEXING=on.
      ...(indexingEnabled()
        ? PRIVATE_SOURCES.map((source) => ({ source, headers: [NOINDEX_HEADER] }))
        : [{ source: "/(.*)", headers: [NOINDEX_HEADER] }]),
    ];
  },
  cacheComponents: true,
  partialPrefetching: true,
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
