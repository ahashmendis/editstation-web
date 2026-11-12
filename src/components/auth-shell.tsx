import Link from "next/link";
import type { ReactNode } from "react";

import { Wordmark } from "@/components/wordmark";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

export function AuthShell({
  title,
  description,
  children,
  footer,
}: {
  title: string;
  description?: string;
  children: ReactNode;
  footer?: ReactNode;
}) {
  return (
    <main className="flex flex-1 items-center justify-center px-4 py-12">
      <div className="grid w-full max-w-sm gap-6">
        <Link href="/" aria-label="EDITSTATION home" className="text-center">
          <Wordmark />
        </Link>
        <Card>
          <CardHeader>
            <CardTitle>{title}</CardTitle>
            {description ? <CardDescription>{description}</CardDescription> : null}
          </CardHeader>
          <CardContent>{children}</CardContent>
        </Card>
        {footer ? <div className="text-muted-foreground text-center text-sm">{footer}</div> : null}
      </div>
    </main>
  );
}

export function AreaShell({
  title,
  subtitle,
  actions,
  children,
}: {
  title: string;
  subtitle?: string;
  actions?: ReactNode;
  children: ReactNode;
}) {
  return (
    <main className="mx-auto grid w-full max-w-4xl gap-6 px-4 py-10">
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="text-muted-foreground text-xs font-medium tracking-widest uppercase">
            EDITSTATION
          </p>
          <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
          {subtitle ? <p className="text-muted-foreground text-sm">{subtitle}</p> : null}
        </div>
        {actions}
      </header>
      {children}
    </main>
  );
}

export function Loading() {
  return <p className="text-muted-foreground p-8 text-center text-sm">Loading…</p>;
}
