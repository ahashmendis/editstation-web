import { EmptyState } from "@/components/empty-state";
import { StatusPill } from "@/components/status-pill";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { formatDateTime } from "@/features/applications/components/status-badge";

import {
  ACCESS_REASON_LABEL,
  ASSET_PROVIDER_LABEL,
  EARLY_ACCESS_HINT,
  editorAccessWarning,
  editorLabel,
  formatMoney,
  isLiveAssignment,
  summariseEditorLabels,
  type AccessReason,
  type AssetProvider,
} from "../constants";
import type { getProjectAccessData } from "../queries";
import {
  AddNoteForm,
  AssetsForm,
  ConfirmAssignmentForm,
  EarlyAccessToggle,
  InviteEditorsForm,
  MakeOfferForm,
  ReassignForm,
  RecordGrantForm,
  RespondForms,
  RevokeAccessForm,
  RevokeGrantForm,
  WithdrawOfferForm,
} from "./forms";
import { NegotiationHistory } from "./negotiation-history";

type Data = Awaited<ReturnType<typeof getProjectAccessData>>;

type Props = {
  projectId: string;
  /** Archived or cancelled: most writes are refused. */
  locked: boolean;
  /** Project is open (and has been opened before), so editors can be invited and offered work. */
  canOffer: boolean;
  currency: string;
  references: { id: string; title: string | null; early_access: boolean }[];
  data: Data;
};

function ExternalLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <a href={href} target="_blank" rel="noopener noreferrer" className="break-all underline">
      {children}
    </a>
  );
}

export function AdminAccessPanels({
  projectId,
  locked,
  canOffer,
  currency,
  references,
  data,
}: Props) {
  return (
    <>
      <AssetsCard projectId={projectId} locked={locked} data={data} />
      <EarlyAccessCard projectId={projectId} locked={locked} references={references} data={data} />
      <EditorsCard
        projectId={projectId}
        canOffer={canOffer}
        locked={locked}
        currency={currency}
        data={data}
      />
      <SharesCard projectId={projectId} locked={locked} data={data} />
      <NotesCard projectId={projectId} data={data} />
    </>
  );
}

function AssetsCard({ projectId, locked, data }: Pick<Props, "projectId" | "locked" | "data">) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Assets</CardTitle>
        <CardDescription>
          Links to footage, music, graphics and brand files. Editors see these only after they are
          confirmed, unless you mark one for the opportunity summary below. Saving assets never
          creates a brief version.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <AssetsForm
          key={data.assets.map((a) => a.id).join(":")}
          projectId={projectId}
          locked={locked}
          initial={data.assets.map((a) => ({
            id: a.id,
            label: a.label,
            url: a.url,
            provider: a.provider,
            kind: a.kind ?? "",
            notes: a.notes ?? "",
          }))}
        />
        {locked ? (
          <p className="text-muted-foreground pt-3 text-sm">
            This project can no longer be edited.
          </p>
        ) : null}
      </CardContent>
    </Card>
  );
}

function EarlyAccessCard({
  projectId,
  locked,
  references,
  data,
}: Pick<Props, "projectId" | "locked" | "references" | "data">) {
  const none = references.length === 0 && data.assets.length === 0;
  return (
    <Card>
      <CardHeader>
        <CardTitle>Shown before confirmation</CardTitle>
        <CardDescription>
          Invited editors see the title, summary, deadline and deliverables, plus any reference or
          asset marked here. Keep client names out of the title and summary. Everything else stays
          hidden until you confirm an editor. Changing this never creates a brief version.
        </CardDescription>
      </CardHeader>
      <CardContent className="grid gap-4">
        <p className="text-muted-foreground text-xs">{EARLY_ACCESS_HINT}</p>
        {none ? (
          <EmptyState title="Nothing to show yet">
            Add references to the brief or assets above first.
          </EmptyState>
        ) : null}
        {references.map((r) => (
          <div
            key={r.id}
            className="flex flex-wrap items-center justify-between gap-3 border-t pt-3 first:border-t-0 first:pt-0"
          >
            <div className="grid gap-1 text-sm">
              <span className="font-medium">{r.title ?? "Untitled reference"}</span>
              <span className="text-muted-foreground flex items-center gap-2">
                Reference
                <StatusPill tone={r.early_access ? "info" : "neutral"}>
                  {r.early_access ? "In summary" : "Hidden"}
                </StatusPill>
              </span>
            </div>
            {locked ? null : (
              <EarlyAccessToggle
                projectId={projectId}
                target="reference"
                targetId={r.id}
                value={r.early_access}
                name={`"${r.title ?? "reference"}"`}
              />
            )}
          </div>
        ))}
        {data.assets.map((a) => (
          <div
            key={a.id}
            className="flex flex-wrap items-center justify-between gap-3 border-t pt-3 first:border-t-0 first:pt-0"
          >
            <div className="grid gap-1 text-sm">
              <span className="font-medium">{a.label}</span>
              <span className="text-muted-foreground flex items-center gap-2">
                Asset
                <StatusPill tone={a.early_access ? "info" : "neutral"}>
                  {a.early_access ? "In summary" : "Hidden"}
                </StatusPill>
              </span>
            </div>
            {locked ? null : (
              <EarlyAccessToggle
                projectId={projectId}
                target="asset"
                targetId={a.id}
                value={a.early_access}
                name={`"${a.label}"`}
              />
            )}
          </div>
        ))}
      </CardContent>
    </Card>
  );
}

