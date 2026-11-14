import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { z } from "zod";

import { AreaShell, Loading } from "@/components/auth-shell";
import { EmptyState } from "@/components/empty-state";
import { SignOutButton } from "@/components/sign-out-button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { AdminActionForm } from "@/features/applications/components/admin-action-form";
import { formatDateTime } from "@/features/applications/components/status-badge";
import { AdminAccessPanels } from "@/features/access/components/admin-panels";
import { getProjectAccessData } from "@/features/access/queries";
import { archiveProjectAction, setProjectStatusAction } from "@/features/projects/admin-actions";
import {
  BriefEditorForm,
  EditDetailsForm,
  type DetailsDefaults,
} from "@/features/projects/components/project-forms";
import { ProjectStatusPill } from "@/features/projects/components/project-status-pill";
import {
  BRIEF_TYPE_LABEL,
  allowedStatusActions,
  type BriefType,
  type ProjectStatus,
  activityLabel,
} from "@/features/projects/constants";
import {
  getClientOption,
  getProjectDetail,
  getProjectFormOptions,
} from "@/features/projects/queries";
import { requireAdmin } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Project · Admin · EDITSTATION" };

export default function ProjectPage({ params }: PageProps<"/admin/projects/[id]">) {
  return (
    <Suspense fallback={<Loading />}>
      <ProjectContent params={params} />
    </Suspense>
  );
}

const str = (value: string | number | null | undefined) =>
  value === null || value === undefined ? "" : String(value);

