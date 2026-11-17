import type { MetadataRoute } from "next";

import { absoluteUrl, indexingEnabled, publicPaths } from "@/lib/seo/site";

// Only canonical, public marketing URLs. No admin, editor, auth or workflow routes, and no
// lastModified: there is no truthful per-page date source, and a wrong date is worse than none.
export default function sitemap(): MetadataRoute.Sitemap {
  if (!indexingEnabled()) return [];
  return publicPaths().map((path) => ({ url: absoluteUrl(path) }));
}
