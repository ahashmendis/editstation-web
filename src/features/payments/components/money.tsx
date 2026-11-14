import { formatMoney } from "@/features/access/constants";

/** An amount with its currency; negative amounts (corrections) use a true minus sign. */
export function Money({ amount, currency }: { amount: number; currency: string }) {
  const text = formatMoney(Math.abs(amount), currency);
  return <span className="tabular-nums">{amount < 0 ? `−${text}` : text}</span>;
}
