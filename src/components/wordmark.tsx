// Text wordmark: EDIT in the foreground colour, STATION in brand purple, as in the logo.
// Kept as text until a transparent SVG of the logo is supplied (docs/DESIGN_SYSTEM.md).
// Fixed at text-xl on purpose: the brand purple is 4.1:1 on the dark background, which meets
// contrast for large text but not for small text, so this component has no size override.
export function Wordmark() {
  return (
    <span className="text-xl font-extrabold tracking-tight uppercase">
      Edit<span className="text-primary">Station</span>
    </span>
  );
}