async function ProjectContent({ params }: { params: PageProps<"/admin/projects/[id]">["params"] }) {
  await requireAdmin();
  const { id } = await params;
  if (!z.uuid().safeParse(id).success) notFound();
  const [detail, options, access] = await Promise.all([
    getProjectDetail(id),
    getProjectFormOptions(),
    getProjectAccessData(id),
  ]);
  if (!detail) notFound();
  const {
    project: p,
    internal,
    versions,
    currentBrief,
    deliverables,
    references,
    activity,
  } = detail;

  const status = p.status as ProjectStatus;
  const briefType = p.brief_type as BriefType;
  const archived = p.archived_at !== null;
  const locked = archived || status === "cancelled";
  const opened = p.first_opened_at !== null;
  const actions = locked
    ? []
    : allowedStatusActions(status, (p.status_before_hold as ProjectStatus | null) ?? null);

  const details: DetailsDefaults = {
    title: p.title,
    briefType,
    serviceTypeCode: p.service_type_code ?? "",
    summary: str(p.summary),
    deadline: str(p.deadline),
    requiresInterpretation:
      p.requires_interpretation === null ? "" : p.requires_interpretation ? "yes" : "no",
    proposedAmount: str(p.proposed_amount),
    proposedCurrency: str(p.proposed_currency) || "LKR",
    revisionAllowance: str(p.revision_allowance),
    clientId: str(internal?.client_id),
    clientPrice: str(internal?.client_price),
    clientPriceCurrency: str(internal?.client_price_currency) || "LKR",
    internalNotes: str(internal?.internal_notes),
  };

  // The client may be archived or merged and so missing from the option list; keep it selectable.
  const clients = [...options.clients];
  if (internal?.client_id && !clients.some((c) => c.id === internal.client_id)) {
    const current = await getClientOption(internal.client_id);
    if (current) clients.push(current);
  }

  return (
    <AreaShell
      title={p.title}
      subtitle={`${BRIEF_TYPE_LABEL[briefType]} · brief version ${p.current_brief_version}`}
      actions={<SignOutButton />}
    >
      <Link href="/admin/projects" className="text-muted-foreground text-sm underline">
        ← All projects
      </Link>

      <Card>
        <CardHeader>
          <div className="flex flex-wrap items-center gap-3">
            <CardTitle>Status</CardTitle>
            <ProjectStatusPill status={status} />
            {archived ? <span className="text-muted-foreground text-sm">Archived</span> : null}
          </div>
          <CardDescription>
            Editors only see this project after you invite them, and only the summary until you
            confirm one.
            {internal?.source_inquiry_id ? (
              <>
                {" "}
                Created from{" "}
                <Link href={`/admin/inquiries/${internal.source_inquiry_id}`} className="underline">
                  an inquiry
                </Link>
                .
              </>
            ) : null}
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4">
          {actions.length === 0 ? (
            <p className="text-muted-foreground text-sm">
              {locked
                ? "No status changes are available for this project."
                : "No status changes are available from this stage."}
            </p>
          ) : (
            <div className="grid gap-4 sm:grid-cols-2">
              {actions.map((a) => (
                <AdminActionForm
                  key={a.to}
                  action={setProjectStatusAction}
                  submitLabel={a.label}
                  variant={a.destructive ? "destructive" : "default"}
                  confirm={a.confirm}
                >
                  <input type="hidden" name="projectId" value={p.id} />
                  <input type="hidden" name="status" value={a.to} />
                </AdminActionForm>
              ))}
            </div>
          )}
          <AdminActionForm
            action={archiveProjectAction}
            submitLabel={archived ? "Restore project" : "Archive project"}
            variant="outline"
          >
            <input type="hidden" name="projectId" value={p.id} />
            <input type="hidden" name="archive" value={archived ? "false" : "true"} />
          </AdminActionForm>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Details</CardTitle>
          <CardDescription>Saving details never creates a new brief version.</CardDescription>
        </CardHeader>
        <CardContent>
          <EditDetailsForm
            projectId={p.id}
            services={options.services}
            clients={clients}
            details={details}
            locked={locked}
            briefTypeLocked={opened}
          />
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Brief</CardTitle>
          <CardDescription>
            Instructions, deliverables and references that editors will confirm.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <BriefEditorForm
            key={[
              p.current_brief_version,
              ...deliverables.map((d) => d.id),
              ...references.map((r) => r.id),
            ].join(":")}
            projectId={p.id}
            briefType={briefType}
            currentVersion={p.current_brief_version}
            opened={opened}
            locked={locked}
            brief={{
              instructions: str(currentBrief?.instructions),
              desiredOutcome: str(currentBrief?.desired_outcome),
              audience: str(currentBrief?.audience),
              coreMessage: str(currentBrief?.core_message),
              brandConstraints: str(currentBrief?.brand_constraints),
              mandatoryContent: str(currentBrief?.mandatory_content),
              prohibitedContent: str(currentBrief?.prohibited_content),
            }}
            deliverables={deliverables.map((d) => ({
              id: d.id,
              name: d.name,
              format: str(d.format),
              resolution: str(d.resolution),
              aspectRatio: str(d.aspect_ratio),
              durationSeconds: str(d.duration_seconds),
              notes: str(d.notes),
            }))}
            references={references.map((r) => ({
              id: r.id,
              title: r.title ?? "",
              url: r.url,
              startSeconds: str(r.start_seconds),
              endSeconds: str(r.end_seconds),
              observationNotes: str(r.observation_notes),
              priority: r.priority,
              category: str(r.category),
              accessNotes: str(r.access_notes),
            }))}
          />
        </CardContent>
      </Card>

      <AdminAccessPanels
        projectId={p.id}
        locked={locked}
        canOffer={!locked && opened && status === "open"}
        currency={p.proposed_currency}
        references={references.map((r) => ({
          id: r.id,
          title: r.title,
          early_access: r.early_access,
        }))}
        data={access}
      />

      <Card>
        <CardHeader>
          <CardTitle>Version history</CardTitle>
          <CardDescription>Earlier versions are kept exactly as they were.</CardDescription>
        </CardHeader>
        <CardContent>
          {versions.length === 0 ? (
            <EmptyState title="No versions yet" />
          ) : (
            <ol className="grid gap-3 text-sm">
              {versions.map((v) => (
                <li key={v.id} className="border-t pt-3 first:border-t-0 first:pt-0">
                  <div className="flex flex-wrap justify-between gap-2">
                    <span className="font-medium">
                      Version {v.version}
                      {v.version === p.current_brief_version ? " (current)" : ""}
                    </span>
                    <span className="text-muted-foreground tabular-nums">
                      {formatDateTime(v.created_at)}
                    </span>
                  </div>
                  <p className="text-muted-foreground">
                    {v.change_summary ?? "First version."}
                    {v.version > 1
                      ? v.requires_reacknowledgement
                        ? " Editors must confirm again."
                        : " No new confirmation needed."
                      : ""}
                  </p>
                </li>
              ))}
            </ol>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>History</CardTitle>
        </CardHeader>
        <CardContent>
          {activity.length === 0 ? (
            <EmptyState title="Nothing recorded yet" />
          ) : (
            <ul className="grid gap-1 text-sm">
              {activity.map((entry) => (
                <li key={entry.id} className="flex flex-wrap justify-between gap-2">
                  <span>{activityLabel(entry.action)}</span>
                  <span className="text-muted-foreground tabular-nums">
                    {formatDateTime(entry.created_at)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </AreaShell>
  );
}
