import Link from "next/link";

import type { EditorFigures } from "../summary";
import { Money } from "./money";

type FigureKey = "committed" | "awaitingTransfer" | "onHold" | "paidThisMonth" | "paidAllTime";

const COLUMNS: { key: FigureKey; label: string }[] = [
  { key: "committed", label: "Committed" },
  { key: "awaitingTransfer", label: "Awaiting transfer" },
  { key: "onHold", label: "On hold" },
  { key: "paidThisMonth", label: "Paid this month" },
  { key: "paidAllTime", label: "Paid all time" },
];

/** The earnings page filtered to one editor shows their payout card (Phase 12E). */
function PayoutLink({ editorId, name }: { editorId: string; name: string }) {
  return (
    <Link
      href={`/admin/earnings?editor=${editorId}`}
      className="underline"
      aria-label={`Payout account of ${name}`}
    >
      Payout account
    </Link>
  );
}

/** Figures per editor and currency; row cards below `sm`. */
export function EditorBreakdown({
  rows,
  names,
}: {
  rows: EditorFigures[];
  names: Map<string, string>;
}) {
  return (
    <>
      <ul className="grid gap-3 sm:hidden">
        {rows.map((row) => (
          <li
            key={`${row.editorId}-${row.currency}`}
            className="grid gap-1 border-t pt-3 text-sm first:border-t-0 first:pt-0"
          >
            <p className="font-medium">
              {names.get(row.editorId) ?? "Unknown editor"} · {row.currency}
            </p>
            <dl className="grid grid-cols-2 gap-x-4 gap-y-1">
              {COLUMNS.map((c) => (
                <div key={c.key} className="contents">
                  <dt className="text-muted-foreground">{c.label}</dt>
                  <dd>
                    <Money amount={row[c.key]} currency={row.currency} />
                  </dd>
                </div>
              ))}
              <dt className="text-muted-foreground">Overdue</dt>
              <dd className="tabular-nums">{row.overdue}</dd>
            </dl>
            <PayoutLink editorId={row.editorId} name={names.get(row.editorId) ?? "the editor"} />
          </li>
        ))}
      </ul>
      <div className="hidden overflow-x-auto sm:block">
        <table className="w-full text-left text-sm">
          <thead className="text-muted-foreground">
            <tr>
              <th className="py-2 pr-4 font-medium">Editor</th>
              {COLUMNS.map((c) => (
                <th key={c.key} className="py-2 pr-4 font-medium">
                  {c.label}
                </th>
              ))}
              <th className="py-2 pr-4 font-medium">Overdue</th>
              <th className="py-2 font-medium">
                <span className="sr-only">Payout account</span>
              </th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={`${row.editorId}-${row.currency}`} className="border-t">
                <td className="py-2 pr-4">{names.get(row.editorId) ?? "Unknown editor"}</td>
                {COLUMNS.map((c) => (
                  <td key={c.key} className="py-2 pr-4 whitespace-nowrap">
                    <Money amount={row[c.key]} currency={row.currency} />
                  </td>
                ))}
                <td className="py-2 pr-4 tabular-nums">{row.overdue}</td>
                <td className="py-2 whitespace-nowrap">
                  <PayoutLink
                    editorId={row.editorId}
                    name={names.get(row.editorId) ?? "the editor"}
                  />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
