/** True when a signed-in visitor opened the public home page and should land in their own area. */
export function shouldEnterArea(pathname: string, isSignedIn: boolean): boolean {
  return isSignedIn && pathname === "/";
}
