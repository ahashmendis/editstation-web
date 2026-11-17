import Link from "next/link";

import { StatusPill } from "@/components/status-pill";
import { buttonVariants } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { selectClassName } from "@/features/projects/components/select-class";
import { cn } from "@/lib/utils";

import { STAGE_LABEL, STAGE_TONE, type PendingAction, type WorkspaceStage } from "../model";

/** Stage as text in a pill (the tone only adds to the words). */
export function StagePill({ stage }: { stage: WorkspaceStage }) {
  return <StatusPill tone={STAGE_TONE[stage]}>{STAGE_LABEL[stage]}</StatusPill>;
}

/** Who acts next, said in words ("You:" or "Studio:"), never by colour alone. */
export function ActionText({ action }: { action: PendingAction | null }) {
  if (!action) return <span className="text-muted-foreground">Nothing pending</span>;
  return (
    <span>
      <span className={action.by === "you" ? "font-medium" : "text-muted-foreground"}>
        {action.by === "you" ? "You: " : "Studio: "}
      </span>
      {action.text}
    </span>
  );
}

/** Link chips for a filter kept in the URL; other params are kept, the page resets. */
export function FilterChips<T extends string>({
  label,
  basePath,
  param,
  options,
  current,
  params = {},
}: {
  label: string;
  basePath: string;
  param: string;
  options: readonly { value: T; label: string }[];
  current: T;
  params?: Record<string, string | null>;
}) {
  const href = (value: T) => {
    const search = new URLSearchParams();
    for (const [k, v] of Object.entries(params)) if (v) search.set(k, v);
    if (value !== options[0]?.value) search.set(param, value);
    const query = search.toString();
    return query ? `${basePath}?${query}` : basePath;
  };
  return (
    <nav aria-label={label} className="flex flex-wrap gap-2 text-sm">
      {options.map((o) => (
        <Link
          key={o.value}
          href={href(o.value)}
          aria-current={o.value === current ? "page" : undefined}
          className={cn(
            "focus-visible:ring-ring inline-flex min-h-9 items-center rounded-md border px-3 focus-visible:ring-2 focus-visible:outline-none",
            o.value === current
              ? "bg-primary text-primary-foreground border-primary font-medium"
              : "hover:bg-muted",
          )}
        >
          {o.label}
        </Link>
      ))}
    </nav>
  );
}

/** Search and sort as a plain GET form (works without JavaScript); the filter rides along. */
export function SearchSortForm<T extends string>({
  action,
  q,
  sort,
  sorts,
  hidden,
}: {
  action: string;
  q: string;
  sort: T;
  sorts: readonly { value: T; label: string }[];
  hidden: Record<string, string | null>;
}) {
  return (
    <form
      action={action}
      method="get"
      role="search"
      className="grid gap-3 sm:grid-cols-[1fr_12rem_auto] sm:items-end"
    >
      {Object.entries(hidden).map(([k, v]) =>
        v ? <input key={k} type="hidden" name={k} value={v} /> : null,
      )}
      <div className="grid gap-1.5">
        <Label htmlFor="workspace-q">Search by title</Label>
        <Input id="workspace-q" name="q" type="search" defaultValue={q} maxLength={100} />
      </div>
      <div className="grid gap-1.5">
        <Label htmlFor="workspace-sort">Sort by</Label>
        <select id="workspace-sort" name="sort" defaultValue={sort} className={selectClassName}>
          {sorts.map((s) => (
            <option key={s.value} value={s.value}>
              {s.label}
            </option>
          ))}
        </select>
      </div>
      <button type="submit" className={buttonVariants({ variant: "outline" })}>
        Apply
      </button>
    </form>
  );
}

/** Previous / next page links with the current position in words. */
export function Pager({
  basePath,
  page,
  pageCount,
  params,
}: {
  basePath: string;
  page: number;
  pageCount: number;
  params: Record<string, string | null>;
}) {
  if (pageCount <= 1) return null;
  const href = (n: number) => {
    const search = new URLSearchParams();
    for (const [k, v] of Object.entries(params)) if (v) search.set(k, v);
    if (n > 1) search.set("page", String(n));
    const query = search.toString();
    return query ? `${basePath}?${query}` : basePath;
  };
  const link =
    "underline focus-visible:ring-ring rounded-sm focus-visible:ring-2 focus-visible:outline-none";
  return (
    <nav aria-label="Pages" className="flex flex-wrap items-center gap-4 text-sm">
      {page > 1 ? (
        <Link href={href(page - 1)} className={link}>
          Previous page
        </Link>
      ) : null}
      <span className="text-muted-foreground">
        Page {page} of {pageCount}
      </span>
      {page < pageCount ? (
        <Link href={href(page + 1)} className={link}>
          Next page
        </Link>
      ) : null}
    </nav>
  );
}
