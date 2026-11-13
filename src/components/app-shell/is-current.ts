// Whether a nav item is the current page. Pure so it can be unit-tested.
// `exact` items (an area's overview) match only their own path; others also match sub-pages.
export function isCurrent(pathname: string, item: { href: string; exact?: boolean }) {
  if (pathname === item.href) return true;
  if (item.exact) return false;
  return pathname.startsWith(`${item.href}/`);
}
