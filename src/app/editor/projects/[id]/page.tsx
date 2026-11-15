import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { z } from "zod";

import { AreaShell, Loading } from "@/components/auth-shell";
import { EmptyState } from "@/components/empty-state";
import { SignOutButton } from "@/components/sign-out-button";
import { StatusPill } from "@/components/status-pill";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { AssignmentPill } from "@/features/access/components/assignment-pill";
import {
  ConfirmAssetAccessForm,
  ReportAssetForm,
  RespondForms,
} from "@/features/access/components/forms";
import { NegotiationHistory } from "@/features/access/components/negotiation-history";
import {
  ASSET_ACCESS_STATUS_LABEL,
  ASSET_ACCESS_STATUS_TONE,
  ASSET_PROVIDER_LABEL,
  formatMoney,
  type AssetAccessStatus,
  type AssetProvider,
} from "@/features/access/constants";
import { getEditorProject } from "@/features/access/queries";
import { EditorAdjustmentOffers } from "@/features/adjustments/components/panels";
import { getRevisionGates, listMyAdjustments } from "@/features/adjustments/queries";
import { EditorConfirmationPanel } from "@/features/confirmation/components/editor-panel";
import { getConfirmationData } from "@/features/confirmation/queries";
import { EditorTermsSummary } from "@/features/projects/components/editor-terms";
import { BRIEF_TYPE_LABEL, type BriefType } from "@/features/projects/constants";
import { getEditorTerms } from "@/features/projects/queries";
import { EditorSubmissionsPanel } from "@/features/submissions/components/panels";
import { getSubmissionData } from "@/features/submissions/queries";
import { requireActiveEditor } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Project · Editor · EDITSTATION" };

export default function EditorProjectPage({ params }: PageProps<"/editor/projects/[id]">) {
  return (
    <Suspense fallback={<Loading />}>
      <EditorProjectContent params={params} />
    </Suspense>
  );
}

