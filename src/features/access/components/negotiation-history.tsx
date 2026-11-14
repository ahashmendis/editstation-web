import { formatDateTime } from "@/features/applications/components/status-badge";

import { NEGOTIATION_ACTION_LABEL, formatMoney, type NegotiationAction } from "../constants";

export type NegotiationRow = {
  id: string;
  fromRole: "admin" | "editor";
  action: NegotiationAction;
  amount: number | null;
  currency: string | null;
  message: string | null;
  createdAt: string;
};

/** Oldest first. `viewer` decides how each side is named. */
export function NegotiationHistory({
  rows,
  viewer,
  editorName,
}: {
  rows: NegotiationRow[];
  viewer: "admin" | "editor";
  editorName?: string;
}) {
  if (rows.length === 0) {
    return <p className="text-muted-foreground text-sm">No offers or replies yet.</p>;
  }
  const who = (role: "admin" | "editor") =>
    viewer === "editor"
      ? role === "editor"
        ? "You"
        : "The studio"
      : role === "editor"
        ? (editorName ?? "The editor")
        : "Admin";
  return (
    <ol className="grid gap-3 text-sm">
      {rows.map((r) => (
        <li key={r.id} className="border-t pt-3 first:border-t-0 first:pt-0">
          <div className="flex flex-wrap justify-between gap-2">
            <span>
              <span className="font-medium">{who(r.fromRole)}</span>{" "}
              {NEGOTIATION_ACTION_LABEL[r.action]}
              {r.amount !== null ? <>: {formatMoney(r.amount, r.currency)}</> : null}
            </span>
            <span className="text-muted-foreground tabular-nums">
              {formatDateTime(r.createdAt)}
            </span>
          </div>
          {r.message ? (
            <p className="text-muted-foreground whitespace-pre-line">{r.message}</p>
          ) : null}
        </li>
      ))}
    </ol>
  );
}
