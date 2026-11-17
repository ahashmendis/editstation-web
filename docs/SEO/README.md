# SEO

Status 2026-11-17. The implementation is built and verified locally; **nothing is deployed, the
site is still closed to search engines, and nothing here claims EDITSTATION is indexed, ranking or
receiving organic traffic.** Indexing is opened by one switch, `SEO_INDEXING=on`, which is a launch
decision (`docs/LAUNCH_READINESS.md`), not part of this work.

## 1. Audit (before this work)

**Strengths:** App Router with static or partially prerendered public pages; one `<h1>` and a
sensible h2/h3 hierarchy on the home page; real alt text on client logos and reel thumbnails; WebP
images; `next/font` for the landing fonts; icon and apple-icon; strict security headers; private
areas already gated by sign-in, admin MFA and RLS.

**Problems found:**

| Problem                                                                                                        | Fix                                                                                              |
| -------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Whole site `noindex` from the root layout with one generic "internal platform" description; no way to open it  | One launch switch; per-page metadata                                                             |
| No `robots.txt`, no sitemap, no canonical URLs, no Open Graph or Twitter metadata, no social image, no JSON-LD | Added                                                                                            |
| No `metadataBase`, so relative URLs could not resolve                                                          | `SITE_URL` (falls back to the current Vercel alias)                                              |
| Private pages had no explicit `noindex` of their own (only the root default)                                   | Layout and page `robots` plus an `X-Robots-Tag` header, so they stay private when the site opens |
| No public page for editor-recruitment searches: `/apply` is behind sign-in and `/sign-up` is an auth page      | New public `/editors` page                                                                       |
| Inquiry page title and description were thin                                                                   | Rewritten                                                                                        |
| Two entry points for editors (`/apply` on the home page, `/sign-up` in the public header)                      | Left alone (product flow); noted in section 7                                                    |
| Placeholder legal pages are thin and would be indexed once the site opens                                      | Stay `noindex` and out of the sitemap until the version string stops starting with `placeholder` |

**Indexing and crawling risks:** a `Disallow` on a linked URL can still list it without content, so
only unlinked private areas are disallowed (see section 4). A robots prefix rule `/editor` would
have blocked the public `/editors` page (found by Lighthouse, fixed, covered by a test).

**Performance (local production build, Lighthouse):** home mobile 93/100/100/100 (LCP 1.1 s, CLS 0,
TBT 330 ms), home desktop 100/100/100/100, `/editors` mobile 100/100/100/100. Order is
performance, accessibility, best practices, SEO. The home page's mobile main-thread cost is mostly
the hero entrance animation and the marquee; both are CSS-only already, so no change was made.
`/inquire` could not be measured: it reads form options from Supabase and local Docker was off.

## 2. Keyword strategy and page mapping

Research starting points from the brief, mapped to pages that already exist. No page was created
per keyword variation, and no service pages exist because the service list is undecided (KB3).

| Intent                                                                            | Page            | Primary                    | Secondary                                             | Action                         |
| --------------------------------------------------------------------------------- | --------------- | -------------------------- | ----------------------------------------------------- | ------------------------------ |
| Brand: EDITSTATION, EDITSTATION video editing                                     | `/`             | EDITSTATION                | professional video editing                            | Send a project, join as editor |
| Client: video editing services, outsource video editing, hire an editor           | `/`, `/inquire` | professional video editing | vetted freelance video editors, managed video editing | `/inquire`                     |
| Editor recruitment: freelance video editor jobs, join a freelance editing network | `/editors`      | freelance video editor     | vetted network, how applications work                 | `/sign-up`                     |
| Sri Lanka local intent                                                            | `/` footer line | (not targeted in titles)   |                                                       | n/a until the owner confirms   |

Deliberately **not** targeted yet, because they need facts the owner has not supplied: "social media
editing", "YouTube editing", "Reels and TikTok editing", "business video editing", and any
"Sri Lanka" title keywords. Each needs a real, confirmed service (KB3) before it earns a page.

## 3. What changed

- `src/lib/seo/site.ts`: site URL, indexing switch, `pageMetadata()` (title, description,
  canonical, Open Graph, Twitter), public path list, legal-page publish rule.
- `src/app/robots.ts`, `src/app/sitemap.ts`: closed while the switch is off; open and accurate when on.
- `src/app/layout.tsx`: `metadataBase`, default title and description, robots from the switch.
- `src/app/opengraph-image.tsx`: 1200x630 brand image, also used for Twitter.
- `src/lib/seo/json-ld.tsx`: Organization, WebSite and breadcrumb markup.
- `src/app/editors/page.tsx`: public editor-recruitment page (new).
- `src/app/page.tsx`, `src/app/inquire/page.tsx`: metadata and JSON-LD; hero text now says "video
  editing project"; footer states the Sri Lanka start (owner to confirm the wording).
