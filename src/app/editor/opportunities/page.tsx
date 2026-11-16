import type { Metadata } from "next";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { SignOutButton } from "@/components/sign-out-button";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { CONFIDENTIALITY_NOTICE } from "@/features/opportunities/constants";
import { EditorOpportunityList } from "@/features/opportunities/components/editor-list";
import { listMyOpportunities, type EditorOpportunity } from "@/features/opportunities/queries";
import { requireActiveEditor } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Open opportunities · EDITSTATION" };

export default function EditorOpportunitiesPage() {
  return (
    <Suspense fallback={<Loading />}>
      <OpportunitiesContent />
    </Suspense>
  );
}

async function OpportunitiesContent() {
  await requireActiveEditor();
  let rows: EditorOpportunity[] | null = null;
  try {
    rows = await listMyOpportunities();
  } catch {
    rows = null;
  }

  return (
    <AreaShell
      title="Open opportunities"
      subtitle="Projects Lenscape has opened to active editors. Register interest; Lenscape chooses one editor and sends them the usual offer."
      actions={<SignOutButton />}
    >
      <p className="text-sm font-medium" role="note">
        {CONFIDENTIALITY_NOTICE}
      </p>
      {rows === null ? (
        <Alert variant="destructive" role="alert">
          <AlertDescription>
            Opportunities could not be loaded. Reload the page to try again.
          </AlertDescription>
        </Alert>
      ) : (
        <EditorOpportunityList rows={rows} />
      )}
    </AreaShell>
  );
}