function EditorsCard({
  projectId,
  canOffer,
  locked,
  currency,
  data,
}: Pick<Props, "projectId" | "canOffer" | "locked" | "currency" | "data">) {
  const editorIds = Array.from(
    new Set([...data.access.map((a) => a.editorId), ...data.assignments.map((a) => a.editorId)]),
  );
  const entries = editorIds.map((id) => {
    const assignments = data.assignments.filter((a) => a.editorId === id);
    const live = data.access.find((a) => a.editorId === id && a.live);
    const label = editorLabel({ hasLiveAccess: Boolean(live), assignments });
    return { id, assignments, live, label };
  });
  const summary = summariseEditorLabels(entries.map((e) => e.label));
  const invitable = data.editorOptions.filter(
    (o) =>
      !entries.some(
        (e) => e.id === o.id && (e.live || e.assignments.some((a) => isLiveAssignment(a.status))),
      ),
  );

  return (
    <Card>
      <CardHeader>
        <CardTitle>Editors</CardTitle>
        <CardDescription>
          {summary ? `${summary}. ` : ""}
          Invite active editors, agree the pay, then confirm one editor. No editing starts until the
          pay is agreed and you have confirmed.
        </CardDescription>
      </CardHeader>
      <CardContent className="grid gap-6">
        {!canOffer ? (
          <p className="text-muted-foreground text-sm">
            {locked
              ? "This project is closed, so offers and invitations are unavailable."
              : data.assignments.some((a) => a.status === "confirmed")
                ? "An editor is confirmed for this project. Reassign them to reopen it for offers."
                : "Editors can be invited and offered work once the project is open."}
          </p>
        ) : null}

        {entries.length === 0 ? (
          <EmptyState title="No editors invited yet">
            {canOffer ? "Invite editors below to start making offers." : "Open the project first."}
          </EmptyState>
        ) : (
          <ul className="grid gap-4">
            {entries.map((e) => {
              const person = data.editorOptions.find((o) => o.id === e.id);
              const name = person?.name ?? data.nameOf(e.id);
              const current = e.assignments.find((a) => isLiveAssignment(a.status));
              const warning = editorAccessWarning(
                data.accessStatusOf(e.id),
                current?.status ?? null,
              );
              const history = e.assignments.flatMap((a) =>
                data.negotiations.filter((n) => n.assignmentId === a.id),
              );
              return (
                <li key={e.id} className="grid gap-3 rounded-lg border p-3">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div className="grid text-sm">
                      <span className="font-medium">{name}</span>
                      {e.live ? (
                        <span className="text-muted-foreground">
                          {ACCESS_REASON_LABEL[e.live.reason as AccessReason]}
                        </span>
                      ) : null}
                    </div>
                    <span className="flex flex-wrap items-center gap-2">
                      {warning ? <StatusPill tone="warning">{warning}</StatusPill> : null}
                      <StatusPill tone={e.label.tone}>{e.label.label}</StatusPill>
                    </span>
                  </div>
                  {warning ? (
                    <p className="text-muted-foreground text-sm">
                      This editor&apos;s account is no longer active, but the assignment stays open
                      until you withdraw, reassign or revoke it.
                    </p>
                  ) : null}

                  {current ? (
                    <p className="text-sm">
                      {current.status === "offered" ? "Offer: " : null}
                      {current.status === "counteroffer_pending" ? "Their counteroffer: " : null}
                      {current.status === "accepted" || current.status === "confirmed"
                        ? "Agreed pay: "
                        : null}
                      <strong className="tabular-nums">
                        {current.agreedAmount !== null
                          ? formatMoney(current.agreedAmount, current.agreedCurrency)
                          : formatMoney(current.proposedAmount, current.currency)}
                      </strong>
                    </p>
                  ) : null}

                  <EditorActions
                    projectId={projectId}
                    editorId={e.id}
                    canOffer={canOffer}
                    hasLiveAccess={Boolean(e.live)}
                    current={current ?? null}
                    currency={currency}
                  />

                  <details>
                    <summary className="cursor-pointer text-sm font-medium">
                      Offers and replies
                    </summary>
                    <div className="pt-3">
                      <NegotiationHistory rows={history} viewer="admin" editorName={name} />
                    </div>
                  </details>
                </li>
              );
            })}
          </ul>
        )}

        {canOffer ? (
          <div className="grid gap-3 border-t pt-4">
            <h3 className="text-sm font-medium">Invite editors</h3>
            <InviteEditorsForm projectId={projectId} options={invitable} />
          </div>
        ) : null}
      </CardContent>
    </Card>
  );
}

