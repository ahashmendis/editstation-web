import Link from "next/link";

import { cn } from "@/lib/utils";

import { PROJECT_TABS, type ProjectTab } from "../model";

/** Server-rendered tabs as links (?tab=); Overview has no param so old links keep working. */
export function ProjectTabs({ projectId, current }: { projectId: string; current: ProjectTab }) {
  return (
    <nav aria-label="Project sections">
      <ul className="flex flex-wrap gap-1 border-b pb-2">
        {PROJECT_TABS.map((t) => (
          <li key={t.value}>
            <Link
              href={
                t.value === "overview"
                  ? `/editor/projects/${projectId}`
                  : `/editor/projects/${projectId}?tab=${t.value}`
              }
              aria-current={t.value === current ? "page" : undefined}
              scroll={false}
              className={cn(
                "focus-visible:ring-ring inline-flex min-h-11 items-center rounded-md px-3 text-sm focus-visible:ring-2 focus-visible:outline-none",
                t.value === current
                  ? "bg-muted font-medium underline underline-offset-4"
                  : "text-muted-foreground hover:bg-muted/60 hover:text-foreground",
              )}
            >
              {t.label}
            </Link>
          </li>
        ))}
      </ul>
    </nav>
  );
}
