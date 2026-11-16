import type { ReactNode } from "react";
import { Bell, Check, FileText, Link2, Lock } from "lucide-react";

import { StatusPill } from "@/components/status-pill";
import { cn } from "@/lib/utils";

// Product graphics for the landing page, drawn in React with the app's own tokens and status
// pills (plan section 5) so they stay crisp and on-theme. Everything shown is fictional: project
// and editor names are made up, no client logos, no prices or amounts. The panels are decorative
// (aria-hidden); each sits in a <figure> whose caption says what it shows. They use the app font
// (Geist) on purpose, to read as the app rather than as the marketing page.

function Frame({ path, children }: { path: string; children: ReactNode }) {
  return (
    <div
      aria-hidden="true"
      className="bg-card text-card-foreground overflow-hidden rounded-xl border font-sans text-[0.8125rem] shadow-[0_1px_2px_rgb(0_0_0/0.04),0_12px_32px_-12px_rgb(40_20_80/0.18)]"
    >
      <div className="bg-secondary/60 flex items-center gap-3 border-b px-3.5 py-2.5">
        <span className="flex gap-1.5">
          <span className="bg-foreground/15 size-2 rounded-full" />
          <span className="bg-foreground/15 size-2 rounded-full" />
          <span className="bg-foreground/15 size-2 rounded-full" />
        </span>
        <span className="text-muted-foreground truncate font-mono text-[0.6875rem]">{path}</span>
      </div>
      <div className="grid gap-3 p-4">{children}</div>
    </div>
  );
}

function Card({
  title,
  aside,
  children,
}: {
  title: string;
  aside?: ReactNode;
  children: ReactNode;
}) {
  return (
    <div className="rounded-lg border">
      <div className="flex items-center justify-between gap-2 border-b px-3 py-2">
        <span className="font-medium">{title}</span>
        {aside}
      </div>
      <div className="grid gap-2 px-3 py-2.5">{children}</div>
    </div>
  );
}

function Row({ label, value, mono }: { label: string; value: ReactNode; mono?: boolean }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <span className="text-muted-foreground">{label}</span>
      <span className={cn("text-right", mono && "font-mono text-xs")}>{value}</span>
    </div>
  );
}

function Tick({ children }: { children: string }) {
  return (
    <li className="flex items-center gap-2">
      <span className="bg-success/15 text-success grid size-4 place-items-center rounded-full">
        <Check className="size-3" strokeWidth={3} />
      </span>
      {children}
    </li>
  );
}

function FakeButton({ children, primary }: { children: string; primary?: boolean }) {
  return (
    <span
      className={cn(
        "inline-flex h-7 items-center rounded-md px-2.5 text-xs font-medium",
        primary ? "bg-primary text-primary-foreground" : "bg-card border",
      )}
    >
      {children}
    </span>
  );
}

/** 1. Admin project page: brief, references and the agreed terms card (Phase 12A). */
export function AdminProjectPanel() {
  return (
    <Frame path="admin / projects / harbour-cafe-launch">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <p className="text-[0.9375rem] font-semibold">Harbour Café launch reel</p>
          <p className="text-muted-foreground text-xs">Brief version 2 · Short-form reel</p>
        </div>
        <StatusPill tone="info">Open</StatusPill>
      </div>
      <div className="grid gap-3 sm:grid-cols-2">
        <Card title="Brief and references">
          <p className="text-muted-foreground flex items-center gap-2">
            <FileText className="size-3.5 shrink-0" /> 3 deliverables · 9:16
          </p>
          <p className="text-muted-foreground flex items-center gap-2">
            <Link2 className="size-3.5 shrink-0" /> Moodboard · Reference cut
          </p>
          <p className="text-muted-foreground flex items-center gap-2">
            <Link2 className="size-3.5 shrink-0" /> Footage folder (Drive)
          </p>
        </Card>
        <Card title="Terms" aside={<StatusPill tone="success">Agreed</StatusPill>}>
          <Row label="Revision policy" value="3 included rounds" />
          <Row label="Editor pay" value="50% / 50%" />
          <Row label="Cancellation" value="Schedule agreed" />
        </Card>
      </div>
    </Frame>
  );
}

