# Landing page upgrade: plan (not started)

Status: **plan for owner review. No code, assets or downloads yet.** Requested 2026-11-15, to be
built after Phase 12. Replaces the earlier immersive landing page (`src/app/page.tsx`,
`src/features/landing/`), keeping its two entry points: client inquiry (`/inquire`) and editor
registration (`/apply`).

## 1. What was asked

- Make the landing page look like **adomate.com** (structure and feel) in **EditStation's colours**,
  using the **typography** that page uses.
- Create **graphics of the EditStation dashboard** as the product visuals.
- Use the **Logo folder** (`C:\Users\ahash\Desktop\Logo`) as the clients strip.
- Add a **"More of our work"** section with the videos from four Google Drive folders, and the
  videos shown on **growthscape.tech** under its own "More of our work".

## 2. What the reference pages do (observed 2026-11-15)

**adomate.com** (a Framer site, light theme):

- Header: logo, 6 links, Sign in, primary CTA, secondary CTA.
- Hero: small uppercase eyebrow ("AD CREATION PLATFORM"), a three-line serif headline, a subhead, a
  single input + button, microcopy, a soft yellow-green gradient blob behind the text.
- Looping **client logo strip**, then a grid of **ad examples**, then "The Platform": three feature
  groups beside one product screenshot, a transparency pair, five testimonial cards, a repeated
  closing CTA, footer.
- **Typography (measured in the browser):** headings **IBM Plex Serif**, weight 500, 65px hero and
  56px section titles, line-height about 1.02, letter-spacing -0.01em; body and UI **DM Sans** (body
  300 at 18px, card titles 700 at 18px with -0.3px tracking). The page also loads Manrope 700 (small
  UI), Figtree 600 and Instrument Sans, but they carry almost no text. Page background zinc-200.

**growthscape.tech** (your own site): hero, who we are, two case-study cards, **"More of our work"**
(eight video thumbnails; still images hosted on the site, each linking out to an Instagram reel),
a numbered four-step process with tags, gallery, four service cards, three client quotes, FAQ,
contact form, final CTA.

## 3. Proposed page (section by section)

Copy below is draft. No prices, claims, client results or testimonials are invented; anything not
supplied is left out or marked for you.

