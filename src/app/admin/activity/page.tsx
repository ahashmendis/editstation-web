import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { EmptyState } from "@/components/empty-state";
import { SignOutButton } from "@/components/sign-out-button";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { formatDateTime } from "@/features/applications/components/status-badge";
import {
  activityActions,
  activityEntityHref,
  activityLabel,
  ENTITY_TYPE_LABEL,
  entityTypeLabel,
  isKnownActivityAction,
} from "@/lib/activity-labels";
import { requireAdmin } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Activity · Admin · EDITSTATION" };

const LIMIT = 200;
const selectClass =
  "border-input bg-background focus-visible:ring-ring min-h-11 w-full rounded-md border px-3 text-sm focus-visible:ring-2 focus-visible:outline-none";

export default function ActivityPage({ searchParams }: PageProps<"/admin/activity">) {
  return (
    <Suspense fallback={<Loading />}>
      <ActivityContent searchParams={searchParams} />
    </Suspense>
  );
}

async function ActivityContent({
  searchParams,
}: {
  searchParams: PageProps<"/admin/activity">["searchParams"];
}) {
  await requireAdmin();
  const params = await searchParams;
  // Only known values reach the query; anything else means "all".
  const entity =
    typeof params.entity === "string" && Object.hasOwn(ENTITY_TYPE_LABEL, params.entity)
      ? params.entity
      : "";
  const action =
    typeof params.action === "string" && isKnownActivityAction(params.action) ? params.action : "";

  // Read-only, through RLS: activity_logs is visible only to an MFA admin (private.is_admin()).
  const supabase = await createClient();
  let query = supabase
    .from("activity_logs")
    .select("id, action, entity_type, entity_id, created_at, actor:profiles(email)")
    .order("created_at", { ascending: false })
    .limit(LIMIT);
  if (entity) query = query.eq("entity_type", entity);
  if (action) query = query.eq("action", action);
  const { data: rows, error } = await query;
  if (error) throw error;

  return (
    <AreaShell
      title="Activity"
      subtitle="The audit trail of every recorded change. Read-only."
      actions={<SignOutButton />}
    >
      <form method="get" className="grid gap-3 sm:grid-cols-[1fr_1fr_auto] sm:items-end">
        <div className="grid gap-1">
          <label htmlFor="entity" className="text-sm font-medium">
            Record type
          </label>
          <select id="entity" name="entity" defaultValue={entity} className={selectClass}>
            <option value="">All record types</option>
            {Object.entries(ENTITY_TYPE_LABEL)
              .sort((a, b) => a[1].localeCompare(b[1]))
              .map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
          </select>
        </div>
        <div className="grid gap-1">
          <label htmlFor="action" className="text-sm font-medium">
            Action
          </label>
          <select id="action" name="action" defaultValue={action} className={selectClass}>
            <option value="">All actions</option>
            {activityActions().map((a) => (
              <option key={a.code} value={a.code}>
                {a.label} ({a.code.split(".")[0].replaceAll("_", " ")})
              </option>
            ))}
          </select>
        </div>
        <div className="flex gap-2">
          <Button type="submit" className="min-h-11">
            Filter
          </Button>
          {entity || action ? (
            <Link
              href="/admin/activity"
              className="hover:bg-muted inline-flex min-h-11 items-center rounded-md border px-3 text-sm"
            >
              Clear
            </Link>
          ) : null}
        </div>
      </form>

      <Card>
        <CardContent>
          {rows.length === 0 ? (
            <EmptyState title={entity || action ? "No matching activity" : "No activity yet"}>
              {entity || action
                ? "Try a different record type or action."
                : "Changes to inquiries, applications, projects and payments are logged here."}
            </EmptyState>
          ) : (
            <ul className="divide-y">
              {rows.map((row) => {
                const href = activityEntityHref(row.entity_type, row.entity_id);
                return (
                  <li key={row.id} className="grid gap-1 py-3 text-sm">
                    <div className="flex flex-wrap items-baseline justify-between gap-2">
                      <span className="font-medium">{activityLabel(row.action)}</span>
                      <span className="text-muted-foreground text-xs tabular-nums">
                        {formatDateTime(row.created_at)}
                      </span>
                    </div>
                    <p className="text-muted-foreground break-words">
                      {href ? (
                        <Link href={href} className="underline underline-offset-4">
                          {entityTypeLabel(row.entity_type)}
                        </Link>
                      ) : (
                        entityTypeLabel(row.entity_type)
                      )}
                      {" · "}
                      {row.actor?.email ?? "System or public form"}
                    </p>
                  </li>
                );
              })}
            </ul>
          )}
        </CardContent>
      </Card>
      {rows.length === LIMIT ? (
        <p className="text-muted-foreground text-sm">
          Showing the latest {LIMIT} entries. Use the filters to narrow the list.
        </p>
      ) : null}
    </AreaShell>
  );
}
