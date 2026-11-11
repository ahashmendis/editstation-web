import type { Metadata } from "next";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { SignOutButton } from "@/components/sign-out-button";
import { Card, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { requireActiveEditor } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Editor dashboard · EDITSTATION" };

// Own Suspense boundary: per-request data must not block navigation into this page.
export default function EditorPage() {
  return (
    <Suspense fallback={<Loading />}>
      <EditorContent />
    </Suspense>
  );
}

async function EditorContent() {
  const access = await requireActiveEditor();

  return (
    <AreaShell
      title="Editor dashboard"
      subtitle={access.email ?? undefined}
      actions={<SignOutButton />}
    >
      <Card>
        <CardHeader>
          <CardTitle>You&apos;re an approved editor</CardTitle>
          <CardDescription>
            Invitations, assignments and payments will appear here as they become available.
          </CardDescription>
        </CardHeader>
      </Card>
    </AreaShell>
  );
}
