import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { z } from "zod";

import { AreaShell, Loading } from "@/components/auth-shell";
import { SignOutButton } from "@/components/sign-out-button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  addVettingNoteAction,
  approveAction,
  createRequestAction,
  recordAssessmentAction,
  rejectAction,
  reopenAction,
  setEditorAccessAction,
  startReviewAction,
} from "@/features/applications/admin-actions";
import { activityLabel } from "@/lib/activity-labels";
import { AdminActionForm } from "@/features/applications/components/admin-action-form";
import { SafeLink, SnapshotView } from "@/features/applications/components/snapshot-view";
import { formatDateTime, StatusBadge } from "@/features/applications/components/status-badge";
import { ASSESSMENT_RESULTS, LEVELS, OPEN_STATUSES } from "@/features/applications/constants";
import { getApplicationDetail } from "@/features/applications/queries";
import { requireAdmin } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Application · Admin · EDITSTATION" };

const selectClass = "border-input h-9 rounded-md border bg-transparent px-3 text-sm";

export default function ApplicationPage({ params }: PageProps<"/admin/applications/[id]">) {
  return (
    <Suspense fallback={<Loading />}>
      <ApplicationContent params={params} />
    </Suspense>
  );
}

function Hidden({ name, value }: { name: string; value: string }) {
  return <input type="hidden" name={name} value={value} />;
}

function TextBox({
  id,
  name,
  label,
  required,
}: {
  id: string;
  name: string;
  label: string;
  required?: boolean;
}) {
  return (
    <div className="grid gap-2">
      <Label htmlFor={id}>{label}</Label>
      <Textarea id={id} name={name} rows={3} required={required} />
    </div>
  );
}

