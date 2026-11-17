import type { MetadataRoute } from "next";

import { absoluteUrl, indexingEnabled } from "@/lib/seo/site";

// robots.txt is a crawling hint, not access control: every private area is protected by sign-in,
// the admin MFA gate and RLS. Closed until SEO_INDEXING=on. When open, only areas with no public
// link are disallowed; /sign-in, /sign-up, /apply and the like stay crawlable so crawlers can read
// their noindex directive (a disallowed but linked URL can still be listed without content).
export default function robots(): MetadataRoute.Robots {
  if (!indexingEnabled()) {
    return { rules: [{ userAgent: "*", disallow: "/" }] };
  }
  return {
    rules: [
      {
        userAgent: "*",
        allow: "/",
        // Prefix rules: "/editor" would also block the public /editors page, so match the dashboard
        // folder and the bare path exactly.
        disallow: [
          "/admin",
          "/editor/",
          "/editor$",
          "/auth/",
          "/mfa",
          "/notifications",
          "/reset-password",
        ],
      },
    ],
    sitemap: absoluteUrl("/sitemap.xml"),
  };
}
