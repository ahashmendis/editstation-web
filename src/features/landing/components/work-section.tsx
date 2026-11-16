import Image from "next/image";
import { ArrowUpRight } from "lucide-react";

import { container, eyebrow, focusRing, sectionTitle } from "@/features/landing/styles";
import { WORK, WORK_SLOTS, type WorkItem } from "@/features/landing/work";

// Six-slot work grid (owner decision 4). Renders nothing until src/features/landing/work.ts has
// entries. Posters only; each opens the full video elsewhere, so no video is hosted here.

function WorkCard({ item }: { item: WorkItem }) {
  return (
    <li>
      <a
        href={item.href}
        target="_blank"
        rel="noopener noreferrer"
        className={`${focusRing} group grid gap-3 rounded-2xl`}
      >
        <span className="bg-secondary relative block aspect-[4/5] overflow-hidden rounded-2xl border">
          <Image
            src={item.poster}
            alt={item.posterAlt}
            width={item.posterWidth}
            height={item.posterHeight}
            sizes="(min-width: 1024px) 360px, (min-width: 640px) 50vw, 100vw"
            className="size-full object-cover transition-transform duration-500 ease-out group-hover:scale-[1.03] motion-reduce:transition-none motion-reduce:group-hover:scale-100"
          />
        </span>
        <span className="flex items-start justify-between gap-3">
          <span className="grid">
            <span className="font-bold tracking-[-0.02em]">{item.title}</span>
            {item.kind ? (
              <span className="text-muted-foreground text-sm font-light">{item.kind}</span>
            ) : null}
          </span>
          <ArrowUpRight aria-hidden className="text-muted-foreground mt-0.5 size-5 shrink-0" />
          <span className="sr-only">(opens in a new tab)</span>
        </span>
      </a>
    </li>
  );
}

export function WorkSection({ items = WORK }: { items?: WorkItem[] }) {
  const shown = items.slice(0, WORK_SLOTS);
  if (shown.length === 0) return null;
  return (
    <section
      id="work"
      aria-labelledby="work-title"
      className={`${container} scroll-mt-20 py-20 lg:py-28`}
    >
      <p className={eyebrow}>Work</p>
      <h2 id="work-title" className={`${sectionTitle} mt-4`}>
        More of our work.
      </h2>
      <ul className="mt-12 grid gap-x-6 gap-y-10 sm:grid-cols-2 lg:grid-cols-3">
        {shown.map((item) => (
          <WorkCard key={item.href} item={item} />
        ))}
      </ul>
    </section>
  );
}
