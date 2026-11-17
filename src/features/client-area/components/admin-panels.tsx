import { EmptyState } from "@/components/empty-state";
import { StatusPill } from "@/components/status-pill";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { AdminActionForm } from "@/features/applications/components/admin-action-form";
import { formatDateTime } from "@/features/applications/components/status-badge";

import { revokeClientUserAction, withdrawClientUpdateAction } from "../admin-actions";
import { clientStatus } from "../constants";
import type { ClientUserRow } from "../queries";
import type { AdminClientUpdates } from "../schemas";
import { InviteClientUserForm, PublishClientUpdateForm } from "./admin-forms";
import { ClientStatusPill } from "./client-ui";

/** Client users of one client record: list, remove access, invite (admin clients page). */
export function ClientUsersSection({
  clientId,
  users,
  canInvite,
}: {
  clientId: string;
  users: ClientUserRow[];
  canInvite: boolean;
}) {
  return (
    <section className="grid gap-3 border-t pt-4" aria-labelledby={`client-users-${clientId}`}>
      <h3 id={`client-users-${clientId}`} className="text-sm font-medium">
        Client area access
      </h3>
      {users.length === 0 ? (
        <p className="text-muted-foreground text-sm">No one from this client can sign in yet.</p>
      ) : (
        <ul className="divide-y rounded-md border">
          {users.map((u) => (
            <li key={u.id} className="grid gap-2 p-3">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <span className="min-w-0 text-sm break-all">{u.email}</span>
                <StatusPill tone={u.revoked_at ? "neutral" : "success"}>
                  {u.revoked_at ? "Access removed" : "Active"}
                </StatusPill>
              </div>
              <p className="text-muted-foreground text-xs">
                Invited {formatDateTime(u.created_at)}
                {u.revoked_at ? ` · removed ${formatDateTime(u.revoked_at)}` : ""}
                {` · last sign-in ${u.last_sign_in_at ? formatDateTime(u.last_sign_in_at) : "never"}`}
              </p>
              {u.revoked_at ? null : (
                <AdminActionForm
                  action={revokeClientUserAction}
                  submitLabel="Remove access"
                  variant="outline"
                  confirm={`Remove client area access for ${u.email}?`}
                >
                  <input type="hidden" name="clientUserId" value={u.id} />
                </AdminActionForm>
              )}
            </li>
          ))}
        </ul>
      )}
      {canInvite ? (
        <InviteClientUserForm clientId={clientId} />
      ) : (
        <p className="text-muted-foreground text-sm">
          Restore this client to invite people to the client area.
        </p>
      )}
    </section>
  );
}

/** Admin project page: what the client sees, and the updates written for them. */
export function ClientUpdatesCard({
  projectId,
  data,
  archived,
}: {
  projectId: string;
  data: AdminClientUpdates;
  archived: boolean;
}) {
  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-center gap-3">
          <CardTitle>Client updates</CardTitle>
          <ClientStatusPill status={data.client_status} />
        </div>
        <CardDescription>
          The client sees the status &quot;{clientStatus(data.client_status).label}&quot;, published
          updates, deliverable names and their payment milestones. Never the editor, editor pay,
          notes or asset links.{" "}
          {!data.visible_to_client
            ? "Clients do not see this project yet (draft or archived projects are hidden). "
            : ""}
          {!data.has_client
            ? "No client is linked to this project, so no one sees these updates yet."
            : data.active_client_users === 0
              ? "The linked client has no client area users yet (invite them on the Clients page)."
              : `${data.active_client_users} client user${data.active_client_users === 1 ? "" : "s"} can see this project.`}
        </CardDescription>
      </CardHeader>
      <CardContent className="grid gap-6">
        {archived ? (
          <p className="text-muted-foreground text-sm">
            Restore the project to publish updates. Archived projects are hidden from the client.
          </p>
        ) : (
          <PublishClientUpdateForm projectId={projectId} />
        )}
        {data.updates.length === 0 ? (
          <EmptyState title="No client updates yet">
            Published updates appear on the client&apos;s project page, newest first.
          </EmptyState>
        ) : (
          <ol className="grid gap-4">
            {data.updates.map((u) => (
              <li key={u.id} className="grid gap-2 border-l-2 pl-3">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-muted-foreground text-xs tabular-nums">
                    {formatDateTime(u.created_at)}
                  </span>
                  <StatusPill tone={u.published ? "success" : "neutral"}>
                    {u.published ? "Published" : "Withdrawn"}
                  </StatusPill>
                </div>
                <p className="text-sm break-words whitespace-pre-wrap">{u.body}</p>
                {u.published ? (
                  <AdminActionForm
                    action={withdrawClientUpdateAction}
                    submitLabel="Withdraw"
                    variant="outline"
                    confirm="Hide this update from the client?"
                  >
                    <input type="hidden" name="projectId" value={projectId} />
                    <input type="hidden" name="updateId" value={u.id} />
                  </AdminActionForm>
                ) : null}
              </li>
            ))}
          </ol>
        )}
      </CardContent>
    </Card>
  );
}
