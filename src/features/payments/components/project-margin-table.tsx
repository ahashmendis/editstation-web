import type { ProjectMargin } from "../summary";
import { Money } from "./money";

export type ProjectMarginRow = { projectId: string; title: string; margin: ProjectMargin };

function MarginValue({ margin }: { margin: ProjectMargin }) {
  if (margin.kind === "no_price")
    return <span className="text-muted-foreground">No client price</span>;
  if (margin.kind === "mixed_currency")
    return <span className="text-muted-foreground">Currencies differ</span>;
  return (
    <span className="text-right">
      <Money amount={margin.amount} currency={margin.currency} />
      {margin.includesOnHold ? (
        <span className="text-muted-foreground block text-xs">Includes on-hold pay</span>
      ) : null}
    </span>
  );
}

/** Admin only: client price minus net editor pay per project. */
export function ProjectMarginTable({ rows }: { rows: ProjectMarginRow[] }) {
  return (
    <ul className="grid gap-2 text-sm">
      {rows.map((row) => (
        <li
          key={row.projectId}
          className="flex flex-wrap items-start justify-between gap-2 border-t pt-2 first:border-t-0 first:pt-0"
        >
          <span className="break-words">{row.title}</span>
          <MarginValue margin={row.margin} />
        </li>
      ))}
    </ul>
  );
}
