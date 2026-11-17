import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { z } from "zod";

import { AreaShell, Loading } from "@/components/auth-shell";
import { EmptyState } from "@/components/empty-state";
import { SignOutButton } from "@/components/sign-out-button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  AdminExtraPayPanel,
  CancellationSettlementPanel,
} from "@/features/adjustments/components/panels";
import { getAdminAdjustmentData, previewSettlement } from "@/features/adjustments/queries";
import { AdminActionForm } from "@/features/applications/components/admin-action-form";
import { formatDateTime } from "@/features/applications/components/status-badge";
import { AdminAccessPanels } from "@/features/access/components/admin-panels";
import { getProjectAccessData } from "@/features/access/queries";
import { ClientBillingPanel } from "@/features/billing/components/billing-panel";
import { ClientUpdatesCard } from "@/features/client-area/components/admin-panels";
import { getAdminClientUpdates } from "@/features/client-area/queries";
import { getClientBilling } from "@/features/billing/queries";
import { AdminConfirmationPanel } from "@/features/confirmation/components/admin-panel";
import { AdminOpportunitySection } from "@/features/opportunities/components/admin-section";
import { getConfirmationData } from "@/features/confirmation/queries";
import { archiveProjectAction, setProjectStatusAction } from "@/features/projects/admin-actions";
import {
  BriefEditorForm,
  EditDetailsForm,
  type DetailsDefaults,
} from "@/features/projects/components/project-forms";
import { ProjectStatusPill } from "@/features/projects/components/project-status-pill";
import { TermsCard } from "@/features/projects/components/terms-card";
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
  getProjectTerms,
} from "@/features/projects/queries";
import { AdminReviewPanel } from "@/features/submissions/components/panels";
import { getSubmissionData } from "@/features/submissions/queries";
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
  const [detail, options, access, submissionData, terms, billing, extras] = await Promise.all([
    getProjectDetail(id),
    getProjectFormOptions(),
    getProjectAccessData(id),
    getSubmissionData(id),
    getProjectTerms(id),
    getClientBilling(id),
    getAdminAdjustmentData(id),
  ]);
  if (!detail) notFound();
  const clientUpdates = await getAdminClientUpdates(id);
  const working = access.assignments.filter(
    (a) => a.status === "confirmed" || a.status === "in_progress",
  );
  const inProgress = working.find((a) => a.status === "in_progress") ?? null;
  // A settlement applies to an assigned or started project with a confirmed editor (spec §4.6).
  const settleable =
    !extras.settlement &&
    detail.project.archived_at === null &&
    working.length > 0 &&
    (["assigned", "in_progress", "in_review", "revision_requested"].includes(
      detail.project.status,
    ) ||
      (detail.project.status === "on_hold" && detail.project.status_before_hold === "assigned"));
  const settlementPreview = settleable
    ? await previewSettlement(id)
    : { preview: null, message: null };
  const confirmationData = await getConfirmationData(working.map((a) => a.id));
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

      <ClientUpdatesCard projectId={p.id} data={clientUpdates} archived={archived} />

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

      <TermsCard projectId={p.id} terms={terms} locked={locked} />

      <ClientBillingPanel
        projectId={p.id}
        milestones={billing.milestones}
        today={billing.today}
        timezone={billing.timezone}
        termsAgreed={terms.some((t) => t.status === "agreed")}
        hasClientPrice={
          internal?.client_price !== null &&
          internal?.client_price !== undefined &&
          internal.client_price > 0
        }
        workStarted={
          working.some((a) => a.status === "in_progress") ||
          ["in_progress", "in_review", "revision_requested", "approved", "completed"].includes(
            status,
          )
        }
        locked={archived}
        cancelled={status === "cancelled"}
      />

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

      <AdminOpportunitySection
        projectId={p.id}
        publishable={!archived && status === "open"}
        services={options.services.filter((s) => s.active)}
        project={{
          serviceTypeCode: p.service_type_code,
          deadline: p.deadline,
          proposedAmount: p.proposed_amount,
          currency: p.proposed_currency,
        }}
      />

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

      <AdminConfirmationPanel
        projectId={p.id}
        startable={!locked && status === "assigned"}
        entries={working.flatMap((a) => {
          const data = confirmationData.get(a.id);
          return data
            ? [
                {
                  assignmentId: a.id,
                  editorName: access.nameOf(a.editorId),
                  assignmentStatus: a.status as "confirmed" | "in_progress",
                  data,
                },
              ]
            : [];
        })}
      />

      {submissionData.submissions.length > 0 ||
      ["in_progress", "in_review", "revision_requested", "approved", "completed"].includes(
        status,
      ) ? (
        <AdminReviewPanel
          projectId={p.id}
          projectStatus={archived ? "archived" : status}
          revisionAllowance={p.revision_allowance}
          data={submissionData}
        />
      ) : null}

      <AdminExtraPayPanel
        projectId={p.id}
        assignmentId={inProgress?.id ?? null}
        currency={inProgress?.agreedCurrency ?? p.proposed_currency ?? "LKR"}
        clientCurrency={internal?.client_price_currency ?? "LKR"}
        revisions={submissionData.revisions}
        data={extras}
        today={billing.today}
        locked={locked}
      />

      <CancellationSettlementPanel
        projectId={p.id}
        settlement={extras.settlement}
        preview={settlementPreview.preview}
        previewMessage={settlementPreview.message}
        cancelledAssignmentId={extras.settlement?.assignmentId ?? null}
        cancellationOffers={extras.adjustments.filter((a) => a.kind === "cancellation")}
        archived={archived}
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
