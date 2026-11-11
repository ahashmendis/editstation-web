import type { Metadata } from "next";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { SignOutButton } from "@/components/sign-out-button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { AdminActionForm } from "@/features/applications/components/admin-action-form";
import { saveBudgetRangeAction, saveServiceTypeAction } from "@/features/inquiries/admin-actions";
import { getSettingsLists } from "@/features/inquiries/queries";
import { requireAdmin } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Settings · Admin · EDITSTATION" };

const inputClass = "border-input h-9 w-full rounded-md border bg-transparent px-3 text-sm";

function Input({
  id,
  name,
  label,
  defaultValue,
  type = "text",
  readOnly,
}: {
  id: string;
  name: string;
  label: string;
  defaultValue?: string | number | null;
  type?: string;
  readOnly?: boolean;
}) {
  return (
    <label htmlFor={id} className="grid gap-1 text-xs">
      <span className="text-muted-foreground">{label}</span>
      <input
        id={id}
        name={name}
        type={type}
        defaultValue={defaultValue ?? ""}
        readOnly={readOnly}
        className={inputClass}
        step={type === "number" ? "any" : undefined}
      />
    </label>
  );
}

function Active({ id, defaultChecked }: { id: string; defaultChecked: boolean }) {
  return (
    <label htmlFor={id} className="flex items-center gap-2 self-end pb-2 text-sm">
      <input
        id={id}
        type="checkbox"
        name="active"
        defaultChecked={defaultChecked}
        className="size-4"
      />
      Active
    </label>
  );
}

export default function SettingsPage() {
  return (
    <Suspense fallback={<Loading />}>
      <SettingsContent />
    </Suspense>
  );
}

async function SettingsContent() {
  await requireAdmin();
  const { services, budgets } = await getSettingsLists();

  return (
    <AreaShell title="Settings" actions={<SignOutButton />}>
      <Card>
        <CardHeader>
          <CardTitle>Service types</CardTitle>
          <CardDescription>
            Shown on the public inquiry form. The starting list is a placeholder from the knowledge
            base (KB3 is still open): rename, reorder or deactivate as needed. Codes can&apos;t be
            changed once created; inquiries keep the label they were submitted with.
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4">
          {services.map((s) => (
            <AdminActionForm
              key={s.code}
              action={saveServiceTypeAction}
              submitLabel="Save"
              variant="outline"
            >
              <input type="hidden" name="mode" value="update" />
              <div className="grid gap-3 sm:grid-cols-[1fr_2fr_6rem_auto]">
                <Input
                  id={`svc-code-${s.code}`}
                  name="code"
                  label="Code"
                  defaultValue={s.code}
                  readOnly
                />
                <Input
                  id={`svc-label-${s.code}`}
                  name="label"
                  label="Label"
                  defaultValue={s.label}
                />
                <Input
                  id={`svc-sort-${s.code}`}
                  name="sortOrder"
                  label="Order"
                  type="number"
                  defaultValue={s.sort_order}
                />
                <Active id={`svc-active-${s.code}`} defaultChecked={s.active} />
              </div>
            </AdminActionForm>
          ))}
          <div className="border-t pt-4">
            <p className="mb-2 text-sm font-medium">Add a service type</p>
            <AdminActionForm action={saveServiceTypeAction} submitLabel="Add service type">
              <input type="hidden" name="mode" value="create" />
              <div className="grid gap-3 sm:grid-cols-[1fr_2fr_6rem_auto]">
                <Input id="svc-new-code" name="code" label="Code (e.g. event_highlights)" />
                <Input id="svc-new-label" name="label" label="Label" />
                <Input
                  id="svc-new-sort"
                  name="sortOrder"
                  label="Order"
                  type="number"
                  defaultValue={50}
                />
                <Active id="svc-new-active" defaultChecked />
              </div>
            </AdminActionForm>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Budget ranges</CardTitle>
          <CardDescription>
            Options on the inquiry form (decision V). &quot;Prefer to discuss&quot; is always
            offered. No ranges are pre-filled: add your own. Amounts are optional, for your
            reporting.
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4">
          {budgets.length === 0 ? (
            <p className="text-muted-foreground text-sm">
              No ranges yet. The form currently offers only &quot;Prefer to discuss&quot;.
            </p>
          ) : null}
          {budgets.map((b) => (
            <AdminActionForm
              key={b.id}
              action={saveBudgetRangeAction}
              submitLabel="Save"
              variant="outline"
            >
              <input type="hidden" name="id" value={b.id} />
              <div className="grid gap-3 sm:grid-cols-[2fr_1fr_1fr_5rem_5rem_auto]">
                <Input id={`b-label-${b.id}`} name="label" label="Label" defaultValue={b.label} />
                <Input
                  id={`b-min-${b.id}`}
                  name="minAmount"
                  label="Min"
                  type="number"
                  defaultValue={b.min_amount}
                />
                <Input
                  id={`b-max-${b.id}`}
                  name="maxAmount"
                  label="Max"
                  type="number"
                  defaultValue={b.max_amount}
                />
                <Input
                  id={`b-cur-${b.id}`}
                  name="currency"
                  label="Currency"
                  defaultValue={b.currency}
                />
                <Input
                  id={`b-sort-${b.id}`}
                  name="sortOrder"
                  label="Order"
                  type="number"
                  defaultValue={b.sort_order}
                />
                <Active id={`b-active-${b.id}`} defaultChecked={b.active} />
              </div>
            </AdminActionForm>
          ))}
          <div className="border-t pt-4">
            <p className="mb-2 text-sm font-medium">Add a budget range</p>
            <AdminActionForm action={saveBudgetRangeAction} submitLabel="Add range">
              <input type="hidden" name="id" value="" />
              <div className="grid gap-3 sm:grid-cols-[2fr_1fr_1fr_5rem_5rem_auto]">
                <Input id="b-new-label" name="label" label="Label (shown to clients)" />
                <Input id="b-new-min" name="minAmount" label="Min" type="number" />
                <Input id="b-new-max" name="maxAmount" label="Max" type="number" />
                <Input id="b-new-cur" name="currency" label="Currency" defaultValue="LKR" />
                <Input
                  id="b-new-sort"
                  name="sortOrder"
                  label="Order"
                  type="number"
                  defaultValue={50}
                />
                <Active id="b-new-active" defaultChecked />
              </div>
            </AdminActionForm>
          </div>
        </CardContent>
      </Card>
    </AreaShell>
  );
}
