import type { ReactNode } from "react";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

import type { Bar } from "../constants";

/** One headline number with a short explanation. */
export function MetricCard({
  label,
  value,
  hint,
}: {
  label: string;
  value: ReactNode;
  hint?: string;
}) {
  return (
    <Card>
      <CardHeader>
        <CardDescription>{label}</CardDescription>
        <CardTitle className="text-2xl tabular-nums">{value}</CardTitle>
      </CardHeader>
      {hint ? <CardContent className="text-muted-foreground text-xs">{hint}</CardContent> : null}
    </Card>
  );
}

/**
 * Horizontal bar chart in plain HTML/CSS. Every bar carries its label and number as text, so the
 * chart reads correctly without colour and for screen readers (a list of label/value pairs).
 */
export function BarChart({ title, bars, total }: { title: string; bars: Bar[]; total?: number }) {
  const max = Math.max(1, ...bars.map((b) => b.value));
  const sum = total ?? bars.reduce((acc, b) => acc + b.value, 0);
  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>{sum} in total</CardDescription>
      </CardHeader>
      <CardContent>
        <ul aria-label={title} className="grid gap-2">
          {bars.map((b) => (
            <li
              key={b.key}
              className="grid grid-cols-[minmax(0,8rem)_1fr_2.5rem] items-center gap-2 text-sm"
            >
              <span className="text-muted-foreground truncate">{b.label}</span>
              <span aria-hidden className="bg-muted h-2.5 overflow-hidden rounded-full">
                <span
                  className="bg-primary block h-full rounded-full"
                  style={{ width: `${(b.value / max) * 100}%` }}
                />
              </span>
              <span className="text-right font-medium tabular-nums">
                <span className="sr-only">{b.label}: </span>
                {b.value}
              </span>
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  );
}
