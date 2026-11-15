import type { ReactNode } from "react";

import { StatusPill } from "@/components/status-pill";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Money } from "@/features/payments/components/money";
import { REVISION_TYPE_LABEL } from "@/features/submissions/constants";
import type { RevisionRow } from "@/features/submissions/queries";

import {
  ADJUSTMENT_KIND_LABEL,
  ADJUSTMENT_STATUS_LABEL,
  ADJUSTMENT_STATUS_TONE,
  EDITOR_ADJUSTMENT_STATUS_LABEL,
  SCOPE_QUOTE_STATUS_LABEL,
  SCOPE_QUOTE_STATUS_TONE,
  SETTLEMENT_STAGE_LABEL,
  isLiveAdjustment,
} from "../constants";
import type {
  AdminAdjustment,
  AdminAdjustmentData,
  EditorAdjustment,
  Settlement,
  SettlementPreview,
} from "../queries";
import {
  ChargeExtraRoundForm,
  CreateScopeQuoteForm,
  OfferAdjustmentForm,
  RespondAdjustmentForms,
  ScopeQuoteAnswerForm,
  SendScopeQuoteForm,
  SetAdjustmentRequiredForm,
  SettleCancellationForm,
  WithdrawAdjustmentForm,
} from "./forms";

function OfferList({
  projectId,
  offers,
  locked,
}: {
  projectId: string;
  offers: AdminAdjustment[];
  locked: boolean;
}) {
  if (offers.length === 0) return <p className="text-muted-foreground text-sm">No offers yet.</p>;
  return (
    <ul className="grid gap-3">
      {offers.map((o) => (
        <li key={o.id} className="grid gap-1 text-sm">
          <div className="flex flex-wrap items-center gap-2">
            <span className="font-medium">
              <Money amount={o.amount} currency={o.currency} />
            </span>
            <span className="text-muted-foreground">{ADJUSTMENT_KIND_LABEL[o.kind]}</span>
            <StatusPill tone={ADJUSTMENT_STATUS_TONE[o.status]}>
              {ADJUSTMENT_STATUS_LABEL[o.status]}
            </StatusPill>
          </div>
          {o.note ? <p className="whitespace-pre-wrap">{o.note}</p> : null}
          {o.status === "offered" && !locked ? (
            <WithdrawAdjustmentForm projectId={projectId} adjustmentId={o.id} />
          ) : null}
          {o.status === "declined" ? (
            <p className="text-muted-foreground">
              Declined: make a new offer, clear the requirement, or reassign the project.
            </p>
          ) : null}
        </li>
      ))}
    </ul>
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="grid gap-3 border-t pt-4 first:border-t-0 first:pt-0">
      <h3 className="text-sm font-medium">{title}</h3>
      {children}
    </section>
  );
}

/**
 * Admin: extra pay and client charges for the open change requests (spec §4.4, F2 a, b, d; call 5).
 * The database enforces every gate; this panel only offers the actions.
 */
