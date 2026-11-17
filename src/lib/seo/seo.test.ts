import { afterEach, describe, expect, it, vi } from "vitest";

import robots from "@/app/robots";
import sitemap from "@/app/sitemap";

import { absoluteUrl, indexingEnabled, pageMetadata, publicPaths, siteUrl } from "./site";

afterEach(() => vi.unstubAllEnvs());

describe("indexing switch", () => {
  it("is off unless SEO_INDEXING is exactly 'on'", () => {
    expect(indexingEnabled()).toBe(false);
    vi.stubEnv("SEO_INDEXING", "true");
    expect(indexingEnabled()).toBe(false);
    vi.stubEnv("SEO_INDEXING", "on");
    expect(indexingEnabled()).toBe(true);
  });

  it("closes robots.txt and empties the sitemap while off", () => {
    expect(robots().rules).toEqual([{ userAgent: "*", disallow: "/" }]);
    expect(robots().sitemap).toBeUndefined();
    expect(sitemap()).toEqual([]);
  });

  it("opens public pages only, with a sitemap reference, when on", () => {
    vi.stubEnv("SEO_INDEXING", "on");
    const rule = [robots().rules].flat()[0];
    expect(rule).toMatchObject({ allow: "/" });
    expect(rule.disallow).toEqual(expect.arrayContaining(["/admin", "/editor/", "/editor$"]));
    // Robots rules match by prefix: no rule may swallow a public path (e.g. "/editor" vs "/editors").
    for (const path of publicPaths()) {
      for (const pattern of [rule.disallow].flat()) {
        const prefix = String(pattern).replace(/\$$/, "");
        const exact = String(pattern).endsWith("$");
        expect(exact ? path === prefix : path.startsWith(prefix)).toBe(false);
      }
    }
    expect(robots().sitemap).toBe(absoluteUrl("/sitemap.xml"));

    const urls = sitemap().map((entry) => entry.url);
    expect(urls).toEqual(publicPaths().map((path) => absoluteUrl(path)));
    for (const url of urls) {
      expect(new URL(url).pathname).not.toMatch(
        /^\/(admin|editor|apply|auth|mfa|notifications|sign-in|sign-up)(\/|$)/,
      );
    }
  });

  it("keeps placeholder legal pages out of the sitemap", () => {
    expect(publicPaths()).not.toContain("/legal/privacy");
    expect(publicPaths()).not.toContain("/legal/editor-terms");
  });
});

describe("site url and page metadata", () => {
  it("uses SITE_URL without a trailing slash, else the current production alias", () => {
    expect(siteUrl()).toBe("https://editstation.vercel.app");
    vi.stubEnv("SITE_URL", "https://example.test/");
    expect(siteUrl()).toBe("https://example.test");
    expect(absoluteUrl("/")).toBe("https://example.test");
    expect(absoluteUrl("/editors")).toBe("https://example.test/editors");
  });

  it("gives every page a canonical, Open Graph and Twitter block that agree", () => {
    const meta = pageMetadata({ title: "T", description: "D", path: "/editors" });
    expect(meta.alternates?.canonical).toBe("https://editstation.vercel.app/editors");
    expect(meta.openGraph).toMatchObject({
      url: "https://editstation.vercel.app/editors",
      title: "T",
    });
    expect(meta.twitter).toMatchObject({ card: "summary_large_image", title: "T" });
  });
});
