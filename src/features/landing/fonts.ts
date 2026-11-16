import { DM_Sans, IBM_Plex_Serif, Manrope } from "next/font/google";

// Landing page only (plan 2026-11-15, section 10): the app keeps Geist. Applied as CSS variables
// on the .landing wrapper and used through the font-landing-* utilities in globals.css.

const plexSerif = IBM_Plex_Serif({
  variable: "--font-plex-serif",
  subsets: ["latin"],
  weight: "500",
  display: "swap",
});

const dmSans = DM_Sans({
  variable: "--font-dm-sans",
  subsets: ["latin"],
  weight: ["300", "400", "700"],
  display: "swap",
});

const manrope = Manrope({
  variable: "--font-manrope",
  subsets: ["latin"],
  weight: "700",
  display: "swap",
});

export const landingFontVariables = `${plexSerif.variable} ${dmSans.variable} ${manrope.variable}`;
