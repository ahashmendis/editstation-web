"use client";

import { useState } from "react";

import {
  AreaField,
  SelectField,
  StayForm,
  TextField,
} from "@/features/access/components/stay-form";

import {
  chargeExtraRoundAction,
  createScopeQuoteAction,
  offerAdjustmentAction,
  recordScopeQuoteAnswerAction,
  sendScopeQuoteAction,
  setAdjustmentRequiredAction,
  settleCancellationAction,
  withdrawAdjustmentAction,
} from "../admin-actions";
import { settlementEarnedLabel, type AdjustmentKind } from "../constants";
import { respondAdjustmentAction } from "../editor-actions";

/** Client form wrappers: render-prop children cannot cross the server/client boundary. */

export function SetAdjustmentRequiredForm({
  projectId,
  revisionId,
  required,
}: {
  projectId: string;
  revisionId: string;
  required: boolean;
}) {
  return (
    <StayForm
      action={setAdjustmentRequiredAction}
      submitLabel={
        required ? "Extra pay no longer required" : "Require extra pay before this round"
      }
      variant="outline"
    >
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="revisionId" value={revisionId} />
      <input type="hidden" name="required" value={required ? "no" : "yes"} />
    </StayForm>
  );
}

export function OfferAdjustmentForm({
  projectId,
  assignmentId,
  kind,
  revisionId,
  quoteId,
  currency,
}: {
  projectId: string;
  assignmentId: string;
  kind: AdjustmentKind;
  revisionId?: string;
  quoteId?: string;
  currency: string;
}) {
  const key = revisionId ?? quoteId ?? assignmentId;
  return (
    <StayForm action={offerAdjustmentAction} submitLabel="Offer extra pay" resetOnSuccess>
      {(state) => (
        <>
          <input type="hidden" name="projectId" value={projectId} />
          <input type="hidden" name="assignmentId" value={assignmentId} />
          <input type="hidden" name="kind" value={kind} />
          <input type="hidden" name="revisionId" value={revisionId ?? ""} />
          <input type="hidden" name="quoteId" value={quoteId ?? ""} />
          <TextField
            id={`offer-amount-${key}`}
            name="amount"
            label={`Extra pay for the editor (${currency})`}
            hint="Editor pay only, in the agreed currency. The agreed amount is not changed."
            inputMode="decimal"
            maxLength={14}
            state={state}
          />
          <AreaField
            id={`offer-note-${key}`}
            name="note"
            label="Note for the editor (optional)"
            hint="What the extra pay covers. The editor sees this."
            rows={2}
            maxLength={1000}
            state={state}
          />
        </>
      )}
    </StayForm>
  );
}

export function WithdrawAdjustmentForm({
  projectId,
  adjustmentId,
}: {
  projectId: string;
  adjustmentId: string;
}) {
  return (
    <StayForm
      action={withdrawAdjustmentAction}
      submitLabel="Withdraw offer"
      variant="outline"
      confirm="Withdraw this offer?"
    >
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="adjustmentId" value={adjustmentId} />
    </StayForm>
  );
}

export function ChargeExtraRoundForm({
  projectId,
  revisionId,
  minDate,
}: {
  projectId: string;
  revisionId: string;
  minDate: string;
}) {
  return (
    <StayForm action={chargeExtraRoundAction} submitLabel="Charge the client for this round">
      {(state) => (
        <>
          <input type="hidden" name="projectId" value={projectId} />
          <input type="hidden" name="revisionId" value={revisionId} />
          <TextField
            id={`charge-due-${revisionId}`}
            name="dueDate"
            label="Client due date"
            hint="Required; there is no default. The amount comes from the agreed terms."
            type="date"
            min={minDate}
            state={state}
          />
        </>
      )}
    </StayForm>
  );
}