| #   | Section              | Content                                                                                                                                                   |
| --- | -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Header               | EditStation logo (icon + text), anchors (Work, Platform, Process), "Join as an editor" (secondary), "Start a project" (primary)                           |
| 2   | Hero                 | Eyebrow "Video editing operations", serif headline, subhead, two entry buttons (replaces Adomate's URL input), brand-purple gradient glow behind the text |
| 3   | Clients strip        | Looping marquee of the Logo folder client logos, "Trusted by" heading, pauses on hover and for reduced motion                                             |
| 4   | Work showcase        | Short muted looping previews in a grid, each opening the full video (section 6)                                                                           |
| 5   | The platform         | Three groups beside one dashboard graphic: Briefs and references; Editors, offers and agreed pay; Review, revisions and payments (section 5)              |
| 6   | Transparency         | Two points taken from real product rules: agreed pay before editing starts; every version, request and payment is recorded                                |
| 7   | Process              | Four to five numbered steps in the Growthscape style (Brief, Match, Edit, Review, Deliver) with tags, from `docs/WORKFLOWS.md`, not invented              |
| 8   | More of our work     | Eight Growthscape reels (thumbnails linking to Instagram) plus the Drive videos                                                                           |
| 9   | Client quotes        | Only if you supply real quotes with permission; otherwise omit the section                                                                                |
| 10  | Closing CTA + footer | Repeat the two entry points; footer links to `/legal/*` placeholders                                                                                      |

Not included: pricing (none decided), a cookie banner (the site sets no analytics or marketing
cookies; add one only if analytics is added later), a Product Hunt badge.

## 4. Look and typography

- **Colours (EditStation brand):** background `#0B0A10`, text `#F5F3FA`, accent `#9643E5`, from
  `docs/DESIGN_SYSTEM.md` and `src/app/globals.css` tokens; no new hard-coded colours.
- Adomate's yellow blobs become soft brand-purple gradients; the light card surfaces become dark
  surfaces with hairline borders. The light theme (system setting) is kept and designed too.
- **Fonts via `next/font/google`:** IBM Plex Serif 500 for headings, DM Sans 300/400/700 for body
  and UI, Manrope 700 only for small buttons and labels if it matches in review. Adomate's scale is
  the starting point: hero 65px (about 44px on phones), section titles 56px, body 18px/300.
- The app (admin, editor, forms) keeps Geist. The wordmark stays as built.
- One orchestrated entrance on load and the logo marquee; no per-section fade-ins; everything
  respects `prefers-reduced-motion`.

## 5. Dashboard graphics

Built in code (React + the real design tokens), not pasted screenshots, so they stay crisp, follow
the theme and contain **no real data**: fictional projects, fictional editor names, sample amounts
clearly neutral. Four panels, drawn from the real screens:

1. Admin project page: brief, references, terms card (Phase 12A look).
2. Editor workspace: offer with agreed pay, brief confirmation, submissions.
3. Review screen: version history, request classification, rounds used.
4. Earnings and notifications: payment milestones, bell with unread items.

Client logos are never placed inside the dashboard graphics. No client prices from real projects.

## 6. Work videos

Source: four Drive folders (file names read on 2026-11-15; contents not opened).

| Folder    | Files                                                                                                   |
| --------- | ------------------------------------------------------------------------------------------------------- |
| Comun     | 7 MP4: Comun 2, Giveaway1, Newspaper Final 2, Pork Benny, Wood Fire Pizza and Pizza 2, Work in Progress |
| Badminton | 1 MP4: Knockout Badminton Final (about 640 MB)                                                          |
| Ryrie     | 6 MP4 + 1 Google Vids: Great Ryrie 2, Carmen, Carmen 3, Final 4, Final 4 without sub, Sri Lankan Dish   |
| Lovenza   | 1 MP4: Lovenza Reel 1 (about 304 MB)                                                                    |

**Approach (recommended):** the site does not host full videos (EditStation rule: no large media in
the app). For each chosen video I make a **short muted looping preview** (about 6-10 s, H.264,
720p, target under 2 MB) and a **poster image**, kept in `public/work/` (total target under 25 MB);
clicking opens the full video on Drive in a new tab. Alternatives rejected: embedding Drive
players (needs each file public, shows Google UI, slow) and hosting full files (hundreds of MB, git
and bandwidth cost).

Needs from you: (a) the original files on this machine, or permission for me to download them
(they are large; downloads need your explicit OK); (b) which 8-12 videos to show; (c) confirmation
that each Drive file is shared so visitors can open it.

Growthscape reels: reuse the eight thumbnails and Instagram links from your own site (permission to
download the images needed).

## 7. Clients strip

The Logo folder has 15 PNGs. Likely clients by name: Active Edge, Agra, Comun, Gearchain, Great
Ryrie, Hydrant, Peak State, Ranshe, First Lane, Labour Hire. **To confirm:** `favicon.png`,
`logo.png`, `Copy of logo.png`, `Copy of MAIN COLOR R@2x.png` and `Copy of HOVER LOGO white.png` look
like own or duplicate marks, not clients. Logos are shown with a neutral treatment (grayscale to
full colour on hover, or a light tint on dark) and resized to under 40 KB each. Need your
confirmation that each client allows its logo to be shown publicly.

## 8. Work plan

| Step | Content                                                                                           | Output                                       |
| ---- | ------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| L1   | Fonts, tokens, page scaffold and header/footer; replace hero (static)                             | New hero in dark and light                   |
| L2   | Clients marquee (optimised logos), dashboard graphic components, platform + transparency sections | Sections 3, 5, 6                             |
| L3   | Preview clips and posters from the videos, work grid, Growthscape reels strip                     | Sections 4, 8 (needs your files and choices) |
| L4   | Process section, closing CTA, copy pass, `legal` links                                            | Sections 7, 10                               |
| L5   | QA: 375/768/1280 px, dark and light, reduced motion, keyboard, e2e smoke update, `npm run check`  | Verified build; screenshots shared with you  |

Each step is a small branch or commit sequence on `landing-upgrade`; I show screenshots after L1
and L2 before continuing. The e2e smoke tests that assert landing text are updated with the page.

## 9. Risks and rules

- **Rights and consent:** client logos and videos are shown only with your confirmation; no
  testimonials are written for you.
- **Weight:** videos lazy-load (`preload="none"`, start when visible), posters first, no autoplay
  with sound, and the hero LCP is text, not video. Target Lighthouse performance 90+ on mobile.
- **Fonts:** three families add load; use `display: swap` and only the needed weights.
- **No invented claims:** headlines and the transparency points use real product rules only.
- **Drive links:** the folder links you sent contain no file IDs; per-video links are needed for
  direct "Watch full video" buttons (or the folder link as a fallback).

## 10. Owner decisions (2026-11-16)

1. **Light base** (not dark): this is a web app; follow Adomate's light feel with EditStation
   purple (#9643E5) as the accent. The dark theme token set stays for the app.
2. **Fonts:** IBM Plex Serif / DM Sans on the landing page only; the app keeps Geist.
3. **Videos:** embeds, my choice. Per-file Drive links do not exist yet, so Drive videos use
   embeds only where a per-file share link is supplied; Growthscape reels use Instagram embeds or
   thumbnail links.
4. **Work shown:** 6 pieces.
5. **Clients strip:** show all logos from the Logo folder (owner confirms permission).
6. **No testimonials section.**
7. **Growthscape reels:** reusable (owner's own company).
8. **Numbers:** no invented figures. Replace stat tiles with factual product-rule highlights
   ("Pay agreed before editing starts", "Every version and request recorded", "Two-step payment
   milestones"), taken from docs/WORKFLOWS.md and BUSINESS_RULES.md.
9. **CTAs:** "Join as an editor" (/apply) is the primary button; "Start a project" (/inquire) is
   secondary.
10. **Name:** EditStation is the public brand; "Lenscape Studios" appears only in the footer.
