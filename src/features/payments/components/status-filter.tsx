import Link from "next/link";

import { PAYMENT_STATUSES, PAYMENT_STATUS_LABEL, type PaymentStatus } from "../constants";

/** Status chips driven by the `status` search param. Other params are kept. */
export function StatusFilter({
  basePath,
  current,
  params = {},
}: {
  basePath: string;
  current: PaymentStatus | null;
  params?: Record<string, string | null>;
}) {
  const href = (status: PaymentStatus | null) => {
    const search = new URLSearchParams();
    for (const [k, v] of Object.entries(params)) if (v) search.set(k, v);
    if (status) search.set("status", status);
    const query = search.toString();
    return query ? `${basePath}?${query}` : basePath;
  };
  const chips: { value: PaymentStatus | null; label: string }[] = [
    { value: null, label: "All" },
    ...PAYMENT_STATUSES.map((s) => ({ value: s, label: PAYMENT_STATUS_LABEL[s] })),
  ];
  return (
    <nav aria-label="Filter by status" className="flex flex-wrap gap-2 text-sm">
      {chips.map((chip) => (
        <Link
          key={chip.label}
          href={href(chip.value)}
          aria-current={chip.value === current ? "page" : undefined}
          className={
            chip.value === current
              ? "bg-primary text-primary-foreground rounded-md px-3 py-1"
              : "hover:bg-muted rounded-md px-3 py-1"
          }
        >
          {chip.label}
        </Link>
      ))}
    </nav>
  );
}