export function AdminExtraPayPanel({
  projectId,
  assignmentId,
  currency,
  clientCurrency,
  revisions,
  data,
  today,
  locked,
}: {
  projectId: string;
  assignmentId: string | null;
  currency: string;
  clientCurrency: string;
  revisions: RevisionRow[];
  data: AdminAdjustmentData;
  today: string;
  locked: boolean;
}) {
  const open = revisions.filter(
    (r) =>
      (r.type === "client_revision" || r.type === "scope_change") &&
      ["requested", "acknowledged", "in_progress", "disputed"].includes(r.status),
  );
  if (open.length === 0) return null;
  return (
    <Card>
      <CardHeader>
        <CardTitle>Extra pay and client charges</CardTitle>
        <CardDescription>
          Extra editor pay is agreed before the change begins: the editor cannot start a marked
          round or a scope change until they accept. A scope change also needs the client&apos;s
          accepted quote.
        </CardDescription>
      </CardHeader>
      <CardContent className="grid gap-4">
        {open.map((r) => {
          const notBegun = r.status === "requested" || r.status === "disputed";
          const charge = data.roundCharges.find((c) => c.revisionRequestId === r.id);
          const quote = data.quotes.find(
            (q) => q.revisionRequestId === r.id && q.status !== "declined",
          );
          const declinedQuotes = data.quotes.filter(
            (q) => q.revisionRequestId === r.id && q.status === "declined",
          ).length;
          const offers = data.adjustments.filter(
            (a) =>
              a.revisionRequestId === r.id ||
              (a.scopeQuoteId !== null &&
                data.quotes.some((q) => q.id === a.scopeQuoteId && q.revisionRequestId === r.id)),
          );
          const live = offers.some((o) => isLiveAdjustment(o.status));
          return (
            <Section
              key={r.id}
              title={`${REVISION_TYPE_LABEL[r.type]}${r.roundNumber ? ` · round ${r.roundNumber}` : ""}`}
            >
              {r.type === "client_revision" ? (
                <>
                  <p className="text-sm">
                    Extra editor pay required:{" "}
                    <strong>{r.adjustmentRequired ? "Yes" : "No"}</strong>
                  </p>
                  {!locked && (notBegun || r.adjustmentRequired) ? (
                    <SetAdjustmentRequiredForm
                      projectId={projectId}
                      revisionId={r.id}
                      required={r.adjustmentRequired}
                    />
                  ) : null}
                  {r.beyondAllowance ? (
                    charge ? (
                      <p className="text-sm">
                        Client charged <Money amount={charge.amount} currency={charge.currency} />,
                        due {charge.dueDate ?? "—"}.
                      </p>
                    ) : !locked ? (
                      <ChargeExtraRoundForm
                        projectId={projectId}
                        revisionId={r.id}
                        minDate={today}
                      />
                    ) : null
                  ) : null}
                </>
              ) : (
                <>
                  {quote ? (
                    <div className="grid gap-2 text-sm">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="font-medium">Client quote</span>
                        <Money amount={quote.amount} currency={quote.currency} />
                        <StatusPill tone={SCOPE_QUOTE_STATUS_TONE[quote.status]}>
                          {SCOPE_QUOTE_STATUS_LABEL[quote.status]}
                        </StatusPill>
                      </div>
                      <p className="whitespace-pre-wrap">{quote.description}</p>
                      {!locked && quote.status === "drafted" ? (
                        <SendScopeQuoteForm projectId={projectId} quoteId={quote.id} />
                      ) : null}
                      {!locked && quote.status === "sent" ? (
                        <ScopeQuoteAnswerForm
                          projectId={projectId}
                          quoteId={quote.id}
                          minDate={today}
                        />
                      ) : null}
                    </div>
                  ) : !locked && notBegun ? (
                    <>
                      {declinedQuotes > 0 ? (
                        <p className="text-muted-foreground text-sm">
                          The client declined {declinedQuotes === 1 ? "a quote" : "earlier quotes"}.
                        </p>
                      ) : null}
                      <CreateScopeQuoteForm
                        projectId={projectId}
                        revisionId={r.id}
                        currency={clientCurrency}
                      />
                    </>
                  ) : null}
                </>
              )}
              {r.type === "scope_change" || r.adjustmentRequired ? (
                <div className="grid gap-3">
                  <h4 className="text-sm font-medium">Extra pay offers</h4>
                  <OfferList projectId={projectId} offers={offers} locked={locked} />
                  {!locked && notBegun && !live && assignmentId ? (
                    r.type === "scope_change" ? (
                      quote ? (
                        <OfferAdjustmentForm
                          projectId={projectId}
                          assignmentId={assignmentId}
                          kind="scope_change"
                          quoteId={quote.id}
                          currency={currency}
                        />
                      ) : (
                        <p className="text-muted-foreground text-sm">
                          Draft the client quote first, then offer the editor&apos;s extra pay.
                        </p>
                      )
                    ) : (
                      <OfferAdjustmentForm
                        projectId={projectId}
                        assignmentId={assignmentId}
                        kind="extra_round"
                        revisionId={r.id}
                        currency={currency}
                      />
                    )
                  ) : null}
                </div>
              ) : null}
            </Section>
          );
        })}
      </CardContent>
    </Card>
  );
}

