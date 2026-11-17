import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { SignOutButton } from "@/components/sign-out-button";
import { Card, CardContent } from "@/components/ui/card";
import { SUPPORT_EMAIL } from "@/lib/site-contact";
import { getAccess, homePathFor } from "@/lib/auth/access";
import { NO_INDEX } from "@/lib/seo/site";

export const metadata: Metadata = { title: "Client access ended · EDITSTATION", robots: NO_INDEX };

// Shown to an account whose client access was removed by the studio. It shows no project data.
export default function ClientAccessEndedPage() {
  return (
    <Suspense fallback={<Loading />}>
      <AccessEnded />
    </Suspense>
  );
}

async function AccessEnded() {
  const access = await getAccess();
  if (!access) redirect("/client/sign-in");
  const home = homePathFor(access);
  if (home !== "/client/access-ended") redirect(home);
  return (
    <AreaShell title="Client access ended" actions={<SignOutButton />}>
      <Card>
        <CardContent className="grid gap-2 text-sm">
          <p>The studio has removed this account&apos;s access to the client area.</p>
          <p className="text-muted-foreground">
            If you think this is a mistake, contact the studio at{" "}
            <a className="underline" href={`mailto:${SUPPORT_EMAIL}`}>
              {SUPPORT_EMAIL}
            </a>
            .
          </p>
        </CardContent>
      </Card>
    </AreaShell>
  );
}
