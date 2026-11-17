import type { Metadata } from "next";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { EmptyState } from "@/components/empty-state";
import { SignOutButton } from "@/components/sign-out-button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { AdminActionForm } from "@/features/applications/components/admin-action-form";
import { ClientUsersSection } from "@/features/client-area/components/admin-panels";
import { listClientUsers } from "@/features/client-area/queries";
import { mergeClientsAction, updateClientAction } from "@/features/projects/admin-actions";
import { CreateClientForm } from "@/features/projects/components/create-client-form";
import { selectClassName } from "@/features/projects/components/select-class";
import { listClients } from "@/features/projects/queries";
import { requireAdmin } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Clients · Admin · EDITSTATION" };

export default function ClientsPage() {
  return (
    <Suspense fallback={<Loading />}>
      <ClientsContent />
    </Suspense>
  );
}

async function ClientsContent() {
  await requireAdmin();
  const [clients, clientUsers] = await Promise.all([listClients(), listClientUsers()]);
  const live = clients.filter((c) => c.merged_into_id === null);
  const mergeTargets = live.filter((c) => c.archived_at === null);

  return (
    <AreaShell
      title="Clients"
      subtitle="Admin only. Clients are created when an inquiry is converted, or added here. Open a client to manage who can sign in to the client area."
      actions={<SignOutButton />}
    >
      <Card>
        <CardHeader>
          <CardTitle>Add a client</CardTitle>
        </CardHeader>
        <CardContent>
          <CreateClientForm />
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>All clients</CardTitle>
          <CardDescription>
            Archived clients stay on record so they are never duplicated. Merging moves all projects
            to the client you keep and cannot be undone.
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-3">
          {live.length === 0 ? (
            <EmptyState title="No clients yet">
              Convert an inquiry into a project, or add a client above.
            </EmptyState>
          ) : (
            live.map((c) => (
              <details key={c.id} className="rounded-lg border p-3">
                <summary className="cursor-pointer text-sm font-medium">
                  {c.name}
                  {c.company ? `, ${c.company}` : ""}
                  <span className="text-muted-foreground font-normal"> · {c.email}</span>
                  {c.archived_at ? (
                    <span className="text-muted-foreground font-normal"> · Archived</span>
                  ) : null}
                </summary>
                <div className="grid gap-6 pt-4">
                  <AdminActionForm action={updateClientAction} submitLabel="Save client">
                    <input type="hidden" name="clientId" value={c.id} />
                    <div className="grid gap-4 sm:grid-cols-2">
                      <div className="grid gap-2">
                        <Label htmlFor={`name-${c.id}`}>Contact name</Label>
                        <Input id={`name-${c.id}`} name="name" defaultValue={c.name} required />
                      </div>
                      <div className="grid gap-2">
                        <Label htmlFor={`company-${c.id}`}>Company or agency</Label>
                        <Input
                          id={`company-${c.id}`}
                          name="company"
                          defaultValue={c.company ?? ""}
                        />
                      </div>
                      <div className="grid gap-2">
                        <Label htmlFor={`email-${c.id}`}>Email</Label>
                        <Input
                          id={`email-${c.id}`}
                          name="email"
                          type="email"
                          defaultValue={c.email}
                          required
                        />
                      </div>
                      <div className="grid gap-2">
                        <Label htmlFor={`phone-${c.id}`}>Phone</Label>
                        <Input id={`phone-${c.id}`} name="phone" defaultValue={c.phone ?? ""} />
                      </div>
                    </div>
                    <div className="grid gap-2">
                      <Label htmlFor={`notes-${c.id}`}>Notes</Label>
                      <Textarea
                        id={`notes-${c.id}`}
                        name="notes"
                        rows={2}
                        defaultValue={c.notes ?? ""}
                      />
                    </div>
                    <label className="flex items-center gap-2 text-sm">
                      <Input
                        type="checkbox"
                        name="archived"
                        defaultChecked={c.archived_at !== null}
                        className="size-4 shrink-0"
                      />
                      Archived (untick to restore)
                    </label>
                  </AdminActionForm>

                  <AdminActionForm
                    action={mergeClientsAction}
                    submitLabel="Merge into another client"
                    variant="outline"
                    confirm="Move all projects of this client to the chosen client?"
                  >
                    <input type="hidden" name="sourceId" value={c.id} />
                    <div className="grid gap-2">
                      <Label htmlFor={`merge-${c.id}`}>Client to keep</Label>
                      <select
                        id={`merge-${c.id}`}
                        name="targetId"
                        className={selectClassName}
                        defaultValue=""
                        required
                      >
                        <option value="" disabled>
                          Choose…
                        </option>
                        {mergeTargets
                          .filter((t) => t.id !== c.id)
                          .map((t) => (
                            <option key={t.id} value={t.id}>
                              {t.name}
                              {t.company ? `, ${t.company}` : ""} ({t.email})
                            </option>
                          ))}
                      </select>
                    </div>
                  </AdminActionForm>

                  <ClientUsersSection
                    clientId={c.id}
                    users={clientUsers.filter((u) => u.client_id === c.id)}
                    canInvite={c.archived_at === null}
                  />
                </div>
              </details>
            ))
          )}
        </CardContent>
      </Card>
    </AreaShell>
  );
}
