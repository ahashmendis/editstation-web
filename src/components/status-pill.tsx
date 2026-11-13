import { cn } from "@/lib/utils";

// One look for every status in the app (docs/DESIGN_SYSTEM.md, "Status badges"). The label is
// always text in the normal text colour; only the dot carries the tone, so status never relies on
// colour alone and contrast does not depend on the tone.
//   success: done, positive      warning: needs the admin's attention
//   info:    in progress/waiting danger:  negative, final      neutral: inactive
export type StatusTone = "success" | "warning" | "info" | "danger" | "neutral";

const DOT: Record<StatusTone, string> = {
  success: "bg-success",
  warning: "bg-warning",
  info: "bg-brand-text",
  danger: "bg-destructive",
  neutral: "bg-muted-foreground",
};

export function StatusPill({
  tone,
  children,
  className,
}: {
  tone: StatusTone;
  children: string;
  className?: string;
}) {
  return (
    <span
      className={cn(
        "bg-secondary text-secondary-foreground inline-flex h-6 w-fit shrink-0 items-center gap-1.5 rounded-full border px-2.5 text-xs font-medium whitespace-nowrap",
        className,
      )}
    >
      <span aria-hidden className={cn("size-1.5 rounded-full", DOT[tone])} />
      {children}
    </span>
  );
}
