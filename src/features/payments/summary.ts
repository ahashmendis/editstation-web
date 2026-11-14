import {
  AWAITING_TRANSFER_STATUSES,
  COMMITTED_STATUSES,
  type PaymentKind,
  type PaymentStatus,
} from "./constants";

/** The fields the earnings figures need (spec §9). Amounts are as stored (reversals negative). */
export type PaymentLike = {
  status: PaymentStatus;
  kind: PaymentKind;
  amount: number;
  currency: string;
  markedPaidAt: string | null;
  dueDate: string | null;
  editorId?: string;
  projectId?: string;
};

export type EarningsFigures = {
  committed: number;
  awaitingTransfer: number;
  onHold: number;
  paidThisMonth: number;
  paidAllTime: number;
  overdue: number;
};

const TIME_ZONE = "Asia/Colombo";
const colomboDate = new Intl.DateTimeFormat("en-CA", {
  timeZone: TIME_ZONE,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});

/** YYYY-MM-DD of an instant in Asia/Colombo (call 6). */
export function colomboDay(value: Date | string): string {
  return colomboDate.format(typeof value === "string" ? new Date(value) : value);
}

const cents = (amount: number) => Math.round(amount * 100);
const fromCents = (value: number) => value / 100;

type CentFigures = Record<keyof EarningsFigures, number>;
const emptyCents = (): CentFigures => ({
  committed: 0,
  awaitingTransfer: 0,
  onHold: 0,
  paidThisMonth: 0,
  paidAllTime: 0,
  overdue: 0,
});

function add(target: CentFigures, row: PaymentLike, today: string) {
  const c = cents(row.amount);
  if (COMMITTED_STATUSES.includes(row.status)) {
    target.committed += c;
    if (row.dueDate !== null && row.dueDate < today) target.overdue += 1;
  }
  if (AWAITING_TRANSFER_STATUSES.includes(row.status)) target.awaitingTransfer += c;
  if (row.status === "on_hold") target.onHold += c;
  if (row.status === "paid") {
    target.paidAllTime += c;
    if (row.markedPaidAt !== null && colomboDay(row.markedPaidAt).slice(0, 7) === today.slice(0, 7))
      target.paidThisMonth += c;
  }
}

function toFigures(c: CentFigures): EarningsFigures {
  return {
    committed: fromCents(c.committed),
    awaitingTransfer: fromCents(c.awaitingTransfer),
    onHold: fromCents(c.onHold),
    paidThisMonth: fromCents(c.paidThisMonth),
    paidAllTime: fromCents(c.paidAllTime),
    overdue: c.overdue,
  };
}

/** Figures per currency; currencies are never summed together (decision H). */
export function summariseByCurrency(
  rows: readonly PaymentLike[],
  now: Date,
): Record<string, EarningsFigures> {
  const today = colomboDay(now);
  const byCurrency = new Map<string, CentFigures>();
  for (const row of rows) {
    const bucket = byCurrency.get(row.currency) ?? emptyCents();
    add(bucket, row, today);
    byCurrency.set(row.currency, bucket);
  }
  return Object.fromEntries(
    [...byCurrency.entries()]
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([currency, c]) => [currency, toFigures(c)]),
  );
}

export type EditorFigures = EarningsFigures & { editorId: string; currency: string };

/** Figures per (editor, currency), largest committed first. */
export function summariseByEditor(rows: readonly PaymentLike[], now: Date): EditorFigures[] {
  const today = colomboDay(now);
  const groups = new Map<string, { editorId: string; currency: string; c: CentFigures }>();
  for (const row of rows) {
    if (!row.editorId) continue;
    const key = `${row.editorId}|${row.currency}`;
    const group = groups.get(key) ?? {
      editorId: row.editorId,
      currency: row.currency,
      c: emptyCents(),
    };
    add(group.c, row, today);
    groups.set(key, group);
  }
  return [...groups.values()]
    .map((g) => ({ editorId: g.editorId, currency: g.currency, ...toFigures(g.c) }))
    .sort((a, b) => b.committed - a.committed || a.editorId.localeCompare(b.editorId));
}

export type ProjectMargin =
  | { kind: "margin"; amount: number; currency: string; includesOnHold: boolean }
  | { kind: "no_price" }
  | { kind: "mixed_currency" };

/** Client price minus the net editor cost of every payment row of the project (admin only). */
export function projectMargin({
  clientPrice,
  clientCurrency,
  rows,
}: {
  clientPrice: number | null;
  clientCurrency: string;
  rows: readonly PaymentLike[];
}): ProjectMargin {
  if (clientPrice === null) return { kind: "no_price" };
  if (rows.some((r) => r.currency !== clientCurrency)) return { kind: "mixed_currency" };
  const cost = rows.reduce((sum, r) => sum + cents(r.amount), 0);
  return {
    kind: "margin",
    amount: fromCents(cents(clientPrice) - cost),
    currency: clientCurrency,
    includesOnHold: rows.some((r) => r.status === "on_hold"),
  };
}
