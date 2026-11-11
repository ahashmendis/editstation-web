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
import { AdminActionForm } from "@/features/applications/components/admin-action-form";
import { SafeLink } from "@/features/applications/components/snapshot-view";
import { formatDateTime } from "@/features/applications/components/status-badge";
import { addInquiryNoteAction, setInquiryStatusAction } from "@/features/inquiries/admin-actions";
import { InquiryStatusBadge } from "@/features/inquiries/components/inquiry-status-badge";
import { INQUIRY_STATUS_LABEL, SETTABLE_INQUIRY_STATUSES } from "@/features/inquiries/constants";
import { getInquiryDetail } from "@/features/inquiries/queries";
import { requireAdmin } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Inquiry · Admin · EDITSTATION" };

const selectClass = "border-input h-9 rounded-md border bg-transparent px-3 text-sm";

export default function InquiryPage({ params }: PageProps<"/admin/inquiries/[id]">) {
  return (
    <Suspense fallback={<Loading />}>
      <InquiryContent params={params} />
    </Suspense>
  );
}

async function InquiryContent({
  params,
}: {
  params: PageProps<"/admin/inquiries/[id]">["params"];
}) {
  await requireAdmin();
  const { id } = await params;
  if (!z.uuid().safeParse(id).success) notFound();
  const detail = await getInquiryDetail(id);
  if (!detail) notFound();
  const { inquiry: q, links, notes, activity } = detail;

  const rows: [string, string | null][] = [
    ["Company / agency", q.company],
    ["Email", q.email],
    ["Phone", q.phone],
    ["Service", q.service_type_label],
    ["Budget", `${q.budget_label}${q.budget_range_id ? ` (${q.budget_currency})` : ""}`],
    ["Expected deadline", q.expected_deadline],
    ["Privacy notice", q.privacy_notice_version],
  ];

  return (
    <AreaShell
      title={q.contact_name}
      subtitle={`Received ${formatDateTime(q.submitted_at)}`}
      actions={<SignOutButton />}
    >
      <Link href="/admin/inquiries" className="text-muted-foreground text-sm underline">
        ← All inquiries
      </Link>

      <Card>
        <CardHeader>
          <div className="flex flex-wrap items-center gap-3">
            <CardTitle>Inquiry</CardTitle>
            <InquiryStatusBadge status={q.status} />
          </div>
          <CardDescription>
            Contact the client directly to discuss scope, pricing and deadlines. Converting a
            confirmed inquiry into a project arrives in Phase 4.
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4 text-sm">
          <dl className="grid gap-x-6 gap-y-2 sm:grid-cols-[12rem_1fr]">
            {rows.map(([label, value]) => (
              <div key={label} className="contents">
                <dt className="text-muted-foreground">{label}</dt>
                <dd className="break-words">{value || "—"}</dd>
              </div>
            ))}
          </dl>
          <div className="grid gap-1">
            <p className="text-muted-foreground">Project description</p>
            <p className="whitespace-pre-wrap">{q.description}</p>
          </div>
          {q.expected_deliverables ? (
            <div className="grid gap-1">
              <p className="text-muted-foreground">Expected deliverables</p>
              <p className="whitespace-pre-wrap">{q.expected_deliverables}</p>
            </div>
          ) : null}
          {q.client_notes ? (
            <div className="grid gap-1">
              <p className="text-muted-foreground">Additional notes from the client</p>
              <p className="whitespace-pre-wrap">{q.client_notes}</p>
            </div>
          ) : null}
          {links.length ? (
            <div className="grid gap-1">
              <p className="text-muted-foreground">Reference links</p>
              <ul className="grid gap-1">
                {links.map((link) => (
                  <li key={link.id}>
                    <SafeLink url={link.url} label={link.label} />
                  </li>
                ))}
              </ul>
            </div>
          ) : null}
        </CardContent>
      </Card>

      {q.status !== "converted" ? (
        <Card>
          <CardHeader>
            <CardTitle>Update status</CardTitle>
          </CardHeader>
          <CardContent>
            <AdminActionForm action={setInquiryStatusAction} submitLabel="Update status">
              <input type="hidden" name="inquiryId" value={q.id} />
              <select
                name="status"
                className={selectClass}
                defaultValue=""
                aria-label="New status"
                required
              >
                <option value="" disabled>
                  Choose…
                </option>
                {SETTABLE_INQUIRY_STATUSES.filter((s) => s !== q.status).map((s) => (
                  <option key={s} value={s}>
                    {INQUIRY_STATUS_LABEL[s]}
                  </option>
                ))}
              </select>
              <div className="grid gap-2">
                <Label htmlFor="status-note">Note (optional, internal)</Label>
                <Textarea id="status-note" name="note" rows={2} />
              </div>
            </AdminActionForm>
          </CardContent>
        </Card>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle>Internal notes</CardTitle>
          <CardDescription>Never shown to the client.</CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4 text-sm">
          <AdminActionForm action={addInquiryNoteAction} submitLabel="Add note" variant="outline">
            <input type="hidden" name="inquiryId" value={q.id} />
            <div className="grid gap-2">
              <Label htmlFor="inquiry-note">Note</Label>
              <Textarea id="inquiry-note" name="note" rows={3} required />
            </div>
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
        <CardContent>
          <ul className="grid gap-1 text-sm">
            {activity.map((entry) => (
              <li key={entry.id} className="flex flex-wrap justify-between gap-2">
                <span>{entry.action}</span>
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
