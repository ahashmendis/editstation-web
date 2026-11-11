import type { Metadata } from "next";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { SignOutButton } from "@/components/sign-out-button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { requireApplicant, type EditorAccessStatus } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Your application · EDITSTATION" };

const statusCopy: Record<EditorAccessStatus, { title: string; body: string }> = {
  none: {
    title: "Account registered",
    body: "Your account is set up. The editor application form is coming soon. Once you submit it, our team will review your portfolio and experience. Registering does not give access to projects.",
  },
  suspended: {
    title: "Editor access suspended",
    body: "Your editor access is currently suspended. Please contact Lenscape Studios if you have questions.",
  },
  revoked: {
    title: "Editor access ended",
    body: "Your editor access has been ended. Please contact Lenscape Studios if you believe this is a mistake.",
  },
  // Active editors are redirected to /editor by the layout gate.
  active: { title: "Approved", body: "" },
};

// Own Suspense boundary: per-request data must not block navigation into this page.
export default function ApplyPage() {
  return (
    <Suspense fallback={<Loading />}>
      <ApplyContent />
    </Suspense>
  );
}

async function ApplyContent() {
  const access = await requireApplicant();
  const copy = statusCopy[access.editorAccessStatus];

  return (
    <AreaShell
      title="Your application"
      subtitle={access.email ?? undefined}
      actions={<SignOutButton />}
    >
      <Card>
        <CardHeader>
          <CardTitle>{copy.title}</CardTitle>
          <CardDescription>{copy.body}</CardDescription>
        </CardHeader>
        <CardContent className="text-muted-foreground text-sm">
          Status: <span className="text-foreground font-medium">{access.editorAccessStatus}</span>
        </CardContent>
      </Card>
    </AreaShell>
  );
}
