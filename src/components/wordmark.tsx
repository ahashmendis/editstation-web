import { LogoMark } from "@/components/logo-mark";
import { cn } from "@/lib/utils";

// Primary logo: the mark, a thin purple divider, then EDIT (foreground) + STATION (brand purple).
// This full lockup is the default everywhere; `iconOnly` is for very tight spots only (the browser
// and app icons are separate files: src/app/icon.svg and src/app/apple-icon.tsx).
// The text stays at text-xl on purpose: the brand purple is 4.1:1 on the dark background, which
// meets contrast for large text but not for small text, so there is no text size override.
// The mark's square box is taller than the drawing, so negative margins keep header heights as
// they were with the text-only wordmark.
export function Wordmark({ iconOnly = false }: { iconOnly?: boolean }) {
  return (
    <span
      role="img"
      aria-label="EditStation"
      className="inline-flex items-center gap-2.5 align-middle"
    >
      <LogoMark className={cn("-my-3 size-12 shrink-0", !iconOnly && "-ml-1.5")} />
      {iconOnly ? null : (
        <>
          <span aria-hidden className="bg-primary h-6 w-px shrink-0" />
          <span aria-hidden className="text-xl font-extrabold tracking-tight uppercase">
            Edit<span className="text-primary">Station</span>
          </span>
        </>
      )}
    </span>
  );
}
