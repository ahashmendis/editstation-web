// "Work" showcase on the landing page (owner decision 4: six pieces). The section and its header
// link render only when this list has entries, so the page ships without it until the videos are
// chosen.
//
// To add a piece: put a poster image (16:9 or 9:16, WebP, under ~150 KB) in public/work/ and add
// an entry below. `href` opens the full video in a new tab: a per-file Google Drive share link or
// an Instagram reel (decision 3). Only add work the owner has cleared for public display.
//
// TODO(owner): choose the six pieces and supply per-file share links (plan section 6).
//   Candidates: Comun, Knockout Badminton Final, Great Ryrie, Lovenza Reel 1, Growthscape reels.

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
  // Example shape (keep commented until the files and links exist):
  // {
  //   title: "Comun",
  //   kind: "Short-form reel",
  //   poster: "/work/comun.webp",
  //   posterAlt: "Still from the Comun reel",
  //   posterWidth: 1080,
  //   posterHeight: 1920,
  //   href: "https://drive.google.com/file/d/<file-id>/view",
  // },
];
