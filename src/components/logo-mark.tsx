// The EditStation mark: an editor seated at a laptop with three purple "spark" strokes.
// Redrawn by hand from the brand identity board on a 400-unit square grid. The figure, laptop and
// desk use currentColor; the screen is an outline (not a cutout), so its interior is whatever sits
// behind the mark and it reads on both themes. The sparks use the brand purple token.
// The same geometry is reused by src/app/apple-icon.tsx; keep src/app/icon.svg in step by hand.

export const LOGO_MARK_VIEWBOX = "0 0 400 400";

/** Torso with the arm reaching to the keyboard (the L-shaped notch separates the forearm). */
export const LOGO_TORSO_PATH =
  "M50 304C56 240 86 191 150 191H172C186 191 195 201 195 215V270.5H140L130.5 240A4.5 4.5 0 0 0 121.5 242L132.5 279.5H195V304Z";
/** Laptop screen, drawn as a stroked outline. */
export const LOGO_SCREEN_PATH = "M227 195H375L350 293H200Z";
/** Desk / base line. */
export const LOGO_DESK_PATH = "M17 308H357";
/** The three spark strokes, above-right of the laptop. */
export const LOGO_SPARK_PATHS = ["M287 141L302 161", "M332 118V151", "M381 138L363 161"];

export function LogoMark({ className, title }: { className?: string; title?: string }) {
  return (
    <svg
      viewBox={LOGO_MARK_VIEWBOX}
      xmlns="http://www.w3.org/2000/svg"
      className={className}
      fill="none"
      role={title ? "img" : undefined}
      aria-hidden={title ? undefined : true}
      aria-label={title}
      focusable="false"
    >
      {title ? <title>{title}</title> : null}
      <circle cx="168" cy="135" r="51" fill="currentColor" />
      <path d={LOGO_TORSO_PATH} fill="currentColor" />
      <path d={LOGO_SCREEN_PATH} stroke="currentColor" strokeWidth="16" strokeLinejoin="round" />
      <circle cx="285" cy="250" r="12" fill="currentColor" />
      <path d={LOGO_DESK_PATH} stroke="currentColor" strokeWidth="16" strokeLinecap="round" />
      <g stroke="var(--primary)" strokeWidth="12" strokeLinecap="round">
        {LOGO_SPARK_PATHS.map((d) => (
          <path key={d} d={d} />
        ))}
      </g>
    </svg>
  );
}
