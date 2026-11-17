import type { Metadata } from "next";

import { EDITOR_TERMS_VERSION, PRIVACY_NOTICE_VERSION } from "@/features/applications/constants";

export const SITE_NAME = "EDITSTATION";

/**
 * Canonical origin. Set SITE_URL once the production domain is registered and verified
 * (docs/SEO/README.md). Until then it falls back to the current Vercel production alias, which
 * is the only origin that actually exists today. Never guess a domain here.
 */
const FALLBACK_SITE_URL = "https://editstation.vercel.app";

export function siteUrl(): string {
  const raw = process.env.SITE_URL?.trim() || FALLBACK_SITE_URL;
  return raw.replace(/\/+$/, "");
}

export function absoluteUrl(path: string): string {
  return `${siteUrl()}${path === "/" ? "" : path}`;
}

/**
 * Launch switch. Search engines are told to stay away unless SEO_INDEXING is exactly "on".
 * Read at build time (redeploy after changing it). Default off: the owner decides when the site
 * goes public (docs/LAUNCH_READINESS.md).
 */
export function indexingEnabled(): boolean {
  return process.env.SEO_INDEXING === "on";
}

export const NO_INDEX: NonNullable<Metadata["robots"]> = { index: false, follow: false };

export function defaultRobots(): NonNullable<Metadata["robots"]> {
  return indexingEnabled() ? { index: true, follow: true } : NO_INDEX;
}

/** The legal pages stay out of search until real text replaces the placeholder versions. */
export function legalPagesPublished(): boolean {
  return (
    !PRIVACY_NOTICE_VERSION.startsWith("placeholder") &&
    !EDITOR_TERMS_VERSION.startsWith("placeholder")
  );
}

type PageMetadataInput = { title: string; description: string; path: string };

/** Title, description, canonical, Open Graph and Twitter card for an indexable public page. */
export function pageMetadata({ title, description, path }: PageMetadataInput): Metadata {
  const url = absoluteUrl(path);
  return {
    title,
    description,
    alternates: { canonical: url },
    openGraph: { title, description, url, siteName: SITE_NAME, type: "website", locale: "en_US" },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: [absoluteUrl("/opengraph-image")],
    },
  };
}

/** Public pages that belong in the sitemap, with the reason each one is indexable. */
export function publicPaths(): string[] {
  const paths = ["/", "/inquire", "/editors"];
  if (legalPagesPublished()) paths.push("/legal/privacy", "/legal/editor-terms");
  return paths;
}
