// Client logos for the landing page strip, from the owner's Logo folder (owner decision 5,
// 2026-11-16: show all; the owner confirms permission). Files are trimmed, resized to 120px high
// and saved as WebP in public/clients/ (each well under 40 KB). Own and duplicate marks from the
// folder (favicon, logo, MAIN COLOR, HOVER LOGO) are not clients and are left out.
//
// `height` is the rendered height in px, tuned per logo so wide and square marks look balanced.
// `plate` puts a light backing behind logos with dark parts that would vanish on the dark strip.

export type ClientLogo = {
  name: string;
  src: string;
  width: number;
  height: number;
  displayHeight: number;
  plate?: boolean;
};

export const CLIENT_LOGOS: ClientLogo[] = [
  {
    name: "Active Edge",
    src: "/clients/active-edge.webp",
    width: 480,
    height: 119,
    displayHeight: 28,
  },
  {
    name: "Agra Photography",
    src: "/clients/agra.webp",
    width: 282,
    height: 120,
    displayHeight: 44,
  },
  { name: "Común", src: "/clients/comun.webp", width: 480, height: 108, displayHeight: 28 },
  {
    name: "First Lane",
    src: "/clients/first-lane.webp",
    width: 116,
    height: 120,
    displayHeight: 52,
  },
  { name: "Gearchain", src: "/clients/gearchain.webp", width: 114, height: 120, displayHeight: 44 },
  {
    name: "Great Ryrie",
    src: "/clients/great-ryrie.webp",
    width: 480,
    height: 95,
    displayHeight: 28,
  },
  { name: "Hydrant", src: "/clients/hydrant.webp", width: 57, height: 120, displayHeight: 56 },
  {
    name: "Labour Hire Authority",
    src: "/clients/labour-hire.webp",
    width: 324,
    height: 120,
    displayHeight: 36,
    plate: true,
  },
  {
    name: "Peak State",
    src: "/clients/peak-state.webp",
    width: 152,
    height: 120,
    displayHeight: 48,
  },
  { name: "Ranshe", src: "/clients/ranshe.webp", width: 120, height: 120, displayHeight: 44 },
];
