// "Work" showcase on the landing page (owner decision 4: six pieces). The section and its header
// link render only when this list has entries, so the page ships without it until the videos are
// chosen.
//
// To add a piece: put a poster image (16:9 or 9:16, WebP, under ~150 KB) in public/work/ and add
// an entry below. `href` opens the full video in a new tab: a per-file Google Drive share link or
// an Instagram reel (decision 3). Only add work the owner has cleared for public display.
//
// Current six: Growthscape's "More of our work" reels (owner's own company; thumbnails reused with
// the owner's authorisation), each linking to its Instagram reel.

export type WorkItem = {
  /** Short title shown under the poster, e.g. the piece or campaign name. */
  title: string;
  /** Optional one-line context, e.g. "Short-form reel". No invented results or figures. */
  kind?: string;
  /** Poster path under public/, e.g. "/work/comun-reel.webp". */
  poster: string;
  /** Describes the poster for screen readers. */
  posterAlt: string;
  posterWidth: number;
  posterHeight: number;
  /** Where the full video lives (opens in a new tab). */
  href: string;
};

export const WORK_SLOTS = 6;

export const WORK: WorkItem[] = [
  {
    title: "Great Ryrie Café: Fresh Berries",
    kind: "Short-form reel",
    poster: "/work/reel-01.webp",
    posterAlt: "Thumbnail of the reel Great Ryrie Café: Fresh Berries",
    posterWidth: 360,
    posterHeight: 640,
    href: "https://www.instagram.com/reel/DZ4ePzrieGS/",
  },
  {
    title: "Hydrant Food Hall: Surf & Turf",
    kind: "Short-form reel",
    poster: "/work/reel-02.webp",
    posterAlt: "Thumbnail of the reel Hydrant Food Hall: Surf & Turf",
    posterWidth: 360,
    posterHeight: 640,
    href: "https://www.instagram.com/reel/DTT5j1-gUTh/",
  },
  {
    title: "Great Ryrie Café: Chilli Prawn Scramble",
    kind: "Short-form reel",
    poster: "/work/reel-08.webp",
    posterAlt: "Thumbnail of the reel Great Ryrie Café: Chilli Prawn Scramble",
    posterWidth: 361,
    posterHeight: 640,
    href: "https://www.instagram.com/reel/DNI1N4mPBq1/",
  },
  {
    title: "Growthscape: You Need a System",
    kind: "Short-form reel",
    poster: "/work/reel-03.webp",
    posterAlt: "Thumbnail of the reel Growthscape: You Need a System",
    posterWidth: 360,
    posterHeight: 640,
    href: "https://www.instagram.com/p/DYNV6Sxj6KI/",
  },
  {
    title: "Growthscape: People Remember What They See",
    kind: "Short-form reel",
    poster: "/work/reel-04.webp",
    posterAlt: "Thumbnail of the reel Growthscape: People Remember What They See",
    posterWidth: 360,
    posterHeight: 640,
    href: "https://www.instagram.com/p/DbI-4uMiSiF/",
  },
  {
    title: "Growthscape: Virality is an Algorithm",
    kind: "Short-form reel",
    poster: "/work/reel-06.webp",
    posterAlt: "Thumbnail of the reel Growthscape: Virality is an Algorithm",
    posterWidth: 360,
    posterHeight: 640,
    href: "https://www.instagram.com/p/DYIL_buiXrQ/",
  },
];