function Row({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="grid gap-0.5">
      <dt className="text-muted-foreground text-xs">{label}</dt>
      <dd className="text-sm">{children}</dd>
    </div>
  );
}

function ClientFigures({
  f,
}: {
  f: Pick<
    Settlement,
    | "clientBase"
    | "clientCurrency"
    | "clientReceived"
    | "clientCharge"
    | "clientRefund"
    | "clientOwes"
    | "clientChargePercent"
  >;
}) {
  const c = f.clientCurrency ?? "LKR";
  return (
    <dl className="grid gap-3 sm:grid-cols-3">
      <Row label="Client price (deposit + balance)">
        <Money amount={f.clientBase} currency={c} />
      </Row>
      <Row label="Verified client money received">
        <Money amount={f.clientReceived} currency={c} />
      </Row>
      <Row label={`Client charge (${f.clientChargePercent}%)`}>
        <Money amount={f.clientCharge} currency={c} />
      </Row>
      <Row label="Refund to the client">
        <Money amount={f.clientRefund} currency={c} />
      </Row>
      {f.clientOwes > 0 ? (
        <Row label="Still owed by the client (recorded only)">
          <Money amount={f.clientOwes} currency={c} />
        </Row>
      ) : null}
    </dl>
  );
}

/**
 * Admin: cancellation settlement (spec §4.6, F2 c, KB9a-3). Shows the proposed figures from the
 * agreed schedule, lets the admin change the editor's earned amount with a reason, and confirms.
 * After settling it shows the record; refund rows appear in Client billing to be verified.
 */
