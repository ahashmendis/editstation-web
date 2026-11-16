import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { SignOutButton } from "@/components/sign-out-button";
import { EmptyState } from "@/components/empty-state";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { runTimedRules } from "@/features/billing/timed-rules";
import { countNewInquiries } from "@/features/inquiries/queries";
import { BarChart, MetricCard } from "@/features/metrics/components/metric-charts";
import {
  APPLICATION_LABEL,
  APPLICATION_ORDER,
  barsFor,
  formatAmount,
  formatHours,
  formatRate,
  INQUIRY_LABEL,
  INQUIRY_ORDER,
  PROJECT_LABEL,
  PROJECT_ORDER,
} from "@/features/metrics/constants";
import { getDashboardMetrics } from "@/features/metrics/queries";
import { activityLabel } from "@/lib/activity-labels";
import { requireAdmin, type EditorAccessStatus } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Admin · EDITSTATION" };

const STATUSES: EditorAccessStatus[] = ["none", "active", "suspended", "revoked"];
const STATUS_LABEL: Record<EditorAccessStatus, string> = {
  none: "Applicants (no access)",
  active: "Active editors",
  suspended: "Suspended",
  revoked: "Revoked",
};

// Own Suspense boundary: per-request data must not block navigation into this page.
export default function AdminPage() {
  return (
    <Suspense fallback={<Loading />}>
      <AdminContent />
    </Suspense>
  );
}

