import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { SignOutButton } from "@/components/sign-out-button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { countNewInquiries } from "@/features/inquiries/queries";
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
  const supabase = await createClient();

  // Both queries go through RLS: they return everything only because this
  // session is an admin with MFA (private.is_admin()).
  const [newInquiries, editors, logs] = await Promise.all([
    countNewInquiries(),
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

      <Card>
        <CardHeader>
          <CardTitle>Recent activity</CardTitle>
        </CardHeader>
        <CardContent>
          {logs.data.length === 0 ? (
            <p className="text-muted-foreground text-sm">No activity yet.</p>
          ) : (
            <ul className="grid gap-2 text-sm">
              {logs.data.map((log) => (
                <li key={log.id} className="flex flex-wrap justify-between gap-2">
                  <span className="font-medium">{log.action}</span>
                  <span className="text-muted-foreground tabular-nums">
                    {new Date(log.created_at).toISOString().replace("T", " ").slice(0, 16)} UTC
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