function seconds(value: number | null): string {
  if (value === null) return "";
  const h = Math.floor(value / 3600);
  const m = Math.floor((value % 3600) / 60);
  const s = value % 60;
  const ss = String(s).padStart(2, "0");
  return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${ss}` : `${m}:${ss}`;
}

function Link2({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <a href={href} target="_blank" rel="noopener noreferrer" className="break-all underline">
      {children}
    </a>
  );
}

function BriefField({ label, value }: { label: string; value: string | null }) {
  if (!value) return null;
  return (
    <div className="grid gap-1">
      <h3 className="text-sm font-medium">{label}</h3>
      <p className="text-sm whitespace-pre-line">{value}</p>
    </div>
  );
}

async function EditorProjectContent({
  params,
}: {
  params: PageProps<"/editor/projects/[id]">["params"];
}) {
  await requireActiveEditor();
  const { id } = await params;
  if (!z.uuid().safeParse(id).success) notFound();
  const detail = await getEditorProject(id);
  // RLS shows nothing when the editor has no access: same answer as a project that does not exist.
  if (!detail) notFound();

  const { project: p, current, assignments, negotiations, brief } = detail;
  const working = assignments.find((a) => a.status === "confirmed" || a.status === "in_progress");
  const confirmed = Boolean(working);
  const [[confirmations, submissionData], terms] = await Promise.all([
    working
      ? Promise.all([getConfirmationData([working.id]), getSubmissionData(detail.project.id)])
      : Promise.resolve([null, null] as const),
    getEditorTerms(p.id),
  ]);
  const confirmation = working ? (confirmations?.get(working.id) ?? null) : null;
  // Offers show whenever the editor can see the project (also cancellation offers on an ended
  // assignment); gates only matter while working.
  const [offers, gates] = await Promise.all([
    listMyAdjustments(p.id),
    working
      ? getRevisionGates(
          (submissionData?.revisions ?? [])
            .filter((r) => r.assignmentId === working.id && r.status === "requested")
            .map((r) => r.id),
        )
      : Promise.resolve({}),
  ]);
  const briefType = p.brief_type as BriefType;
  const live =
    current &&
    ["offered", "counteroffer_pending", "accepted", "confirmed", "in_progress"].includes(
      current.status,
    );

  return (
    <AreaShell
      title={p.title}
      subtitle={[BRIEF_TYPE_LABEL[briefType], detail.serviceLabel].filter(Boolean).join(" · ")}
      actions={<SignOutButton />}
    >
      <Link href="/editor" className="text-muted-foreground text-sm underline">
        ← Dashboard
      </Link>

      <Card>
        <CardHeader>
          <div className="flex flex-wrap items-center gap-3">
            <CardTitle>{confirmed ? "Your assignment" : "Your offer"}</CardTitle>
            {current ? <AssignmentPill status={current.status} viewer="editor" /> : null}
            {p.status === "on_hold" ? (
              <StatusPill tone="warning">Project on hold</StatusPill>
            ) : null}
          </div>
          <CardDescription>
            {confirmed
              ? "The studio has confirmed you for this project."
              : "Pay is agreed before any editing starts. Nothing is final until the studio confirms you."}
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-5">
          {current && live ? (
            <p className="text-sm">
              {current.status === "offered" ? "Offer: " : null}
              {current.status === "counteroffer_pending" ? "Your counteroffer: " : null}
              {current.status === "accepted" ||
              current.status === "confirmed" ||
              current.status === "in_progress"
                ? "Agreed pay: "
                : null}
              <strong className="tabular-nums">
                {current.agreedAmount !== null
                  ? formatMoney(current.agreedAmount, current.agreedCurrency)
                  : formatMoney(current.proposedAmount, current.currency)}
              </strong>
            </p>
          ) : null}

          {!current ? (
            <EmptyState title="No offer yet">
              {p.proposed_amount !== null
                ? `The proposed pay is ${formatMoney(p.proposed_amount, p.proposed_currency)}, but it is not agreed. `
                : ""}
              The studio will send you an offer if they want to work with you on this.
            </EmptyState>
          ) : null}

          {current?.status === "offered" && p.status !== "open" ? (
            <p className="text-muted-foreground text-sm">
              {p.status === "on_hold"
                ? "Replies are paused while the project is on hold."
                : "Replies are paused while the project is not open."}
            </p>
          ) : null}
          {current?.status === "offered" && p.status === "open" ? (
            <RespondForms
              role="editor"
              projectId={p.id}
              assignmentId={current.id}
              currency={current.currency}
              acceptLabel="Accept this offer"
              acceptAmount={formatMoney(current.proposedAmount, current.currency)}
            />
          ) : null}
          {current?.status === "counteroffer_pending" ? (
            <p className="text-muted-foreground text-sm">
              You proposed a different amount. The studio will reply here.
            </p>
          ) : null}
          {current?.status === "accepted" ? (
            <p className="text-muted-foreground text-sm">
              You accepted. The studio will confirm one editor for the project, and you will see the
              full brief here if it is you.
            </p>
          ) : null}
          {current && !live ? (
            <p className="text-muted-foreground text-sm">
              This offer is closed. You will see a new offer here if the studio sends one.
            </p>
          ) : null}

          {negotiations.length > 0 ? (
            <details>
              <summary className="cursor-pointer text-sm font-medium">Offers and replies</summary>
              <div className="pt-3">
                <NegotiationHistory rows={negotiations} viewer="editor" />
              </div>
            </details>
          ) : null}
        </CardContent>
      </Card>

      <EditorTermsSummary terms={terms} />

      {working && confirmation ? (
        <EditorConfirmationPanel
          projectId={p.id}
          assignmentId={working.id}
          assignmentStatus={working.status as "confirmed" | "in_progress"}
          paused={p.status === "on_hold"}
          deadline={p.deadline}
          deliverables={detail.deliverables.map((d) => ({ id: d.id, name: d.name }))}
          agreedAmount={working.agreedAmount}
          agreedCurrency={working.agreedCurrency}
          data={confirmation}
        />
      ) : null}

      <EditorAdjustmentOffers offers={offers} />

      {working?.status === "in_progress" && submissionData ? (
        <EditorSubmissionsPanel
          projectId={p.id}
          assignmentId={working.id}
          projectStatus={p.status}
          data={submissionData}
          gates={gates}
        />
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle>{confirmed ? "Project" : "Summary"}</CardTitle>
          {!confirmed ? (
            <CardDescription>
              This is the short version. You get the full brief if you are confirmed.
            </CardDescription>
          ) : null}
        </CardHeader>
        <CardContent className="grid gap-4">
          <dl className="grid gap-3 text-sm sm:grid-cols-2">
            <div>
              <dt className="text-muted-foreground">Brief type</dt>
              <dd>{BRIEF_TYPE_LABEL[briefType]}</dd>
            </div>
            <div>
              <dt className="text-muted-foreground">Type of service</dt>
              <dd>{detail.serviceLabel ?? "Not set"}</dd>
            </div>
            <div>
              <dt className="text-muted-foreground">Deadline</dt>
              <dd>{p.deadline ?? "Not set"}</dd>
            </div>
            {confirmed ? (
              <div>
                <dt className="text-muted-foreground">Included revision rounds</dt>
                <dd>{p.revision_allowance}</dd>
              </div>
            ) : null}
          </dl>
          <BriefField label="Summary" value={p.summary} />
          <div className="grid gap-2">
            <h3 className="text-sm font-medium">Deliverables</h3>
            {detail.deliverables.length === 0 ? (
              <p className="text-muted-foreground text-sm">No deliverables listed.</p>
            ) : (
              <ul className="grid gap-2 text-sm">
                {detail.deliverables.map((d) => (
                  <li key={d.id} className="rounded-lg border p-3">
                    <p className="font-medium">{d.name}</p>
                    <p className="text-muted-foreground">
                      {[
                        d.format,
                        d.resolution,
                        d.aspect_ratio,
                        d.duration_seconds === null ? null : `${seconds(d.duration_seconds)} long`,
                      ]
                        .filter(Boolean)
                        .join(" · ") || "No specification given."}
                    </p>
                    {d.notes ? <p className="whitespace-pre-line">{d.notes}</p> : null}
                  </li>
                ))}
              </ul>
            )}
          </div>
        </CardContent>
      </Card>

      {confirmed ? (
        <Card>
          <CardHeader>
            <CardTitle>Brief</CardTitle>
            <CardDescription>Version {p.current_brief_version}.</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-4">
            {brief ? (
              <>
                <BriefField label="Instructions" value={brief.instructions} />
                <BriefField label="Desired outcome" value={brief.desired_outcome} />
                <BriefField label="Audience" value={brief.audience} />
                <BriefField label="Core message" value={brief.core_message} />
                <BriefField label="Brand constraints" value={brief.brand_constraints} />
                <BriefField label="Must include" value={brief.mandatory_content} />
                <BriefField label="Must avoid" value={brief.prohibited_content} />
              </>
            ) : (
              <EmptyState title="The brief is not available">
                Ask the studio if this looks wrong.
              </EmptyState>
            )}
          </CardContent>
        </Card>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle>References</CardTitle>
          <CardDescription>
            References show the style or pacing the client likes. A link is not permission to copy
            someone else&apos;s footage, music or other material. Use only what the studio supplies
            or what you have the right to use.
            {!confirmed ? " You will see every reference if you are confirmed." : ""}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {detail.references.length === 0 ? (
            <EmptyState title="No references to show" />
          ) : (
            <ul className="grid gap-3">
              {detail.references.map((r) => (
                <li key={r.id} className="grid gap-1 rounded-lg border p-3 text-sm">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <span className="font-medium">{r.title ?? "Reference"}</span>
                    <StatusPill tone={r.priority === "essential" ? "info" : "neutral"}>
                      {r.priority === "essential" ? "Essential" : "Optional"}
                    </StatusPill>
                  </div>
                  <Link2 href={r.url}>{r.url}</Link2>
                  {r.start_seconds !== null ? (
                    <p className="text-muted-foreground">
                      From {seconds(r.start_seconds)}
                      {r.end_seconds !== null ? ` to ${seconds(r.end_seconds)}` : ""}
                    </p>
                  ) : null}
                  {r.category ? <p className="text-muted-foreground">{r.category}</p> : null}
                  {r.observation_notes ? (
                    <p className="whitespace-pre-line">{r.observation_notes}</p>
                  ) : null}
                  {confirmed && r.access_notes ? (
                    <p className="text-muted-foreground whitespace-pre-line">
                      Access: {r.access_notes}
                    </p>
                  ) : null}
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Assets</CardTitle>
          <CardDescription>
            Material supplied for the project. Links are shared by the client with your account.
            {confirmed
              ? " If one does not open, report it so the studio can sort out access."
              : " You will see all assets if you are confirmed."}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {detail.assets.length === 0 ? (
            <EmptyState title="No assets to show" />
          ) : (
            <ul className="grid gap-3">
              {detail.assets.map((a) => {
                const status = a.access_status as AssetAccessStatus;
                const reported = detail.openReportAssetIds.includes(a.id);
                // Stale when older than this editor's own confirmation (an earlier assignment).
                const saidOpen =
                  a.editor_confirmed_at !== null &&
                  working?.confirmedAt != null &&
                  a.editor_confirmed_at >= working.confirmedAt;
                return (
                  <li key={a.id} className="grid gap-2 rounded-lg border p-3 text-sm">
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <span className="font-medium">{a.label}</span>
                      <span className="text-muted-foreground">
                        {[a.kind, ASSET_PROVIDER_LABEL[a.provider as AssetProvider]]
                          .filter(Boolean)
                          .join(" · ")}
                      </span>
                    </div>
                    <span className="flex flex-wrap items-center gap-2">
                      <StatusPill tone={ASSET_ACCESS_STATUS_TONE[status]}>
                        {ASSET_ACCESS_STATUS_LABEL[status]}
                      </StatusPill>
                    </span>
                    <Link2 href={a.url}>{a.url}</Link2>
                    {a.description ? <p className="whitespace-pre-line">{a.description}</p> : null}
                    {a.access_instructions ? (
                      <p className="whitespace-pre-line">
                        <span className="font-medium">How to get access: </span>
                        {a.access_instructions}
                      </p>
                    ) : null}
                    {a.notes ? <p className="whitespace-pre-line">{a.notes}</p> : null}
                    {confirmed ? (
                      reported ? (
                        <p className="text-muted-foreground">
                          You reported this as inaccessible. The studio is sorting out access.
                        </p>
                      ) : (
                        <div className="grid gap-3">
                          {saidOpen ? (
                            <p className="text-muted-foreground">
                              You told the studio you can open this.
                            </p>
                          ) : status !== "verified" ? (
                            <ConfirmAssetAccessForm
                              projectId={p.id}
                              assetId={a.id}
                              label={a.label}
                            />
                          ) : null}
                          <ReportAssetForm projectId={p.id} assetId={a.id} label={a.label} />
                        </div>
                      )
                    ) : null}
                  </li>
                );
              })}
            </ul>
          )}
        </CardContent>
      </Card>
    </AreaShell>
  );
}