export function CancellationSettlementPanel({
  projectId,
  settlement,
  preview,
  previewMessage,
  cancelledAssignmentId,
  cancellationOffers,
  archived,
}: {
  projectId: string;
  settlement: Settlement | null;
  preview: SettlementPreview | null;
  previewMessage: string | null;
  cancelledAssignmentId: string | null;
  cancellationOffers: AdminAdjustment[];
  archived: boolean;
}) {
  if (!settlement && !preview && !previewMessage) return null;
  return (
    <Card>
      <CardHeader>
        <CardTitle>Cancellation settlement</CardTitle>
        <CardDescription>
          The editor is paid for the work done under the agreed cancellation schedule; unpaid
          milestones are cancelled, and the client&apos;s unused money is refunded. Refunds are
          verified in Client billing like any transfer.
        </CardDescription>
      </CardHeader>
      <CardContent className="grid gap-4">
        {settlement ? (
          <>
            <dl className="grid gap-3 sm:grid-cols-3">
              <Row label="Stage at cancellation">
                {SETTLEMENT_STAGE_LABEL[settlement.stage] ?? settlement.stage}
              </Row>
              <Row
                label={`Schedule (${settlement.editorEarnedPercent}% of agreed pay + extra pay)`}
              >
                <Money
                  amount={settlement.computedEditorEarned}
                  currency={settlement.editorCurrency}
                />
              </Row>
              <Row label="Editor earned">
                <Money amount={settlement.editorEarned} currency={settlement.editorCurrency} />
              </Row>
              <Row label="Accepted extra pay">
                <Money amount={settlement.editorExtraPay} currency={settlement.editorCurrency} />
              </Row>
              <Row label="Milestones paid before the settlement">
                <Money amount={settlement.editorPaidBefore} currency={settlement.editorCurrency} />
              </Row>
              <Row label="Settlement payment">
                <Money
                  amount={settlement.editorSettlementAmount}
                  currency={settlement.editorCurrency}
                />
              </Row>
              <Row label="Overpaid (reversed; recover outside the app)">
                <Money amount={settlement.editorOverpayment} currency={settlement.editorCurrency} />
              </Row>
              <Row label="Unpaid rows cancelled">{settlement.cancelledPaymentCount}</Row>
            </dl>
            {settlement.adjustmentReason ? (
              <p className="text-sm whitespace-pre-wrap">
                <span className="font-medium">Reason for the changed amount: </span>
                {settlement.adjustmentReason}
              </p>
            ) : null}
            <ClientFigures f={settlement} />
            {cancelledAssignmentId ? (
              <div className="grid gap-3">
                <h3 className="text-sm font-medium">Extra cancellation pay</h3>
                <OfferList projectId={projectId} offers={cancellationOffers} locked={archived} />
                {!archived && !cancellationOffers.some((o) => o.status === "offered") ? (
                  <OfferAdjustmentForm
                    projectId={projectId}
                    assignmentId={cancelledAssignmentId}
                    kind="cancellation"
                    currency={settlement.editorCurrency}
                  />
                ) : null}
              </div>
            ) : null}
          </>
        ) : preview ? (
          <>
            <dl className="grid gap-3 sm:grid-cols-3">
              <Row label="Stage now">{SETTLEMENT_STAGE_LABEL[preview.stage] ?? preview.stage}</Row>
              <Row label="Agreed editor pay">
                <Money amount={preview.agreedAmount} currency={preview.editorCurrency} />
              </Row>
              <Row label={`Proposed editor earned (${preview.editorEarnedPercent}% + extra pay)`}>
                <Money amount={preview.computedEditorEarned} currency={preview.editorCurrency} />
              </Row>
              <Row label="Accepted extra pay (earned in full, stays payable)">
                <Money amount={preview.editorExtraPay} currency={preview.editorCurrency} />
              </Row>
              <Row label="Milestones already paid">
                <Money amount={preview.editorPaidBefore} currency={preview.editorCurrency} />
              </Row>
              <Row label="Settlement payment">
                <Money amount={preview.editorSettlementAmount} currency={preview.editorCurrency} />
              </Row>
              <Row label="Overpaid (would be reversed)">
                <Money amount={preview.editorOverpayment} currency={preview.editorCurrency} />
              </Row>
              <Row label="Unpaid rows to cancel">{preview.unpaidCount}</Row>
            </dl>
            <ClientFigures f={preview} />
            {!archived ? (
              <SettleCancellationForm
                projectId={projectId}
                currency={preview.editorCurrency}
                proposed={preview.computedEditorEarned}
              />
            ) : null}
          </>
        ) : (
          <p className="text-sm">{previewMessage}</p>
        )}
      </CardContent>
    </Card>
  );
}

/**
 * Editor: extra pay offers, with Accept / Decline for open ones. On the earnings page it lists the
 * open offers of every project (showProject).
 */
export function EditorAdjustmentOffers({
  offers,
  showProject = false,
}: {
  offers: EditorAdjustment[];
  showProject?: boolean;
}) {
  if (offers.length === 0) return null;
  return (
    <Card>
      <CardHeader>
        <CardTitle>Extra pay offers</CardTitle>
        <CardDescription>
          Extra pay for extra work is agreed before the work begins. Accepting adds it to your
          earnings; your agreed pay is not changed.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <ul className="grid gap-4">
          {offers.map((o) => (
            <li key={o.id} className="grid gap-2 text-sm">
              {showProject ? <p className="font-medium break-words">{o.projectTitle}</p> : null}
              <div className="flex flex-wrap items-center gap-2">
                <span className="font-medium">{ADJUSTMENT_KIND_LABEL[o.kind]}</span>
                <span className="text-base font-semibold">
                  <Money amount={o.amount} currency={o.currency} />
                </span>
                <StatusPill tone={ADJUSTMENT_STATUS_TONE[o.status]}>
                  {EDITOR_ADJUSTMENT_STATUS_LABEL[o.status]}
                </StatusPill>
              </div>
              {o.note ? <p className="whitespace-pre-wrap">{o.note}</p> : null}
              {o.status === "offered" ? (
                <RespondAdjustmentForms projectId={o.projectId} adjustmentId={o.id} />
              ) : null}
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  );
}
