// Whether a nav item is the current page. Pure so it can be unit-tested.
// `exact` items (an area's overview) match only their own path; others also match sub-pages.
export function isCurrent(pathname: string, item: { href: string; exact?: boolean }) {
  if (pathname === item.href) return true;
  if (item.exact) return false;
  return pathname.startsWith(`${item.href}/`);
}

/**
 * Whether `item` is the current page and no other item matches the path more specifically (so
 * "/client/projects/new" marks "New project", not also "Projects").
 */
export function isMostSpecificCurrent(
  pathname: string,
  item: { href: string; exact?: boolean },
  items: readonly { href: string; exact?: boolean }[],
) {
  if (!isCurrent(pathname, item)) return false;
  return !items.some((other) => other.href.length > item.href.length && isCurrent(pathname, other));
}
