import type { CSSProperties } from "react";

// The hero visual: one project laid out as an editing timeline. Each track is one party
// (the client, Lenscape Studios, the editor) and each clip is a real step in the workflow
// (docs/WORKFLOWS.md, docs/BUSINESS_RULES.md). Positions are relative (0-100) and only show
// order, not durations: no turnaround is promised. Pure CSS; the playback is the page's one
// orchestrated motion moment and is skipped under prefers-reduced-motion.

type Clip = { label: string; start: number; end: number };
type Track = { name: string; accent?: boolean; clips: Clip[] };

const TRACKS: Track[] = [
  {
    name: "You",
    clips: [
      { label: "Send inquiry", start: 0, end: 12 },
      { label: "Agree the quote", start: 19, end: 34 },
      { label: "Share references", start: 37, end: 51 },
      { label: "Feedback, 3 rounds included", start: 64, end: 86 },
      { label: "Receive files", start: 89, end: 100 },
    ],
  },
  {
    name: "Lenscape",
    accent: true,
    clips: [
      { label: "Review", start: 5, end: 17 },
      { label: "Quote", start: 19, end: 31 },
      { label: "Assign editor", start: 33, end: 46 },
      { label: "Quality check", start: 68, end: 82 },
      { label: "Deliver", start: 87, end: 100 },
    ],
  },
  {
    name: "Editor",
    clips: [
      { label: "Brief and pay agreed", start: 36, end: 52 },
      { label: "Edit", start: 54, end: 70 },
      { label: "Revisions", start: 72, end: 86 },
    ],
  },
];

const RULER = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

export function ProjectTimeline() {
  return (
    <figure className="bg-card/80 relative overflow-hidden rounded-2xl border shadow-[0_30px_80px_-40px_color-mix(in_oklch,var(--primary)_45%,transparent)]">
      <figcaption className="flex flex-wrap items-baseline justify-between gap-x-6 gap-y-1 border-b px-4 py-3 sm:px-5">
        <span className="text-sm font-medium">One project, three tracks</span>
        <span className="text-muted-foreground text-sm">
          You, Lenscape Studios and your editor, in order
        </span>
      </figcaption>

      {/* Scrolls sideways inside itself on narrow screens; the page never does. */}
      <div
        role="region"
        aria-label="Project timeline"
        tabIndex={0}
        className="focus-visible:ring-ring/60 overflow-x-auto outline-none focus-visible:ring-3 focus-visible:ring-inset"
      >
        <div className="grid min-w-[64rem] grid-cols-[5.5rem_1fr] px-4 pt-3 pb-5 sm:px-5">
          {/* Ruler */}
          <div aria-hidden="true" />
          <div
            aria-hidden="true"
            className="text-muted-foreground grid grid-cols-10 border-b pb-1.5 font-mono text-[0.6875rem] tabular-nums"
          >
            {RULER.map((n) => (
              <span key={n} className="border-l pl-1.5">
                00:{String(n).padStart(2, "0")}:00
              </span>
            ))}
          </div>

          {/* Track names */}
          <ul className="grid gap-2 pt-3 pr-3" aria-label="Tracks">
            {TRACKS.map((track) => (
              <li
                key={track.name}
                className="text-muted-foreground flex h-11 items-center text-sm font-medium"
              >
                {track.name}
              </li>
            ))}
          </ul>

          {/* Lanes and playhead */}
          <div className="relative overflow-hidden pt-3">
            <div className="grid gap-2">
              {TRACKS.map((track) => (
                <ol
                  key={track.name}
                  aria-label={`${track.name} steps`}
                  className="bg-muted/40 relative h-11 rounded-md"
                >
                  {track.clips.map((clip) => (
                    <li
                      key={clip.label}
                      className={`landing-clip absolute inset-y-1 flex items-center overflow-hidden rounded-[0.3rem] px-2.5 text-[0.8125rem] leading-tight font-medium ${
                        track.accent
                          ? "bg-primary text-primary-foreground"
                          : "bg-secondary text-secondary-foreground ring-border ring-1 ring-inset"
                      }`}
                      style={
                        {
                          left: `${clip.start}%`,
                          width: `${clip.end - clip.start - 0.6}%`,
                          "--at": clip.start / 100,
                        } as CSSProperties
                      }
                    >
                      <span className="truncate">{clip.label}</span>
                    </li>
                  ))}
                </ol>
              ))}
            </div>

            <div aria-hidden="true" className="pointer-events-none absolute inset-0">
              <div className="landing-playhead absolute inset-y-0 left-0 w-full">
                <span className="bg-brand-text absolute top-0 bottom-0 left-0 w-px" />
                <span className="bg-brand-text absolute top-0 -left-[5px] size-[11px] rotate-45 rounded-[2px]" />
              </div>
            </div>
          </div>
        </div>
      </div>
    </figure>
  );
}
