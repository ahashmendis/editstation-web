"use client";

import {
  AreaField,
  SelectField,
  StayForm,
  TextField,
} from "@/features/access/components/stay-form";

import { registerInterestAction, withdrawInterestAction } from "../actions";
import {
  closeOpportunityAction,
  publishOpportunityAction,
  selectEditorAction,
  updateOpportunityAction,
} from "../admin-actions";

/** Client form wrappers: render-prop children cannot cross the server/client boundary. */

// ---------------------------------------------------------------------------
// Editor
// ---------------------------------------------------------------------------
export function RegisterInterestForm({
  opportunityId,
  currency,
  payShown,
}: {
  opportunityId: string;
  currency: string;
  payShown: boolean;
}) {
  const p = `interest-${opportunityId}`;
  return (
    <StayForm action={registerInterestAction} submitLabel="Register interest">
      {(state) => (
        <>
          <input type="hidden" name="opportunityId" value={opportunityId} />
          <div className="grid gap-3 sm:grid-cols-2">
            <TextField
              id={`${p}-amount`}
              name="proposedAmount"
              label="Your proposed rate (optional)"
              inputMode="decimal"
              hint={
                payShown
                  ? "Only if you would ask for a different rate. Pay is agreed in the offer."
                  : "A signal only. Pay is agreed in the offer if you are chosen."
              }
              state={state}
            />
            <TextField
              id={`${p}-currency`}
              name="proposedCurrency"
              label="Currency"
              defaultValue={state.values?.proposedCurrency ?? currency}
              maxLength={3}
              state={state}
            />
          </div>
          <AreaField
            id={`${p}-note`}
            name="note"
            label="Short note (optional)"
            hint="For example similar work you have done. At most 500 characters."
            rows={2}
            maxLength={500}
            state={state}
          />
        </>
      )}
    </StayForm>
  );
}

export function WithdrawInterestForm({ interestId }: { interestId: string }) {
  return (
    <StayForm
      action={withdrawInterestAction}
      submitLabel="Withdraw interest"
      variant="outline"
      confirm="Withdraw your interest?"
    >
      <input type="hidden" name="interestId" value={interestId} />
    </StayForm>
  );
}

// ---------------------------------------------------------------------------
// Admin
// ---------------------------------------------------------------------------
export type SummaryDefaults = {
  title: string;
  deliverablesSummary: string;
  serviceTypeCode: string;
  deadline: string;
  formatNotes: string;
  showPay: boolean;
  payAmount: string;
  payCurrency: string;
  closesOn: string;
};

