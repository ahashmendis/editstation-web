import { Suspense } from "react";

import { getMyProfileSummary } from "../queries";
import { UserMenuView } from "./user-menu-view";

/**
 * Header menu for the signed-in user: their picture (or initials), a link to manage it, and sign
 * out. The profile read and signed URL are per request, so they stream in their own Suspense
 * boundary; the fallback is a working menu without the picture.
 */
export function UserMenu({
  profileHref,
  withLabel = false,
}: {
  profileHref?: string;
  withLabel?: boolean;
}) {
  return (
    <Suspense
      fallback={
        <UserMenuView
          name={null}
          email={null}
          url={null}
          profileHref={profileHref}
          withLabel={withLabel}
        />
      }
    >
      <UserMenuLoaded profileHref={profileHref} withLabel={withLabel} />
    </Suspense>
  );
}

async function UserMenuLoaded({
  profileHref,
  withLabel,
}: {
  profileHref?: string;
  withLabel: boolean;
}) {
  const me = await getMyProfileSummary();
  return (
    <UserMenuView
      name={me.name}
      email={me.email}
      url={me.avatarUrl}
      profileHref={profileHref}
      withLabel={withLabel}
    />
  );
}
