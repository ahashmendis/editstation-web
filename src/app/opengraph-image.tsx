import { ImageResponse } from "next/og";

import {
  LOGO_DESK_PATH,
  LOGO_MARK_VIEWBOX,
  LOGO_SCREEN_PATH,
  LOGO_SPARK_PATHS,
  LOGO_TORSO_PATH,
} from "@/components/logo-mark";

// Social preview image (1200x630), shared by Open Graph and Twitter cards: the brand mark on the
// brand purple, with the name and the one-line description. No claims beyond the site copy.
export const alt = "EDITSTATION, professional video editing managed end to end";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

const markSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${LOGO_MARK_VIEWBOX}" fill="none">
<circle cx="168" cy="135" r="51" fill="#fff"/>
<path d="${LOGO_TORSO_PATH}" fill="#fff"/>
<path d="${LOGO_SCREEN_PATH}" stroke="#fff" stroke-width="16" stroke-linejoin="round"/>
<circle cx="285" cy="250" r="12" fill="#fff"/>
<path d="${LOGO_DESK_PATH}" stroke="#fff" stroke-width="16" stroke-linecap="round"/>
<g stroke="#E9D8FF" stroke-width="12" stroke-linecap="round">${LOGO_SPARK_PATHS.map((d) => `<path d="${d}"/>`).join("")}</g>
</svg>`;

const markSrc = `data:image/svg+xml;base64,${Buffer.from(markSvg).toString("base64")}`;

export default function OpengraphImage() {
  return new ImageResponse(
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        alignItems: "center",
        padding: "0 96px",
        gap: 56,
        color: "#fff",
        background: "linear-gradient(135deg, #9643E5 0%, #5A1DA6 100%)",
      }}
    >
      {/* eslint-disable-next-line @next/next/no-img-element -- ImageResponse renders plain img */}
      <img src={markSrc} width={260} height={260} alt="" />
      <div style={{ display: "flex", flexDirection: "column", gap: 20 }}>
        <div style={{ fontSize: 84, fontWeight: 700, letterSpacing: "-0.02em" }}>EDITSTATION</div>
        <div style={{ fontSize: 36, lineHeight: 1.3, color: "#E9D8FF", maxWidth: 640 }}>
          Professional video editing, managed end to end
        </div>
      </div>
    </div>,
    size,
  );
}
