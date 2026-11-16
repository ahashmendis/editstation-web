import { EmptyState } from "@/components/empty-state";
import { StatusPill } from "@/components/status-pill";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { formatMoney } from "@/features/access/constants";
import { formatDateTime } from "@/features/applications/components/status-badge";

import {
  dateFromClosesAt,
  INTEREST_STATUS_LABEL,
  INTEREST_STATUS_TONE,
  OPPORTUNITY_STATUS_LABEL,
  OPPORTUNITY_STATUS_TONE,
  type InterestStatus,
  type OpportunityStatus,
} from "../constants";
import type { AdminInterest, AdminOpportunity } from "../queries";
import {
  CloseOpportunityForm,
  OpportunitySummaryForm,
  SelectEditorForm,
  type SummaryDefaults,
} from "./forms";

const str = (value: string | number | null | undefined) =>
  value === null || value === undefined ? "" : String(value);

/**
 * "Open opportunity" card on the admin project page: publish a summary for every active editor,
 * see who is interested (with proposed rates), choose one (the existing offer), or close it.
 * Direct invitations in the Editors card still work without publishing.
 */
export function AdminOpportunityCard({
  projectId,
  publishable,
  opportunity,
  interests,
  services,
  project,
}: {
  projectId: string;
  /** The project is open and not archived (the database checks again). */
  publishable: boolean;
  opportunity: AdminOpportunity | null;
  interests: AdminInterest[];
  services: { code: string; label: string }[];
  project: {
    serviceTypeCode: string | null;
    deadline: string | null;
    /** The editor pay set on the project (never the client price), used to prefill the offer. */
    proposedAmount: number | null;
    currency: string | null;
  };
}) {
  const status = (opportunity?.status ?? null) as OpportunityStatus | null;
  const open = status === "open";
  const defaults: SummaryDefaults = opportunity
    ? {
        title: opportunity.title,
        deliverablesSummary: opportunity.deliverables_summary,
        serviceTypeCode: str(opportunity.service_type_code),
        deadline: str(opportunity.deadline),
        formatNotes: str(opportunity.format_notes),
        showPay: opportunity.shown_pay_amount !== null,
        payAmount: str(opportunity.shown_pay_amount),
        payCurrency: str(opportunity.shown_pay_currency) || str(project.currency) || "LKR",
        closesOn: dateFromClosesAt(opportunity.closes_at),
      }
    : {
        title: "",
        deliverablesSummary: "",
        serviceTypeCode: str(project.serviceTypeCode),
        deadline: str(project.deadline),
        formatNotes: "",
        showPay: false,
        payAmount: "",
        payCurrency: str(project.currency) || "LKR",
        closesOn: "",
      };
  const live = interests.filter((i) => i.status === "interested");

  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-center gap-3">
          <CardTitle>Open opportunity</CardTitle>
          {status ? (
            <StatusPill tone={OPPORTUNITY_STATUS_TONE[status]}>
              {OPPORTUNITY_STATUS_LABEL[status]}
            </StatusPill>
          ) : (
            <StatusPill tone="neutral">Not published</StatusPill>
          )}
        </div>
        <CardDescription>
          Publish a short summary every active editor can see and register interest in. Write it for
          editors: no client name, client price, brief text, files or links. Choosing an editor
          sends them the usual offer. You can still invite editors directly below.
        </CardDescription>
      </CardHeader>
      <CardContent className="grid gap-6">
        {opportunity && !open ? (
          <p className="text-muted-foreground text-sm">
            {status === "filled" ? "An editor was chosen" : "Closed"}
            {opportunity.closed_at ? ` on ${formatDateTime(opportunity.closed_at)}` : ""}.
            {status === "filled" ? " Follow the offer in the Editors card." : ""}
            {publishable
              ? status === "filled"
                ? " If the offer falls through, publishing again reopens it."
                : " Publishing again reopens it with the summary below."
              : ""}
          </p>
        ) : null}

        {open || publishable ? (
          <OpportunitySummaryForm
            projectId={projectId}
            opportunityId={open ? opportunity?.id : undefined}
            services={services}
            defaults={defaults}
          />
        ) : !opportunity ? (
          <EmptyState title="Only an open project can be published">
            Open the project first. Editors never see drafts.
          </EmptyState>
        ) : null}

        {opportunity ? (
          <section className="grid gap-3" aria-labelledby={`interests-${opportunity.id}`}>
            <h3 id={`interests-${opportunity.id}`} className="text-sm font-medium">
              Interested editors ({live.length})
            </h3>
            {interests.length === 0 ? (
              <EmptyState title="No interest yet" />
            ) : (
              <ul className="grid gap-4">
                {interests.map((i) => (
                  <li
                    key={i.interest_id}
                    className="grid gap-2 border-t pt-4 first:border-t-0 first:pt-0"
                  >
                    <InterestRow
                      interest={i}
                      projectId={projectId}
                      canChoose={open && publishable}
                      defaultAmount={str(opportunity.shown_pay_amount ?? project.proposedAmount)}
                      defaultCurrency={opportunity.shown_pay_currency ?? project.currency ?? "LKR"}
                    />
                  </li>
                ))}
              </ul>
            )}
          </section>
        ) : null}

        {open && opportunity ? (
          <CloseOpportunityForm projectId={projectId} opportunityId={opportunity.id} />
        ) : null}
      </CardContent>
    </Card>
  );
}

function InterestRow({
  interest: i,
  projectId,
  canChoose,
  defaultAmount,
  defaultCurrency,
}: {
  interest: AdminInterest;
  projectId: string;
  canChoose: boolean;
  defaultAmount: string;
  defaultCurrency: string;
}) {
  const status = i.status as InterestStatus;
  const active = i.editor_access_status === "active";
  return (
    <>
      <div className="flex flex-wrap items-center gap-2">
        <span className="font-medium break-words">{i.editor_name ?? "Editor"}</span>
        <StatusPill tone={INTEREST_STATUS_TONE[status]}>{INTEREST_STATUS_LABEL[status]}</StatusPill>
        {!active ? <StatusPill tone="warning">Access not active</StatusPill> : null}
      </div>
      <p className="text-muted-foreground text-sm">
        {i.proposed_amount !== null
          ? `Proposed ${formatMoney(i.proposed_amount, i.proposed_currency)} (a signal only)`
          : "No rate proposed"}
        {" · "}
        {formatDateTime(i.created_at)}
      </p>
      {i.note ? <p className="text-sm break-words whitespace-pre-line">{i.note}</p> : null}
      {canChoose && status === "interested" && active ? (
        <SelectEditorForm
          projectId={projectId}
          interestId={i.interest_id}
          defaultAmount={defaultAmount}
          defaultCurrency={defaultCurrency}
        />
      ) : null}
    </>
  );
}
