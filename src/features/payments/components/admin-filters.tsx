import Link from "next/link";

import { buttonVariants } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { selectClassName } from "@/features/projects/components/select-class";

import { PAYMENT_STATUSES, PAYMENT_STATUS_LABEL } from "../constants";
import type { AdminEarningsFilter } from "../schemas";

/** Plain GET form: works without JavaScript. */
export function AdminFilters({
  filter,
  editors,
  currencies,
}: {
  filter: AdminEarningsFilter;
  editors: { id: string; name: string }[];
  currencies: string[];
}) {
  return (
    <form method="get" action="/admin/earnings" className="grid gap-3 sm:grid-cols-4 sm:items-end">
      <div className="grid gap-2">
        <Label htmlFor="filter-status">Status</Label>
        <select
          id="filter-status"
          name="status"
          defaultValue={filter.status ?? ""}
          className={selectClassName}
        >
          <option value="">All statuses</option>
          {PAYMENT_STATUSES.map((s) => (
            <option key={s} value={s}>
              {PAYMENT_STATUS_LABEL[s]}
            </option>
          ))}
        </select>
      </div>
      <div className="grid gap-2">
        <Label htmlFor="filter-editor">Editor</Label>
        <select
          id="filter-editor"
          name="editor"
          defaultValue={filter.editor ?? ""}
          className={selectClassName}
        >
          <option value="">All editors</option>
          {editors.map((e) => (
            <option key={e.id} value={e.id}>
              {e.name}
            </option>
          ))}
        </select>
      </div>
      <div className="grid gap-2">
        <Label htmlFor="filter-currency">Currency</Label>
        <select
          id="filter-currency"
          name="currency"
          defaultValue={filter.currency ?? ""}
          className={selectClassName}
        >
          <option value="">All currencies</option>
          {currencies.map((c) => (
            <option key={c} value={c}>
              {c}
            </option>
          ))}
        </select>
      </div>
      <div className="flex flex-wrap gap-2">
        <button type="submit" className={buttonVariants()}>
          Apply
        </button>
        <Link href="/admin/earnings" className={buttonVariants({ variant: "ghost" })}>
          Clear
        </Link>
      </div>
    </form>
  );
}