async function ApplicationContent({
  params,
}: {
  params: PageProps<"/admin/applications/[id]">["params"];
}) {
  await requireAdmin();
  const { id } = await params;
  if (!z.uuid().safeParse(id).success) notFound();
  const detail = await getApplicationDetail(id);
  if (!detail) notFound();

  const { app, person, editor, requests, notes, attempts, activity, isLatestAttempt } = detail;
  const isOpen = OPEN_STATUSES.includes(app.status);
  const canDecide = app.status === "submitted" || app.status === "under_review";
  const openRequests = requests.filter((r) => !r.responded_at).length;

  return (
    <AreaShell
      title={person.full_name ?? person.email}
      subtitle={`${person.email}${person.phone ? ` · ${person.phone}` : ""}`}
      actions={<SignOutButton />}
    >
      <Link href="/admin/applications" className="text-muted-foreground text-sm underline">
        ← All applications
      </Link>

      <Card>
        <CardHeader>
          <div className="flex flex-wrap items-center gap-3">
            <CardTitle>Attempt {app.attempt}</CardTitle>
            <StatusBadge status={app.status} />
            <span className="text-muted-foreground text-sm">
              Editor access: <strong>{editor.access_status}</strong>
              {editor.level ? ` · level ${editor.level}` : ""}
            </span>
          </div>
          <CardDescription>
            Submitted {formatDateTime(app.submitted_at)} · terms {app.terms_version ?? "—"} ·
            privacy {app.privacy_version ?? "—"}
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4">
          {app.decision_message ? (
            <p className="text-sm">
              <span className="text-muted-foreground">Message to applicant: </span>
              {app.decision_message}
            </p>
          ) : null}
          {app.status === "submitted" ? (
            <AdminActionForm action={startReviewAction} submitLabel="Start review">
              <Hidden name="applicationId" value={app.id} />
            </AdminActionForm>
          ) : null}
          {openRequests > 0 ? (
            <p className="text-sm">
              Waiting for the applicant to answer {openRequests} request
              {openRequests > 1 ? "s" : ""}.
            </p>
          ) : null}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Submitted details</CardTitle>
          <CardDescription>
            As submitted; later profile edits don&apos;t change this.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <SnapshotView snapshot={app.submitted_snapshot} showContact />
        </CardContent>
      </Card>

      {requests.length ? (
        <Card>
          <CardHeader>
            <CardTitle>Requests to the applicant</CardTitle>
          </CardHeader>
          <CardContent className="grid gap-6 text-sm">
            {requests.map((request) => (
              <div
                key={request.id}
                className="grid gap-2 border-t pt-4 first:border-t-0 first:pt-0"
              >
                <p className="font-medium">
                  {request.kind === "test" ? "Practical test" : "Information request"} ·{" "}
                  {formatDateTime(request.requested_at)}
                </p>
                <p className="whitespace-pre-wrap">{request.message}</p>
                {request.responded_at ? (
                  <div className="bg-muted grid gap-1 rounded-md p-3">
                    <p className="text-muted-foreground">
                      Answered {formatDateTime(request.responded_at)}
                    </p>
                    {request.response ? (
                      <p className="whitespace-pre-wrap">{request.response}</p>
                    ) : null}
                    {request.response_link ? (
                      <SafeLink url={request.response_link} label={null} />
                    ) : null}
                  </div>
                ) : (
                  <p className="text-muted-foreground">Not answered yet.</p>
                )}
                {request.kind === "test" ? (
                  request.assessment_result ? (
                    <p>
                      Result: <strong>{request.assessment_result}</strong>
                      {request.assessment_notes ? ` — ${request.assessment_notes}` : ""}
                    </p>
                  ) : request.responded_at ? (
                    <AdminActionForm action={recordAssessmentAction} submitLabel="Record result">
                      <Hidden name="requestId" value={request.id} />
                      <div className="flex flex-wrap gap-2">
                        <select name="result" className={selectClass} defaultValue="passed">
                          {ASSESSMENT_RESULTS.map((r) => (
                            <option key={r.value} value={r.value}>
                              {r.label}
                            </option>
                          ))}
                        </select>
                      </div>
                      <TextBox id={`notes-${request.id}`} name="notes" label="Notes (internal)" />
                    </AdminActionForm>
                  ) : null
                ) : null}
              </div>
            ))}
          </CardContent>
        </Card>
      ) : null}

      {isOpen ? (
        <Card>
          <CardHeader>
            <CardTitle>Ask the applicant</CardTitle>
            <CardDescription>
              The applicant sees this message and can reply with text and a link.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <AdminActionForm action={createRequestAction} submitLabel="Send request">
              <Hidden name="applicationId" value={app.id} />
              <select name="kind" className={selectClass} defaultValue="info" aria-label="Type">
                <option value="info">More information</option>
                <option value="test">Practical test</option>
              </select>
              <TextBox
                id="request-message"
                name="message"
                label="Message to the applicant"
                required
              />
            </AdminActionForm>
          </CardContent>
        </Card>
      ) : null}

      {isOpen ? (
        <Card>
          <CardHeader>
            <CardTitle>Decision</CardTitle>
            <CardDescription>
              {canDecide
                ? "Approving activates editor access immediately."
                : "Approval is available once all requests have been answered."}
            </CardDescription>
          </CardHeader>
          <CardContent className="grid gap-6 md:grid-cols-2">
            {canDecide ? (
              <AdminActionForm
                action={approveAction}
                submitLabel="Approve and activate"
                confirm="Activate editor access?"
              >
                <Hidden name="applicationId" value={app.id} />
                <div className="grid gap-2">
                  <Label htmlFor="level">Initial level</Label>
                  <select id="level" name="level" className={selectClass} defaultValue="">
                    <option value="" disabled>
                      Choose…
                    </option>
                    {LEVELS.map((l) => (
                      <option key={l.value} value={l.value}>
                        {l.label}
                      </option>
                    ))}
                  </select>
                </div>
                <TextBox
                  id="approve-message"
                  name="message"
                  label="Message to the applicant (optional)"
                />
              </AdminActionForm>
            ) : (
              <div />
            )}
            <AdminActionForm
              action={rejectAction}
              submitLabel="Don't approve"
              variant="destructive"
              confirm="Close this application as not approved?"
            >
              <Hidden name="applicationId" value={app.id} />
              <TextBox
                id="reject-message"
                name="message"
                label="Message to the applicant (optional)"
              />
              <p className="text-muted-foreground text-xs">
                Put internal reasoning in a vetting note, not here.
              </p>
            </AdminActionForm>
          </CardContent>
        </Card>
      ) : null}

      {isLatestAttempt && (app.status === "rejected" || app.status === "withdrawn") ? (
        <Card>
          <CardHeader>
            <CardTitle>Reopen</CardTitle>
            <CardDescription>
              Lets this person submit a new application (decision M). The previous attempt is kept.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <AdminActionForm
              action={reopenAction}
              submitLabel="Reopen application"
              confirm="Allow a new submission?"
            >
              <Hidden name="editorId" value={app.editor_id} />
            </AdminActionForm>
          </CardContent>
        </Card>
      ) : null}

      {app.status === "approved" &&
      (editor.access_status === "active" || editor.access_status === "suspended") ? (
        <Card>
          <CardHeader>
            <CardTitle>Editor access</CardTitle>
            <CardDescription>
              Currently <strong>{editor.access_status}</strong>
              {editor.access_change_reason ? ` · ${editor.access_change_reason}` : ""}. Revoking is
              permanent.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <AdminActionForm
              action={setEditorAccessAction}
              submitLabel="Change access"
              variant="outline"
              confirm="Change this editor's access now?"
            >
              <Hidden name="editorId" value={app.editor_id} />
              <select name="status" className={selectClass} aria-label="New access status">
                {editor.access_status === "active" ? (
                  <option value="suspended">Suspend</option>
                ) : (
                  <option value="active">Reactivate</option>
                )}
                <option value="revoked">Revoke permanently</option>
              </select>
              <TextBox
                id="access-reason"
                name="reason"
                label="Reason (recorded in the audit log)"
                required
              />
            </AdminActionForm>
          </CardContent>
        </Card>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle>Vetting notes</CardTitle>
          <CardDescription>Internal. Never shown to the applicant.</CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4 text-sm">
          <AdminActionForm action={addVettingNoteAction} submitLabel="Add note" variant="outline">
            <Hidden name="applicationId" value={app.id} />
            <TextBox id="vetting-note" name="note" label="Note" required />
          </AdminActionForm>
          <ul className="grid gap-3">
            {notes.map((note) => (
              <li key={note.id} className="border-t pt-3">
                <p className="text-muted-foreground text-xs">{formatDateTime(note.created_at)}</p>
                <p className="whitespace-pre-wrap">{note.note}</p>
              </li>
            ))}
          </ul>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>History</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-4 text-sm">
          {attempts.length > 1 ? (
            <ul className="grid gap-1">
              {attempts.map((a) => (
                <li key={a.id} className="flex flex-wrap items-center gap-2">
                  <Link href={`/admin/applications/${a.id}`} className="underline">
                    Attempt {a.attempt}
                  </Link>
                  <StatusBadge status={a.status} />
                  <span className="text-muted-foreground">{formatDateTime(a.submitted_at)}</span>
                </li>
              ))}
            </ul>
          ) : null}
          <ul className="grid gap-1">
            {activity.map((entry) => (
              <li key={entry.id} className="flex flex-wrap justify-between gap-2">
                <span>{activityLabel(entry.action)}</span>
                <span className="text-muted-foreground tabular-nums">
                  {formatDateTime(entry.created_at)}
                </span>
              </li>
            ))}
          </ul>
        </CardContent>
      </Card>
    </AreaShell>
  );
}
