import { EmptyState } from "@/components/empty-state";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

import type { EarningsFigures } from "../summary";
import { Money } from "./money";

export type SummaryCardSpec = {
  key: keyof Omit<EarningsFigures, "overdue">;
  label: string;
  /** Hide the card when its figure is zero. */
  hideWhenZero?: boolean;
};

/** One group of figure cards per currency; cards stack at narrow widths. */
export function SummaryCards({
  summary,
  cards,
  emptyTitle,
}: {
  summary: Record<string, EarningsFigures>;
  cards: SummaryCardSpec[];
  emptyTitle?: string;
}) {
  const currencies = Object.keys(summary);
  if (currencies.length === 0) return emptyTitle ? <EmptyState title={emptyTitle} /> : null;
  return (
    <div className="grid gap-4">
      {currencies.map((currency) => {
        const figures = summary[currency];
        const visible = cards.filter((c) => !(c.hideWhenZero && figures[c.key] === 0));
        return (
          <section key={currency} aria-label={`Totals in ${currency}`} className="grid gap-2">
            {currencies.length > 1 ? (
              <h2 className="text-muted-foreground text-xs font-medium tracking-widest uppercase">
                {currency}
              </h2>
            ) : null}
            <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
              {visible.map((c) => (
                <li key={c.key}>
                  <Card size="sm">
                    <CardHeader>
                      <CardTitle className="text-muted-foreground text-sm font-normal">
                        {c.label}
                      </CardTitle>
                    </CardHeader>
                    <CardContent className="text-xl font-semibold">
                      <Money amount={figures[c.key]} currency={currency} />
                    </CardContent>
                  </Card>
                </li>
              ))}
            </ul>
          </section>
        );
      })}
    </div>
  );
}
