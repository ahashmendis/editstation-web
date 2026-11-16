import Image from "next/image";
import { ArrowUpRight } from "lucide-react";

import { container, eyebrow, focusRing, sectionTitle } from "@/features/landing/styles";
import { WORK, WORK_SLOTS, type WorkItem } from "@/features/landing/work";

// Six-reel horizontal strip that drifts slowly and pauses on hover or focus (owner decision 4);
// a static wrapped row under reduced motion (same CSS as the clients strip). Renders nothing until src/features/landing/work.ts has
// entries. Posters only; each opens the full video elsewhere, so no video is hosted here.

function WorkCard({ item, hidden }: { item: WorkItem; hidden: boolean }) {
  return (
    <li className="w-44 shrink-0 sm:w-52">
      <a
        href={item.href}
        tabIndex={hidden ? -1 : undefined}
        target="_blank"
        rel="noopener noreferrer"
        className={`${focusRing} group grid gap-3 rounded-2xl`}
      >
        <span className="bg-secondary relative block aspect-[9/16] overflow-hidden rounded-2xl border">
          <Image
            src={item.poster}
            alt={item.posterAlt}
            width={item.posterWidth}
            height={item.posterHeight}
            sizes="208px"
            loading="lazy"
            className="size-full object-cover transition-transform duration-500 ease-out group-hover:scale-[1.03] motion-reduce:transition-none motion-reduce:group-hover:scale-100"
          />
        </span>
        <span className="flex items-start justify-between gap-3">
          <span className="grid">
            <span className="text-sm font-bold tracking-[-0.02em] text-pretty">{item.title}</span>
            {item.kind ? (
              <span className="text-muted-foreground text-sm font-light">{item.kind}</span>
            ) : null}
          </span>
          <ArrowUpRight aria-hidden className="text-muted-foreground mt-0.5 size-5 shrink-0" />
          <span className="sr-only">Watch reel on Instagram (opens in a new tab)</span>
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
      <div className="landing-marquee landing-marquee-cards mt-12 overflow-hidden">
        <div className="landing-marquee-track">
          {[0, 1].map((copy) => (
            <ul
              key={copy}
              aria-label={copy === 0 ? "Recent reels" : undefined}
              aria-hidden={copy === 1 ? "true" : undefined}
              className="landing-marquee-copy"
            >
              {shown.map((item) => (
                <WorkCard key={item.href} item={item} hidden={copy === 1} />
              ))}
            </ul>
          ))}
        </div>
      </div>
    </section>
  );
}