function EditorActions({
  projectId,
  editorId,
  canOffer,
  hasLiveAccess,
  current,
  currency,
}: {
  projectId: string;
  editorId: string;
  canOffer: boolean;
  hasLiveAccess: boolean;
  current: Data["assignments"][number] | null;
  currency: string;
}) {
  if (current?.status === "confirmed") {
    return <ReassignForm projectId={projectId} assignmentId={current.id} />;
  }
  return (
    <div className="grid gap-4">
      {!current && canOffer ? (
        <MakeOfferForm
          projectId={projectId}
          editorId={editorId}
          defaultCurrency={currency}
          label="Send offer"
        />
      ) : null}
      {current?.status === "counteroffer_pending" ? (
        <RespondForms
          role="admin"
          projectId={projectId}
          assignmentId={current.id}
          currency={current.currency}
          acceptLabel="Accept counteroffer"
        />
      ) : null}
      {current?.status === "accepted" ? (
        <ConfirmAssignmentForm projectId={projectId} assignmentId={current.id} />
      ) : null}
      {current ? <WithdrawOfferForm projectId={projectId} assignmentId={current.id} /> : null}
      {hasLiveAccess || current ? (
        <RevokeAccessForm projectId={projectId} editorId={editorId} />
      ) : null}
    </div>
  );
}

function SharesCard({ projectId, locked, data }: Pick<Props, "projectId" | "locked" | "data">) {
  const live = data.grants.filter((g) => g.revokedAt === null);
  const past = data.grants.filter((g) => g.revokedAt !== null);
  return (
    <Card>
      <CardHeader>
        <CardTitle>Folder shares</CardTitle>
        <CardDescription>
          Folders are shared by hand in Google Drive or Dropbox. Record each share here so it can be
          taken back when the work is over. This does not share anything by itself.
        </CardDescription>
      </CardHeader>
      <CardContent className="grid gap-6">
        {live.length === 0 ? (
          <EmptyState title="No live shares">
            Record a share after you give an editor a folder.
          </EmptyState>
        ) : (
          <ul className="grid gap-4">
            {live.map((g) => (
              <li key={g.id} className="grid gap-3 rounded-lg border p-3 text-sm">
                <div className="flex flex-wrap justify-between gap-2">
                  <span className="font-medium">{g.editorName}</span>
                  <span className="text-muted-foreground tabular-nums">
                    {formatDateTime(g.sharedAt)}
                  </span>
                </div>
                <p>
                  {ASSET_PROVIDER_LABEL[g.provider as AssetProvider]} · shared with{" "}
                  <span className="break-all">{g.email}</span>
                </p>
                {g.folderUrl ? (
                  <p>
                    <ExternalLink href={g.folderUrl}>Open folder</ExternalLink>
                  </p>
                ) : null}
                <RevokeGrantForm grantId={g.id} projectId={projectId} />
              </li>
            ))}
          </ul>
        )}
        {past.length > 0 ? (
          <details>
            <summary className="cursor-pointer text-sm font-medium">
              Removed shares ({past.length})
            </summary>
            <ul className="grid gap-2 pt-3 text-sm">
              {past.map((g) => (
                <li key={g.id} className="text-muted-foreground">
                  {g.editorName}, <span className="break-all">{g.email}</span>, removed{" "}
                  {formatDateTime(g.revokedAt)}
                  {g.revokeReason ? `: ${g.revokeReason}` : ""}
                </li>
              ))}
            </ul>
          </details>
        ) : null}
        <div className="grid gap-3 border-t pt-4">
          <h3 className="text-sm font-medium">Record a share</h3>
          <RecordGrantForm projectId={projectId} options={data.editorOptions} locked={locked} />
        </div>
      </CardContent>
    </Card>
  );
}

function NotesCard({ projectId, data }: Pick<Props, "projectId" | "data">) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Notes</CardTitle>
        <CardDescription>
          A log of calls, messages and decisions about this project. Only admins can see it.
        </CardDescription>
      </CardHeader>
      <CardContent className="grid gap-6">
        <AddNoteForm projectId={projectId} />
        {data.notes.length === 0 ? (
          <EmptyState title="No notes yet" />
        ) : (
          <ol className="grid gap-3 text-sm">
            {data.notes.map((n) => (
              <li key={n.id} className="border-t pt-3 first:border-t-0 first:pt-0">
                <div className="flex flex-wrap justify-between gap-2">
                  <span className="font-medium">{n.author}</span>
                  <span className="text-muted-foreground tabular-nums">
                    {formatDateTime(n.createdAt)}
                  </span>
                </div>
                <p className="whitespace-pre-line">{n.note}</p>
              </li>
            ))}
          </ol>
        )}
      </CardContent>
    </Card>
  );
}
