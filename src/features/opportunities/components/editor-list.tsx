import Link from "next/link";

import { EmptyState } from "@/components/empty-state";
import { StatusPill } from "@/components/status-pill";
import { buttonVariants } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { formatMoney } from "@/features/access/constants";
import { formatDateTime } from "@/features/applications/components/status-badge";

import {
  INTEREST_STATUS_LABEL,
  INTEREST_STATUS_TONE,
  MAX_LIVE_INTERESTS,
  type InterestStatus,
} from "../constants";
import type { EditorOpportunity } from "../queries";
import { RegisterInterestForm, WithdrawInterestForm } from "./forms";

/** The editor's list: summary fields only (the database projection), never client data. */
export function EditorOpportunityList({ rows }: { rows: EditorOpportunity[] }) {
  if (rows.length === 0) {
    return (
      <EmptyState title="No open opportunities right now">
        When Lenscape publishes a project for active editors it appears here. You can still be
        invited to projects directly.
      </EmptyState>
    );
  }
  // The limit counts only interests on opportunities still taking interest (as the database does).
  const live = rows.filter(
    (r) => r.interest_status === "interested" && r.accepting_interest,
  ).length;
  return (
    <div className="grid gap-4">
      <p className="text-muted-foreground text-sm">
        You are interested in {live} of at most {MAX_LIVE_INTERESTS} opportunities at a time.
      </p>
      <ul className="grid gap-4">
        {rows.map((r) => (
          <li key={r.opportunity_id}>
            <OpportunityCard row={r} />
          </li>
        ))}
      </ul>
    </div>
  );
}

function OpportunityCard({ row: r }: { row: EditorOpportunity }) {
  const status = r.interest_status as InterestStatus | null;
  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-center gap-2">
          <CardTitle className="break-words">{r.title}</CardTitle>
          {status ? (
            <StatusPill tone={INTEREST_STATUS_TONE[status]}>
              {INTEREST_STATUS_LABEL[status]}
            </StatusPill>
          ) : null}
          {!r.accepting_interest && !status ? <StatusPill tone="neutral">Closed</StatusPill> : null}
        </div>
        {r.service_type ? <CardDescription>{r.service_type}</CardDescription> : null}
      </CardHeader>
      <CardContent className="grid gap-4">
        <p className="text-sm break-words whitespace-pre-line">{r.deliverables_summary}</p>
        <dl className="grid gap-x-4 gap-y-1 text-sm sm:grid-cols-[auto_1fr]">
          <dt className="text-muted-foreground">Deadline</dt>
          <dd>{r.deadline ?? "Not set"}</dd>
          <dt className="text-muted-foreground">Pay</dt>
          <dd>
            {r.shown_pay_amount !== null
              ? formatMoney(r.shown_pay_amount, r.shown_pay_currency)
              : "Not shown: you may propose a rate"}
          </dd>
          {r.format_notes ? (
            <>
              <dt className="text-muted-foreground">Notes</dt>
              <dd className="break-words whitespace-pre-line">{r.format_notes}</dd>
            </>
          ) : null}
          {r.closes_at && r.accepting_interest ? (
            <>
              <dt className="text-muted-foreground">Interest closes</dt>
              <dd>{formatDateTime(r.closes_at)}</dd>
            </>
          ) : null}
        </dl>
        <InterestSection row={r} status={status} />
      </CardContent>
    </Card>
  );
}

function InterestSection({
  row: r,
  status,
}: {
  row: EditorOpportunity;
  status: InterestStatus | null;
}) {
  const yours =
    r.proposed_amount !== null || r.note ? (
      <p className="text-muted-foreground text-sm break-words">
        Your interest
        {r.proposed_amount !== null
          ? `: proposed ${formatMoney(r.proposed_amount, r.proposed_currency)}`
          : ""}
        {r.note ? ` · “${r.note}”` : ""}
      </p>
    ) : null;

  if (status === "interested") {
    return (
      <div className="grid gap-3">
        {yours}
        <WithdrawInterestForm interestId={r.interest_id as string} />
      </div>
    );
  }
  if (status === "selected") {
    return (
      <div className="grid gap-3">
        <p className="text-sm">You were chosen. Answer the offer on the project page.</p>
        {r.selected_project_id ? (
          <Link
            href={`/editor/projects/${r.selected_project_id}`}
            className={buttonVariants({ className: "justify-self-start" })}
          >
            Open the project
          </Link>
        ) : null}
      </div>
    );
  }
  if (status === "not_selected") {
    return (
      <p className="text-muted-foreground text-sm">
        Another editor was chosen or the opportunity closed. Thank you for your interest.
      </p>
    );
  }
  if (!r.accepting_interest) {
    return (
      <p className="text-muted-foreground text-sm">
        This opportunity is no longer taking interest.
      </p>
    );
  }
  return (
    <div className="grid gap-2">
      {status === "withdrawn" ? (
        <p className="text-muted-foreground text-sm">
          You withdrew your interest. You can register again.
        </p>
      ) : null}
      <RegisterInterestForm
        opportunityId={r.opportunity_id}
        currency={r.shown_pay_currency ?? "LKR"}
        payShown={r.shown_pay_amount !== null}
      />
    </div>
  );
}
