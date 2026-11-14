import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { EmptyState } from "@/components/empty-state";
import { SignOutButton } from "@/components/sign-out-button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { RevokeGrantForm } from "@/features/access/components/forms";
import {
  ASSET_PROVIDER_LABEL,
  REVOCATION_REASON_LABEL,
  type AssetProvider,
} from "@/features/access/constants";
import { listPendingRevocations } from "@/features/access/queries";
import { formatDateTime } from "@/features/applications/components/status-badge";
import { requireAdmin } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Access review · Admin · EDITSTATION" };

export default function AccessReviewPage() {
  return (
    <Suspense fallback={<Loading />}>
      <AccessReviewContent />
    </Suspense>
  );
}

async function AccessReviewContent() {
  await requireAdmin();
  const rows = await listPendingRevocations();

  return (
    <AreaShell
      title="Access review"
      subtitle="Folder shares that should be taken back."
      actions={<SignOutButton />}
    >
      <Card>
        <CardHeader>
          <CardTitle>Shares to remove</CardTitle>
          <CardDescription>
            Remove each folder share in Google Drive or Dropbox first, then mark it as removed here.
            This page only records it; it does not change anything in the provider.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {rows.length === 0 ? (
            <EmptyState title="Nothing to review">
              Every recorded folder share still matches an active editor and a live project.
            </EmptyState>
          ) : (
            <ul className="grid gap-4">
              {rows.map((r) => (
                <li key={r.grantId} className="grid gap-3 rounded-lg border p-3 text-sm">
                  <div className="flex flex-wrap justify-between gap-2">
                    <span className="font-medium">{r.editorName}</span>
                    <span className="text-muted-foreground tabular-nums">
                      Shared {formatDateTime(r.sharedAt)}
                    </span>
                  </div>
                  <p>
                    <Link href={`/admin/projects/${r.projectId}`} className="underline">
                      {r.projectTitle}
                    </Link>
                  </p>
                  <p>
                    {ASSET_PROVIDER_LABEL[r.provider as AssetProvider] ?? r.provider} · shared with{" "}
                    <span className="break-all">{r.sharedWithEmail}</span>
                  </p>
                  <p className="text-muted-foreground">
                    {REVOCATION_REASON_LABEL[r.reason] ?? "This share needs a check."}
                  </p>
                  {r.folderUrl ? (
                    <p>
                      <a
                        href={r.folderUrl}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="break-all underline"
                      >
                        Open folder
                      </a>
                    </p>
                  ) : null}
                  <RevokeGrantForm grantId={r.grantId} projectId={null} />
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </AreaShell>
  );
}
