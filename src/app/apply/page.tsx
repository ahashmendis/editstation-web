import type { Metadata } from "next";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { SignOutButton } from "@/components/sign-out-button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  RequestResponseForm,
  WithdrawButton,
} from "@/features/applications/components/applicant-actions";
import {
  ApplicationForm,
  type ApplicationFormValues,
} from "@/features/applications/components/application-form";
import { SafeLink, SnapshotView } from "@/features/applications/components/snapshot-view";
import { formatDateTime, StatusBadge } from "@/features/applications/components/status-badge";
import { OPEN_STATUSES } from "@/features/applications/constants";
import { getApplicantView } from "@/features/applications/queries";
import { requireApplicant } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Your application · EDITSTATION" };

// Own Suspense boundary: per-request data must not block navigation into this page.
export default function ApplyPage() {
  return (
    <Suspense fallback={<Loading />}>
      <ApplyContent />
    </Suspense>
  );
}

function Notice({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>{children}</CardDescription>
      </CardHeader>
    </Card>
  );
}

async function ApplyContent() {
  const access = await requireApplicant();
  const shell = (children: React.ReactNode) => (
    <AreaShell
      title="Your editor application"
      subtitle={access.email ?? undefined}
      actions={<SignOutButton />}
    >
      {children}
    </AreaShell>
  );

  if (access.editorAccessStatus === "suspended") {
    return shell(
      <Notice title="Editor access suspended">
        Your editor access is currently suspended. Please contact Lenscape Studios if you have
        questions.
      </Notice>,
    );
  }
  if (access.editorAccessStatus === "revoked") {
    return shell(
      <Notice title="Editor access ended">
        Your editor access has been ended. Please contact Lenscape Studios if you believe this is a
        mistake.
      </Notice>,
    );
  }

  const view = await getApplicantView(access.userId);
  const { latest } = view;

  // No application yet, or a draft (e.g. reopened by an admin): show the form.
  if (!latest || latest.status === "draft") {
    const initial: ApplicationFormValues = {
      fullName: view.profile.full_name ?? "",
      phone: view.profile.phone ?? "",
      region: view.editor.region ?? "",
      experienceYears: view.editor.experience_years?.toString() ?? "",
      experienceSummary: view.editor.experience_summary ?? "",
      availability: view.editor.availability ?? "",
      typicalTurnaround: view.editor.typical_turnaround ?? "",
      hardware: view.editor.hardware ?? "",
      softwareOther: view.editor.software_other ?? "",
      specialisations: view.selected.filter((s) => s.kind === "specialisation").map((s) => s.code),
      software: view.selected.filter((s) => s.kind === "software").map((s) => s.code),
      links: view.links.map((l) => ({ url: l.url, label: l.label ?? "" })),
    };
    return shell(
      <div className="grid gap-6">
        {latest?.status === "draft" && latest.attempt > 1 ? (
          <Notice title="Your application has been reopened">
            Review your details below and submit again when you&apos;re ready.
          </Notice>
        ) : (
          <Notice title="Apply to join the editor network">
            Tell us about your experience and share your work. Our team reviews every application;
            we may ask for more information or a short practical test.
          </Notice>
        )}
        <Card>
          <CardContent className="pt-6">
            <ApplicationForm initial={initial} options={view.options} />
          </CardContent>
        </Card>
      </div>,
    );
  }

  const openRequests = view.requests.filter((r) => !r.responded_at);
  const isOpen = OPEN_STATUSES.includes(latest.status);

  return shell(
    <div className="grid gap-6">
      <Card>
        <CardHeader>
          <div className="flex flex-wrap items-center gap-3">
            <CardTitle>Application status</CardTitle>
            <StatusBadge status={latest.status} />
          </div>
          <CardDescription>
            {latest.status === "rejected"
              ? "Thank you for applying. We're not able to offer a place in the network at this time. If your circumstances change, contact Lenscape Studios and we can reopen your application."
              : latest.status === "withdrawn"
                ? "You withdrew your application. If you'd like to apply again, contact Lenscape Studios and we can reopen it."
                : openRequests.length
                  ? "We need something from you before we can continue the review."
                  : "Thanks for applying. Our team is reviewing your application."}
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-3 text-sm">
          <p className="text-muted-foreground">
            Submitted {formatDateTime(latest.submitted_at)}
            {latest.attempt > 1 ? ` · attempt ${latest.attempt}` : ""}
          </p>
          {latest.decision_message ? (
            <p className="whitespace-pre-wrap">{latest.decision_message}</p>
          ) : null}
          {isOpen ? <WithdrawButton /> : null}
        </CardContent>
      </Card>

      {view.requests.map((request) => (
        <Card key={request.id}>
          <CardHeader>
            <CardTitle>
              {request.kind === "test" ? "Practical test requested" : "More information requested"}
            </CardTitle>
            <CardDescription>{formatDateTime(request.requested_at)}</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-4 text-sm">
            <p className="whitespace-pre-wrap">{request.message}</p>
            {request.responded_at ? (
              <div className="grid gap-1 border-t pt-3">
                <p className="text-muted-foreground">
                  You responded {formatDateTime(request.responded_at)}
                </p>
                {request.response ? (
                  <p className="whitespace-pre-wrap">{request.response}</p>
                ) : null}
                {request.response_link ? (
                  <SafeLink url={request.response_link} label={null} />
                ) : null}
              </div>
            ) : (
              <RequestResponseForm requestId={request.id} isTest={request.kind === "test"} />
            )}
          </CardContent>
        </Card>
      ))}

      <Card>
        <CardHeader>
          <CardTitle>What you submitted</CardTitle>
        </CardHeader>
        <CardContent>
          <SnapshotView snapshot={latest.submitted_snapshot} />
        </CardContent>
      </Card>
    </div>,
  );
}