- `next.config.ts`: `X-Robots-Tag` on private routes, and on every route while the switch is off.
- Private routes: `robots: noindex` on the admin, editor and apply layouts and on the auth, MFA and
  notification pages.
- Header and footer link to `/editors`.

## 4. Robots and sitemap behaviour

- **Switch off (current default):** `robots.txt` is `Disallow: /`, the sitemap is empty, every page
  has `noindex, nofollow` in the HTML and the header. robots.txt is a hint, not access control;
  authentication, MFA and RLS protect private data regardless.
- **Switch on:** crawling allowed; disallowed only `/admin`, `/editor/`, `/editor` (exact), `/auth/`,
  `/mfa`, `/notifications`, `/reset-password`. `/sign-in`, `/sign-up`, `/apply` and `/forgot-password`
  stay crawlable but are `noindex`, so crawlers can read the directive. The sitemap lists `/`,
  `/inquire`, `/editors` (and the two legal pages once real text replaces the placeholders).
  `lastModified` is omitted on purpose: there is no truthful per-page date.
- Canonical host: one hostname from `SITE_URL`. Vercel preview URLs are not canonical for the
  production site. Redirects: none added; none are justified (no URL changed).

## 5. Structured data

Home: `Organization` (name, URL, logo, description, `parentOrganization` Lenscape Studios) and
`WebSite`. `/editors` and `/inquire`: `BreadcrumbList`. All match visible content. **Not used, on
purpose:** LocalBusiness, address, phone, ratings, reviews, awards, `Service` (no confirmed service
list), `FAQPage`, `ContactPoint` (no public contact address is set), `hreflang` (one language).

## 6. Security and indexing verification (local production build)

Verified with indexing on and `SITE_URL` set: `/`, `/editors`, `/inquire` are `index, follow` and
in the sitemap; `/sign-in`, `/sign-up`, the legal placeholders are `noindex`; `/admin`, `/editor`,
`/apply`, `/mfa`, `/auth/confirm` redirect signed-out visitors to sign-in and carry
`X-Robots-Tag: noindex`; with the switch off every page carries `noindex` and `robots.txt` is
`Disallow: /`. No Supabase, RLS, auth, payment, migration or workflow code was touched.
Automated: `src/lib/seo/seo.test.ts` (switch, robots, sitemap, prefix-collision guard, canonical).

## 7. Owner decisions outstanding

1. **Production domain.** `editstation.work` is not confirmed registered. Set `SITE_URL` to it once
   it is. Until then canonicals fall back to `editstation.vercel.app`.
2. **When to open the site** (`SEO_INDEXING=on`). Recommended only after the privacy notice, editor
   terms and a support contact exist (see `docs/LAUNCH_READINESS.md`).
3. **Sri Lanka wording.** The footer says "starting with clients and editors in Sri Lanka". Confirm
   or edit. No eligibility rule for editors is stated anywhere.
4. **Service list (KB3).** Service pages and service keywords wait for it. Do not invent turnaround,
   pricing or inclusions.
5. **Public contact address** (for `ContactPoint` and the legal pages).
6. **One editor entry point.** The home page sends editors to `/apply` (sign-in first); the public
   header sends them to `/sign-up`. `/editors` explains the process and links to `/sign-up`.
7. **Analytics.** None is installed. Decide on GA4 and a cookie/consent approach with counsel before
   adding it; the privacy notice must match.
8. **Client logos and reel titles on the home page** still need the permissions listed in
   `docs/LAUNCH_READINESS.md` section 3.

## 8. Launch checklist (when the owner opens the site)

1. Register the domain; add it in Vercel (Settings, Domains) and set `SITE_URL=https://<domain>`.
2. Set `SEO_INDEXING=on` in Vercel, redeploy (it is read at build time).
3. Check `/robots.txt`, `/sitemap.xml`, view-source on `/`, `/editors`, `/inquire` (canonical points
   at the domain, `robots` is `index, follow`), and that `/admin` still shows `noindex`.
4. **Google Search Console:** add a Domain property; verify with the DNS TXT record Google gives
   (the owner supplies it; never commit a token). Submit `https://<domain>/sitemap.xml`. Use URL
   Inspection on `/`, `/editors`, `/inquire`.
5. **Bing Webmaster Tools:** sign in, import from Search Console or add the site and verify; submit
   the same sitemap.
6. Test the social preview with each platform's sharing debugger.
7. Re-run Lighthouse on the live URLs, and `/inquire` (not measured locally).
8. Wait for real data before saying anything about indexing, ranking or traffic.
