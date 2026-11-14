// "What we edit": the four service categories from KB §7.1 (placeholders until the service
// list is settled, KB §17.3). Each tile's visual is the format's own frame shape, so the
// decoration carries information instead of filling space.

function Frame({ ratio, label, className }: { ratio: string; label: string; className?: string }) {
  return (
    <div
      aria-hidden="true"
      className={`border-brand-text/60 relative grid place-items-center rounded-md border bg-[color-mix(in_oklch,var(--primary)_10%,transparent)] ${className ?? ""}`}
      style={{ aspectRatio: ratio }}
    >
      <span className="text-brand-text font-mono text-xs tabular-nums">{label}</span>
    </div>
  );
}

function KeyframeCurve() {
  // An ease curve between two keyframes, as drawn in a graph editor.
  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 240 110"
      className="h-auto w-full max-w-[15rem] overflow-visible"
      fill="none"
    >
      <path d="M8 98 H232" className="stroke-border" strokeWidth="1" />
      <path d="M8 98 C 104 98, 128 12, 232 12" className="stroke-brand-text" strokeWidth="2" />
      <path
        d="M8 98 L 104 98 M232 12 L128 12"
        className="stroke-muted-foreground"
        strokeWidth="1"
        strokeDasharray="3 3"
      />
      <circle cx="104" cy="98" r="3.5" className="fill-muted-foreground" />
      <circle cx="128" cy="12" r="3.5" className="fill-muted-foreground" />
      <rect
        x="2"
        y="92"
        width="12"
        height="12"
        transform="rotate(45 8 98)"
        className="fill-primary"
      />
      <rect
        x="226"
        y="6"
        width="12"
        height="12"
        transform="rotate(45 232 12)"
        className="fill-primary"
      />
    </svg>
  );
}

export function ServiceFormats() {
  return (
    <ul className="grid gap-4 md:grid-cols-6 md:grid-rows-[auto_auto]">
      <li className="bg-card flex flex-col gap-6 rounded-2xl border p-6 md:col-span-2 md:row-span-2">
        <div className="flex flex-1 items-center justify-center py-4">
          <Frame ratio="9 / 16" label="9:16" className="w-28 md:w-32" />
        </div>
        <div className="grid gap-1.5">
          <h3 className="text-lg font-semibold tracking-tight">Short-form and social</h3>
          <p className="text-muted-foreground">
            Vertical and square edits for social feeds, built to hold attention from the first
            second.
          </p>
        </div>
      </li>

      <li className="bg-card grid gap-6 rounded-2xl border p-6 sm:grid-cols-[1fr_auto] sm:items-end md:col-span-4">
        <div className="grid gap-1.5">
          <h3 className="text-lg font-semibold tracking-tight">Long-form</h3>
          <p className="text-muted-foreground max-w-[34ch]">
            Interviews, explainers, documentaries and event films, cut for pace across the whole
            running time.
          </p>
        </div>
        <Frame ratio="16 / 9" label="16:9" className="w-full sm:w-56" />
      </li>

      <li className="bg-card grid content-between gap-6 rounded-2xl border p-6 md:col-span-2">
        <div className="bg-background/60 grid place-items-center rounded-md py-5">
          <Frame ratio="2.39 / 1" label="2.39:1" className="w-full max-w-[13rem]" />
        </div>
        <div className="grid gap-1.5">
          <h3 className="text-lg font-semibold tracking-tight">Cinematic and storytelling</h3>
          <p className="text-muted-foreground">
            Story-led edits where structure, rhythm and pacing carry the mood.
          </p>
        </div>
      </li>

      <li className="bg-card grid content-between gap-6 rounded-2xl border p-6 md:col-span-2">
        <div className="grid place-items-center py-3">
          <KeyframeCurve />
        </div>
        <div className="grid gap-1.5">
          <h3 className="text-lg font-semibold tracking-tight">Motion graphics</h3>
          <p className="text-muted-foreground">
            Titles, lower thirds, animated text and graphics that sit cleanly in the cut.
          </p>
        </div>
      </li>
    </ul>
  );
}
