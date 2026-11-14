import { ImageResponse } from "next/og";

import {
  LOGO_DESK_PATH,
  LOGO_MARK_VIEWBOX,
  LOGO_SCREEN_PATH,
  LOGO_SPARK_PATHS,
  LOGO_TORSO_PATH,
} from "@/components/logo-mark";

// Apple touch icon (180x180 PNG): white mark on the purple gradient tile, as src/app/icon.svg.
// Full-bleed square: iOS applies its own rounded mask.
export const size = { width: 180, height: 180 };
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

export default function AppleIcon() {
  return new ImageResponse(
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        background: "linear-gradient(135deg, #9643E5 0%, #5A1DA6 100%)",
      }}
    >
      {/* eslint-disable-next-line @next/next/no-img-element -- ImageResponse renders plain img */}
      <img src={markSrc} width={160} height={160} alt="" />
    </div>,
    { ...size },
  );
}