async function AdminContent() {
  const access = await requireAdmin();
  // Timed rules first (Phase 12C auto-hold), so the figures below include any hold it applied.
  await runTimedRules();
  const supabase = await createClient();

  // Both queries go through RLS: they return everything only because this
  // session is an admin with MFA (private.is_admin()).
  const [newInquiries, metrics, editors, logs] = await Promise.all([
    countNewInquiries(),
    getDashboardMetrics(),
    supabase.from("editor_profiles").select("access_status"),
    supabase
      .from("activity_logs")
      .select("id, action, entity_type, entity_id, created_at")
      .order("created_at", { ascending: false })
      .limit(10),
  ]);
  if (editors.error) throw editors.error;
  if (logs.error) throw logs.error;

  const counts = Object.fromEntries(STATUSES.map((s) => [s, 0])) as Record<
    EditorAccessStatus,
    number
  >;
  for (const row of editors.data) counts[row.access_status] += 1;

  return (
    <AreaShell
      title="Admin overview"
      subtitle={access.email ?? undefined}
      actions={<SignOutButton />}
    >
      <Card>
        <CardHeader>
          <CardTitle className="text-3xl tabular-nums">{newInquiries}</CardTitle>
        </CardHeader>
        <CardContent className="text-sm">
          <Link href="/admin/inquiries" className="underline">
            New client inquiries
          </Link>
        </CardContent>
      </Card>

      <section className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        {STATUSES.map((status) => (
          <Card key={status}>
            <CardHeader>
              <CardTitle className="text-3xl tabular-nums">{counts[status]}</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground text-sm">
              {STATUS_LABEL[status]}
            </CardContent>
          </Card>
        ))}
      </section>

      <section aria-labelledby="pilot-metrics" className="grid gap-4">
        <h2 id="pilot-metrics" className="text-lg font-semibold">
          Pilot metrics
        </h2>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <MetricCard
            label="Inquiry conversion"
            value={formatRate(metrics.inquiries.conversion_rate)}
            hint="Converted inquiries out of all non-spam inquiries."
          />
          <MetricCard
            label="On-time submissions"
            value={formatRate(metrics.delivery.on_time_rate)}
            hint={`${metrics.delivery.submissions} submissions; target 90%.`}
          />
          <MetricCard
            label="First-submission approval"
            value={formatRate(metrics.delivery.first_submission_approval_rate)}
            hint="Reviewed first versions approved; target 70%."
          />
          <MetricCard
            label="Client revision rounds"
            value={metrics.revisions.average_client_rounds ?? "—"}
            hint="Average per project with a submission."
          />
          <MetricCard
            label="Time to assignment"
            value={formatHours(metrics.assignments.median_hours_to_assignment)}
            hint="Median from project creation to confirmed editor."
          />
          <MetricCard
            label="Turnaround"
            value={formatHours(metrics.delivery.median_hours_to_first_submission)}
            hint="Median from confirmation to first submission."
          />
          <MetricCard
            label="Offer acceptance"
            value={formatRate(metrics.assignments.acceptance_rate)}
            hint={`Counteroffers on ${formatRate(metrics.assignments.counteroffer_rate)} of ${metrics.assignments.offers} offers.`}
          />
          <MetricCard
            label="Editor-caused corrections"
            value={metrics.revisions.editor_corrections}
            hint={`Scope changes: ${metrics.revisions.scope_changes}.`}
          />
        </div>
        <div className="grid gap-4 lg:grid-cols-2">
          <BarChart
            title="Inquiries by status"
            bars={barsFor(metrics.inquiries.by_status, INQUIRY_ORDER, INQUIRY_LABEL)}
          />
          <BarChart
            title="Applications by status"
            bars={barsFor(metrics.applications.by_status, APPLICATION_ORDER, APPLICATION_LABEL)}
          />
          <BarChart
            title="Projects by status"
            bars={barsFor(metrics.projects.by_status, PROJECT_ORDER, PROJECT_LABEL)}
          />
          <Card>
            <CardHeader>
              <CardTitle>Editor payments</CardTitle>
            </CardHeader>
            <CardContent>
              {metrics.payments.length === 0 ? (
                <EmptyState title="No payment records yet">
                  Records are created when an assignment is confirmed.
                </EmptyState>
              ) : (
                <dl className="grid gap-3 text-sm">
                  {metrics.payments.map((p) => (
                    <div key={p.currency} className="grid gap-1">
                      <div className="flex flex-wrap justify-between gap-2">
                        <dt className="text-muted-foreground">
                          Outstanding ({p.outstanding_count})
                        </dt>
                        <dd className="font-medium tabular-nums">
                          {formatAmount(p.outstanding, p.currency)}
                        </dd>
                      </div>
                      <div className="flex flex-wrap justify-between gap-2">
                        <dt className="text-muted-foreground">Committed, not yet due</dt>
                        <dd className="tabular-nums">{formatAmount(p.not_due, p.currency)}</dd>
                      </div>
                      <div className="flex flex-wrap justify-between gap-2">
                        <dt className="text-muted-foreground">Paid (net of reversals)</dt>
                        <dd className="tabular-nums">{formatAmount(p.paid, p.currency)}</dd>
                      </div>
                    </div>
                  ))}
                </dl>
              )}
              <Link href="/admin/earnings" className="mt-3 inline-block text-sm underline">
                Open earnings
              </Link>
            </CardContent>
          </Card>
        </div>
      </section>

      <Card>
        <CardHeader>
          <CardTitle>Recent activity</CardTitle>
        </CardHeader>
        <CardContent>
          {logs.data.length === 0 ? (
            <EmptyState title="No activity yet">
              Changes to applications, inquiries and editor access are logged here.
            </EmptyState>
          ) : (
            <ul className="grid gap-2 text-sm">
              {logs.data.map((log) => (
                <li key={log.id} className="flex flex-wrap justify-between gap-2">
                  <span className="font-medium">{activityLabel(log.action)}</span>
                  <span className="text-muted-foreground tabular-nums">
                    {new Date(log.created_at).toISOString().replace("T", " ").slice(0, 16)} UTC
                  </span>
                </li>
              ))}
            </ul>
          )}
          <Link href="/admin/activity" className="mt-3 inline-block text-sm underline">
            View all activity
          </Link>
        </CardContent>
      </Card>
    </AreaShell>
  );
}
