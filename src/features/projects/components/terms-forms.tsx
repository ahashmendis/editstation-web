"use client";

import { useActionState, useTransition } from "react";

import { Button } from "@/components/ui/button";
import { Field, FormMessage, TextareaField } from "@/features/authentication/components/form-parts";
import { initialFormState, type FormState } from "@/features/authentication/schemas";

import { saveTermsDraftAction } from "../admin-actions";
import { TERMS_STAGE_LABEL } from "../constants";
import { TERMS_STAGES, type TermsStage } from "../schemas";

export type TermsDefaults = {
  includedRounds: string;
  extraRoundCharge: string;
  chargeCurrency: string;
  depositDays: string;
  balanceDays: string;
  editorPayDays: string;
  lateBalanceDays: string;
  editorShares: string;
  changeReason: string;
  stages: Record<TermsStage, { editor: string; client: string }>;
};

function Errors({ state }: { state: FormState }) {
  return (
    <>
      <FormMessage state={state} />
      {/* Field errors show inline; only the stage-pair error has no field of its own. */}
      {state.fieldErrors?.stages
        ? state.fieldErrors.stages.slice(0, 1).map((message) => (
            <p key={message} className="text-destructive text-sm">
              {message}
            </p>
          ))
        : null}
    </>
  );
}

/** Edit the draft terms (or start the next version from the latest one). */
export function TermsDraftForm({
  projectId,
  defaults,
  hasDraft,
  nextVersion,
}: {
  projectId: string;
  defaults: TermsDefaults;
  hasDraft: boolean;
  nextVersion: number;
}) {
  const [state, formAction, pending] = useActionState(saveTermsDraftAction, initialFormState);
  const [, startTransition] = useTransition();
  const v = (name: string, fallback: string) => state.values?.[name] ?? fallback;
  return (
    <form
      onSubmit={(event) => {
        // Submitted inside a transition so a validation error keeps what the admin typed.
        event.preventDefault();
        const formData = new FormData(event.currentTarget);
        startTransition(() => formAction(formData));
      }}
      className="grid gap-4"
      noValidate
    >
      <input type="hidden" name="projectId" value={projectId} />
      <Errors state={state} />
      <p className="text-muted-foreground text-sm">
        {hasDraft
          ? `Editing the draft (version ${nextVersion}). Nothing changes until it is agreed.`
          : `Saving starts version ${nextVersion} as a draft; the agreed version stays in force until you agree the new one.`}
      </p>
      <fieldset className="grid gap-4 rounded-lg border p-3">
        <legend className="px-1 text-sm font-medium">Revisions</legend>
        <div className="grid gap-4 sm:grid-cols-3">
          <Field
            name="includedRounds"
            label="Included revision rounds"
            inputMode="numeric"
            hint="0 means every client revision is chargeable."
            defaultValue={v("includedRounds", defaults.includedRounds)}
            state={state}
          />
          <Field
            name="extraRoundCharge"
            label="Client charge per extra round"
            hint="Admin only. Leave empty until known."
            defaultValue={v("extraRoundCharge", defaults.extraRoundCharge)}
            state={state}
          />
          <Field
            name="chargeCurrency"
            label="Charge currency"
            defaultValue={v("chargeCurrency", defaults.chargeCurrency)}
            state={state}
          />
        </div>
      </fieldset>
      <fieldset className="grid gap-4 rounded-lg border p-3">
        <legend className="px-1 text-sm font-medium">Payment days (calendar days)</legend>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field
            name="depositDays"
            label="Deposit due after invoice"
            inputMode="numeric"
            defaultValue={v("depositDays", defaults.depositDays)}
            state={state}
          />
          <Field
            name="balanceDays"
            label="Balance due after approval"
            inputMode="numeric"
            defaultValue={v("balanceDays", defaults.balanceDays)}
            state={state}
          />
          <Field
            name="editorPayDays"
            label="Editor paid within (after payable)"
            inputMode="numeric"
            defaultValue={v("editorPayDays", defaults.editorPayDays)}
            state={state}
          />
          <Field
            name="lateBalanceDays"
            label="Late-balance protection after"
            inputMode="numeric"
            defaultValue={v("lateBalanceDays", defaults.lateBalanceDays)}
            state={state}
          />
        </div>
      </fieldset>
      <fieldset className="grid gap-4 rounded-lg border p-3">
        <legend className="px-1 text-sm font-medium">Editor pay</legend>
        <Field
          name="editorShares"
          label="Editor pay milestones (%)"
          hint="Shares of the agreed editor pay, in order, adding up to 100. For example: 50, 50."
          defaultValue={v("editorShares", defaults.editorShares)}
          state={state}
        />
      </fieldset>
      <fieldset className="grid min-w-0 gap-3 rounded-lg border p-3">
        <legend className="px-1 text-sm font-medium">Cancellation schedule</legend>
        <p className="text-muted-foreground text-sm">
          Percent of the agreed totals, by the project status at cancellation. No defaults: enter
          what was agreed. The editor sees only their share; the client charge is admin only.
        </p>
        {TERMS_STAGES.map((s) => (
          <div key={s} className="grid gap-2 sm:grid-cols-2 sm:items-end">
            <Field
              name={`stage.${s}.editor`}
              label={`${TERMS_STAGE_LABEL[s]}: editor earns (%)`}
              inputMode="text"
              defaultValue={v(`stage.${s}.editor`, defaults.stages[s].editor)}
              state={state}
            />
            <Field
              name={`stage.${s}.client`}
              label={`${TERMS_STAGE_LABEL[s]}: client charged (%)`}
              inputMode="text"
              defaultValue={v(`stage.${s}.client`, defaults.stages[s].client)}
              state={state}
            />
          </div>
        ))}
      </fieldset>
      <TextareaField
        name="changeReason"
        label="Reason for the change"
        hint="Required to agree a new version after work has begun. Admin only."
        defaultValue={v("changeReason", defaults.changeReason)}
        state={state}
      />
      <div>
        <Button type="submit" disabled={pending}>
          {pending ? "Saving…" : hasDraft ? "Save draft" : "Start new version"}
        </Button>
      </div>
    </form>
  );
}
