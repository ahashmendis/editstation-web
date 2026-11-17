import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { EmptyState } from "@/components/empty-state";
import { SignOutButton } from "@/components/sign-out-button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { GrantAccessType, RemovalState } from "@/features/access/components/admin-panels";
import { RemovalForms } from "@/features/access/components/forms";
import {
  ASSET_PROVIDER_LABEL,
  REVOCATION_REASON_LABEL,
  type AssetProvider,
} from "@/features/access/constants";
import { listPendingRevocations } from "@/features/access/queries";
import { formatDateTime } from "@/features/applications/components/status-badge";
import { UserAvatar } from "@/features/profile/components/user-avatar";
import { getAvatarUrlsForUsers } from "@/features/profile/queries";
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
  const avatars = await getAvatarUrlsForUsers(rows.map((r) => r.editorId));

  return (
    <AreaShell
      title="Access review"
      subtitle="Client folder shares whose access should be removed."
      actions={<SignOutButton />}
    >
      <Card>
        <CardHeader>
          <CardTitle>Access to remove</CardTitle>
          <CardDescription>
            The client owns these folders, so only the client can remove access. Ask the client to
            remove the editor&apos;s access and record the request, then record the client&apos;s
            confirmation. This page only records it; it changes nothing in the provider.
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
                    <span className="flex min-w-0 items-center gap-2 font-medium">
                      <UserAvatar url={avatars.get(r.editorId)} name={r.editorName} size="sm" />
                      {r.editorName}
                    </span>
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
                  <GrantAccessType accessType={r.accessType} />
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
                  <RemovalState requestedAt={r.removalRequestedAt} confirmedAt={null} />
                  <RemovalForms
                    grantId={r.grantId}
                    projectId={null}
                    requested={r.removalRequestedAt !== null}
                  />
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </AreaShell>
  );
}