export function CreateScopeQuoteForm({
  projectId,
  revisionId,
  currency,
}: {
  projectId: string;
  revisionId: string;
  currency: string;
}) {
  return (
    <StayForm action={createScopeQuoteAction} submitLabel="Draft scope quote" resetOnSuccess>
      {(state) => (
        <>
          <input type="hidden" name="projectId" value={projectId} />
          <input type="hidden" name="revisionId" value={revisionId} />
          <AreaField
            id={`quote-description-${revisionId}`}
            name="description"
            label="Scope change for the client"
            rows={3}
            maxLength={4000}
            state={state}
          />
          <div className="grid gap-3 sm:grid-cols-2">
            <TextField
              id={`quote-amount-${revisionId}`}
              name="amount"
              label="Client quote"
              hint="Admin only; editors never see it."
              inputMode="decimal"
              maxLength={14}
              state={state}
            />
            <TextField
              id={`quote-currency-${revisionId}`}
              name="currency"
              label="Currency"
              defaultValue={state.values?.currency ?? currency}
              maxLength={3}
              state={state}
            />
          </div>
        </>
      )}
    </StayForm>
  );
}

export function SendScopeQuoteForm({ projectId, quoteId }: { projectId: string; quoteId: string }) {
  return (
    <StayForm
      action={sendScopeQuoteAction}
      submitLabel="Mark as sent to the client"
      variant="outline"
    >
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="quoteId" value={quoteId} />
    </StayForm>
  );
}

export function ScopeQuoteAnswerForm({
  projectId,
  quoteId,
  minDate,
}: {
  projectId: string;
  quoteId: string;
  minDate: string;
}) {
  return (
    <StayForm action={recordScopeQuoteAnswerAction} submitLabel="Record the client's answer">
      {(state) => (
        <>
          <input type="hidden" name="projectId" value={projectId} />
          <input type="hidden" name="quoteId" value={quoteId} />
          <SelectField
            id={`quote-answer-${quoteId}`}
            name="accepted"
            label="Client's answer"
            defaultValue="yes"
            state={state}
          >
            <option value="yes">Accepted</option>
            <option value="no">Declined</option>
          </SelectField>
          <TextField
            id={`quote-due-${quoteId}`}
            name="dueDate"
            label="Client due date (when accepted)"
            hint="Required for an acceptance; there is no default."
            type="date"
            min={minDate}
            state={state}
          />
        </>
      )}
    </StayForm>
  );
}

export function SettleCancellationForm({
  projectId,
  currency,
  proposed,
}: {
  projectId: string;
  currency: string;
  proposed: number;
}) {
  // The reason becomes required once the admin types a changed earned amount.
  const [changed, setChanged] = useState(false);
  return (
    <StayForm
      action={settleCancellationAction}
      submitLabel="Cancel the project and settle"
      variant="destructive"
      confirm="Cancel this project and record the settlement? This cannot be undone."
    >
      {(state) => (
        <div
          className="grid gap-3"
          onChange={(event) => {
            const target = event.target as HTMLInputElement;
            if (target.name === "adjustedEarned") setChanged(target.value.trim() !== "");
          }}
        >
          <input type="hidden" name="projectId" value={projectId} />
          <TextField
            id="settle-earned"
            name="adjustedEarned"
            label={settlementEarnedLabel(proposed, currency)}
            hint={`Leave empty to use the agreed schedule. Amount in ${currency}.`}
            inputMode="decimal"
            maxLength={14}
            state={state}
          />
          <AreaField
            id="settle-reason"
            name="reason"
            label="Reason for a changed amount"
            hint="Required when you change the editor's earned amount. Admins only."
            rows={2}
            maxLength={2000}
            ariaRequired={changed || Boolean(state.values?.adjustedEarned)}
            state={state}
          />
        </div>
      )}
    </StayForm>
  );
}

export function RespondAdjustmentForms({
  projectId,
  adjustmentId,
}: {
  projectId: string;
  adjustmentId: string;
}) {
  return (
    <div className="flex flex-wrap gap-2">
      <StayForm action={respondAdjustmentAction} submitLabel="Accept extra pay">
        <input type="hidden" name="projectId" value={projectId} />
        <input type="hidden" name="adjustmentId" value={adjustmentId} />
        <input type="hidden" name="response" value="accept" />
      </StayForm>
      <StayForm
        action={respondAdjustmentAction}
        submitLabel="Decline"
        variant="outline"
        confirm="Decline this offer?"
      >
        <input type="hidden" name="projectId" value={projectId} />
        <input type="hidden" name="adjustmentId" value={adjustmentId} />
        <input type="hidden" name="response" value="decline" />
      </StayForm>
    </div>
  );
}
