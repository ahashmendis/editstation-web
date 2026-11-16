// Client logos for the landing page strip, from the owner's Logo folder (owner decision 5,
// 2026-11-16: show all; the owner confirms permission). Files are trimmed, resized to 120px high
// and saved as WebP in public/clients/ (each well under 40 KB). Own and duplicate marks from the
// folder (favicon, logo, MAIN COLOR, HOVER LOGO) are not clients and are left out.
//
// `height` is the rendered height in px, tuned per logo so wide and square marks look balanced.
// Files are black silhouettes (alpha only); the strip sets opacity.

export type ClientLogo = {
  name: string;
  src: string;
  width: number;
  height: number;
  displayHeight: number;
};

export const CLIENT_LOGOS: ClientLogo[] = [
  {
    name: "Active Edge",
    src: "/clients/active-edge-black.webp",
    width: 480,
    height: 119,
    displayHeight: 28,
  },
  {
    name: "Agra Photography",
    src: "/clients/agra-black.webp",
    width: 282,
    height: 120,
    displayHeight: 44,
  },
  { name: "Común", src: "/clients/comun-black.webp", width: 480, height: 108, displayHeight: 28 },
  {
    name: "First Lane",
    src: "/clients/first-lane-black.webp",
    width: 116,
    height: 120,
    displayHeight: 52,
  },
  {
    name: "Gearchain",
    src: "/clients/gearchain-black.webp",
    width: 114,
    height: 120,
    displayHeight: 44,
  },
  {
    name: "Great Ryrie",
    src: "/clients/great-ryrie-black.webp",
    width: 480,
    height: 95,
    displayHeight: 28,
  },
  {
    name: "Hydrant",
    src: "/clients/hydrant-black.webp",
    width: 57,
    height: 120,
    displayHeight: 56,
  },
  {
    name: "Labour Hire Authority",
    src: "/clients/labour-hire-black.webp",
    width: 324,
    height: 120,
    displayHeight: 36,
  },
  {
    name: "Peak State",
    src: "/clients/peak-state-black.webp",
    width: 152,
    height: 120,
    displayHeight: 48,
  },
  { name: "Ranshe", src: "/clients/ranshe-black.webp", width: 120, height: 120, displayHeight: 44 },
];
