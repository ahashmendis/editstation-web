import { cn } from "@/lib/utils";

// Text wordmark: EDIT in the foreground colour, STATION in brand purple, as in the logo.
// Kept as text until a transparent SVG of the logo is supplied (docs/DESIGN_SYSTEM.md).
// Large sizes only (text-xl and up): the brand purple is 4.1:1 on the dark background, which
// meets contrast for large text but not for small text.
export function Wordmark({ className }: { className?: string }) {
  return (
    <span className={cn("text-xl font-extrabold tracking-tight uppercase", className)}>
      Edit<span className="text-primary">Station</span>
    </span>
  );
}
