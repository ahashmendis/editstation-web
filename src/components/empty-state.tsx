import type { ReactNode } from "react";

// An empty list or section: say what is missing and what to do about it (design system, section 6).
export function EmptyState({
  title,
  children,
  action,
}: {
  title: string;
  children?: ReactNode;
  action?: ReactNode;
}) {
  return (
    <div className="grid justify-items-start gap-1 py-2">
      <p className="text-sm font-medium">{title}</p>
      {children ? <p className="text-muted-foreground max-w-prose text-sm">{children}</p> : null}
      {action ? <div className="pt-2">{action}</div> : null}
    </div>
  );
}