export function OpportunitySummaryForm({
  projectId,
  opportunityId,
  services,
  defaults,
}: {
  projectId: string;
  /** Present when editing an open opportunity; absent when publishing (or reopening). */
  opportunityId?: string;
  services: { code: string; label: string }[];
  defaults: SummaryDefaults;
}) {
  const p = `opportunity-${projectId}`;
  return (
    <StayForm
      action={opportunityId ? updateOpportunityAction : publishOpportunityAction}
      submitLabel={opportunityId ? "Save summary" : "Publish to active editors"}
      confirm={opportunityId ? undefined : "Every active editor will see this summary. Publish it?"}
    >
      {(state) => {
        const v = state.values;
        return (
          <>
            <input type="hidden" name="projectId" value={projectId} />
            {opportunityId ? (
              <input type="hidden" name="opportunityId" value={opportunityId} />
            ) : null}
            <TextField
              id={`${p}-title`}
              name="title"
              label="Title editors see"
              hint="Neutral: never the client's or company's name."
              maxLength={120}
              defaultValue={v?.title ?? defaults.title}
              state={state}
            />
            <AreaField
              id={`${p}-deliverables`}
              name="deliverablesSummary"
              label="Deliverables summary"
              hint="Written for editors. Do not paste the brief, links or client details."
              rows={3}
              maxLength={1000}
              defaultValue={v?.deliverablesSummary ?? defaults.deliverablesSummary}
              state={state}
            />
            <div className="grid gap-3 sm:grid-cols-2">
              <SelectField
                id={`${p}-service`}
                name="serviceTypeCode"
                label="Service type (optional)"
                defaultValue={v?.serviceTypeCode ?? defaults.serviceTypeCode}
                state={state}
              >
                <option value="">Not shown</option>
                {services.map((s) => (
                  <option key={s.code} value={s.code}>
                    {s.label}
                  </option>
                ))}
              </SelectField>
              <TextField
                id={`${p}-deadline`}
                name="deadline"
                label="Deadline (optional)"
                type="date"
                defaultValue={v?.deadline ?? defaults.deadline}
                state={state}
              />
            </div>
            <AreaField
              id={`${p}-format`}
              name="formatNotes"
              label="Language or format notes (optional)"
              rows={2}
              maxLength={1000}
              defaultValue={v?.formatNotes ?? defaults.formatNotes}
              state={state}
            />
            <label className="flex min-h-11 items-center gap-2 text-sm">
              <input
                type="checkbox"
                name="showPay"
                value="on"
                className="size-4"
                defaultChecked={v ? v.showPay === "on" : defaults.showPay}
              />
              Show pay to editors (otherwise hidden; editors may propose a rate)
            </label>
            <div className="grid gap-3 sm:grid-cols-2">
              <TextField
                id={`${p}-pay`}
                name="payAmount"
                label="Pay shown (editor pay, never the client price)"
                inputMode="decimal"
                defaultValue={v?.payAmount ?? defaults.payAmount}
                state={state}
              />
              <TextField
                id={`${p}-currency`}
                name="payCurrency"
                label="Currency"
                maxLength={3}
                defaultValue={v?.payCurrency ?? defaults.payCurrency}
                state={state}
              />
            </div>
            <TextField
              id={`${p}-closes`}
              name="closesOn"
              label="Stop taking interest after (optional)"
              type="date"
              hint="Interest closes at the end of this day (Sri Lanka time). You can still choose an editor."
              defaultValue={v?.closesOn ?? defaults.closesOn}
              state={state}
            />
          </>
        );
      }}
    </StayForm>
  );
}

export function CloseOpportunityForm({
  projectId,
  opportunityId,
}: {
  projectId: string;
  opportunityId: string;
}) {
  return (
    <StayForm
      action={closeOpportunityAction}
      submitLabel="Close opportunity"
      variant="outline"
      confirm="Interested editors will see Not selected."
    >
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="opportunityId" value={opportunityId} />
    </StayForm>
  );
}

/** The existing offer form's fields, prefilled; submitting chooses this editor. */
export function SelectEditorForm({
  projectId,
  interestId,
  defaultAmount,
  defaultCurrency,
}: {
  projectId: string;
  interestId: string;
  defaultAmount: string;
  defaultCurrency: string;
}) {
  const p = `select-${interestId}`;
  return (
    <StayForm
      action={selectEditorAction}
      submitLabel="Choose this editor"
      confirm="Send this offer? Every other interested editor will see Not selected."
    >
      {(state) => (
        <>
          <input type="hidden" name="projectId" value={projectId} />
          <input type="hidden" name="interestId" value={interestId} />
          <div className="grid gap-3 sm:grid-cols-2">
            <TextField
              id={`${p}-amount`}
              name="amount"
              label="Pay offered"
              inputMode="decimal"
              defaultValue={state.values?.amount ?? defaultAmount}
              hint="Your offer. The proposed rate never sets pay."
              state={state}
            />
            <TextField
              id={`${p}-currency`}
              name="currency"
              label="Currency"
              maxLength={3}
              defaultValue={state.values?.currency ?? defaultCurrency}
              state={state}
            />
          </div>
          <AreaField
            id={`${p}-message`}
            name="message"
            label="Message (optional)"
            rows={2}
            maxLength={2000}
            state={state}
          />
        </>
      )}
    </StayForm>
  );
}