/** 2. Editor workspace: the offer with agreed pay, then the brief confirmation. */
export function EditorWorkspacePanel() {
  return (
    <Frame path="editor / projects / harbour-cafe-launch">
      <Card title="Offer" aside={<StatusPill tone="success">Accepted</StatusPill>}>
        <Row label="Pay" value="Agreed and approved" />
        <Row label="Deadline" value="Fri, week 3" />
      </Card>
      <Card title="Brief confirmation" aside={<StatusPill tone="success">Confirmed</StatusPill>}>
        <ul className="grid gap-1.5">
          <Tick>Brief version 2</Tick>
          <Tick>Deliverables and deadline</Tick>
          <Tick>Agreed pay</Tick>
        </ul>
      </Card>
      <div className="bg-secondary flex items-center justify-between gap-2 rounded-lg px-3 py-2">
        <span className="text-muted-foreground">Start work</span>
        <StatusPill tone="info">Waiting for the client deposit</StatusPill>
      </div>
    </Frame>
  );
}

/** 3. Review screen: version history, request classification and rounds used. */
export function ReviewPanel() {
  // Each row is the request raised on that version, as the admin classified it.
  const versions = [
    { v: "v4", note: "Resubmitted", tone: "info" as const, label: "In review" },
    { v: "v3", note: "Editor correction", tone: "neutral" as const, label: "No round used" },
    { v: "v2", note: "Client revision", tone: "neutral" as const, label: "Round 2" },
    { v: "v1", note: "Client revision", tone: "neutral" as const, label: "Round 1" },
  ];
  return (
    <Frame path="admin / projects / northline-teaser / review">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-[0.9375rem] font-semibold">Northline teaser</p>
        <span className="text-muted-foreground text-xs">
          Rounds used <span className="text-foreground font-medium">2 of 3</span>
        </span>
      </div>
      <div className="bg-secondary h-1.5 overflow-hidden rounded-full">
        <div className="bg-primary h-full w-2/3 rounded-full" />
      </div>
      <ol className="grid gap-2">
        {versions.map((x) => (
          <li
            key={x.v}
            className="flex items-center justify-between gap-2 rounded-lg border px-3 py-2"
          >
            <span className="flex min-w-0 items-center gap-2.5">
              <span className="bg-secondary rounded px-1.5 py-0.5 font-mono text-[0.6875rem]">
                {x.v}
              </span>
              <span className="truncate">{x.note}</span>
            </span>
            <StatusPill tone={x.tone}>{x.label}</StatusPill>
          </li>
        ))}
      </ol>
      <div className="flex flex-wrap gap-1.5">
        <FakeButton primary>Approve</FakeButton>
        <FakeButton>Request revision</FakeButton>
      </div>
    </Frame>
  );
}

/** 4. Earnings: the two pay milestones, plus the notification bell. */
export function EarningsPanel() {
  return (
    <Frame path="editor / earnings">
      <div className="flex items-center justify-between gap-2">
        <p className="text-[0.9375rem] font-semibold">Earnings</p>
        <span className="relative grid size-8 place-items-center rounded-md border">
          <Bell className="size-4" />
          <span className="bg-primary text-primary-foreground absolute -top-1.5 -right-1.5 grid size-4 place-items-center rounded-full text-[0.625rem] font-semibold">
            2
          </span>
        </span>
      </div>
      <Card title="Harbour Café launch reel">
        <Row label="Milestone 1 · 50%" value={<StatusPill tone="success">Paid</StatusPill>} />
        <Row
          label="Milestone 2 · 50%"
          value={<StatusPill tone="info">Waiting for client payment</StatusPill>}
        />
      </Card>
      <ul className="grid gap-1.5">
        <li className="bg-secondary flex items-center gap-2 rounded-lg px-3 py-2">
          <span className="bg-brand-text size-1.5 shrink-0 rounded-full" />
          <span className="truncate">New offer: Northline teaser</span>
        </li>
        <li className="bg-secondary flex items-center gap-2 rounded-lg px-3 py-2">
          <span className="bg-brand-text size-1.5 shrink-0 rounded-full" />
          <span className="truncate">Harbour Café launch reel approved</span>
        </li>
        <li className="text-muted-foreground flex items-center gap-2 px-3 py-1 text-xs">
          <Lock className="size-3 shrink-0" /> Client prices are never shown to editors
        </li>
      </ul>
    </Frame>
  );
}
