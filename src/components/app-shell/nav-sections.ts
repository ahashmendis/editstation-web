// Navigation entries: plain items or labelled groups. Pure so it can be unit-tested.

export type BaseNavItem<Icon extends string = string> = {
  href: string;
  label: string;
  icon: Icon;
  /** Only the exact path is "current" (for an area's overview page). */
  exact?: boolean;
};

/** A labelled set of items (rendered under a small heading). */
export type NavGroup<Item> = { group: string; items: Item[] };

export const isNavGroup = <Item>(entry: Item | NavGroup<Item>): entry is NavGroup<Item> =>
  typeof entry === "object" && entry !== null && "group" in entry;

/** Plain items render as one untitled section; consecutive plain items stay together. */
export function toSections<Item>(
  entries: (Item | NavGroup<Item>)[],
): { title: string | null; items: Item[] }[] {
  const sections: { title: string | null; items: Item[] }[] = [];
  for (const entry of entries) {
    if (isNavGroup(entry)) {
      sections.push({ title: entry.group, items: entry.items });
    } else {
      const last = sections.at(-1);
      if (last && last.title === null) last.items.push(entry);
      else sections.push({ title: null, items: [entry] });
    }
  }
  return sections;
}
