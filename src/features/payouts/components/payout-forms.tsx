"use client";

import { useActionState, useEffect, useState, useTransition } from "react";

import { Button } from "@/components/ui/button";
import { FormMessage } from "@/features/authentication/components/form-parts";
import { initialFormState } from "@/features/authentication/schemas";
import {
  AreaField,
  SelectField,
  StayForm,
  TextField,
} from "@/features/access/components/stay-form";

import { savePayoutDetailsAction } from "../actions";
import {
  attestPayoutAction,
  revealPayoutAction,
  type RevealState,
  setPayoutEnabledAction,
  verifyPayoutAction,
} from "../admin-actions";
import { VERIFY_METHODS, VERIFY_METHOD_LABEL } from "../schemas";

/** Client form wrappers: render-prop children cannot cross the server/client boundary. */

export function EditorPayoutForm({
  accountHolder,
  bank,
  branch,
  saved,
}: {
  accountHolder?: string;
  bank?: string;
  branch?: string;
  saved: boolean;
}) {
  return (
    <StayForm
      action={savePayoutDetailsAction}
      resetOnSuccess
      submitLabel={saved ? "Save changes" : "Save payout details"}
      confirm={
        saved ? "Changing details makes them unverified until Lenscape confirms them." : undefined
      }
    >
      {(state) => (
        <>
          <TextField
            id="payout-holder"
            name="accountHolder"
            label="Account holder name"
            state={state}
            maxLength={120}
            defaultValue={state.values?.accountHolder ?? accountHolder}
          />
          <TextField
            id="payout-bank"
            name="bank"
            label="Bank"
            state={state}
            maxLength={120}
            defaultValue={state.values?.bank ?? bank}
          />
          <TextField
            id="payout-branch"
            name="branch"
            label="Branch"
            state={state}
            maxLength={120}
            defaultValue={state.values?.branch ?? branch}
          />
          <TextField
            id="payout-number"
            name="accountNumber"
            label={saved ? "Account number (enter it again to save)" : "Account number"}
            hint="Never enter banking passwords, PINs or one-time codes."
            state={state}
            maxLength={34}
            inputMode="text"
          />
        </>
      )}
    </StayForm>
  );
}

export function VerifyPayoutForm({ editorId, version }: { editorId: string; version: number }) {
  return (
    <StayForm action={verifyPayoutAction} submitLabel="Mark verified">
      {(state) => (
        <>
          <input type="hidden" name="editorId" value={editorId} />
          <input type="hidden" name="version" value={version} />
          <SelectField
            id="verify-method"
            name="method"
            label="How you verified them"
            state={state}
            defaultValue="phone"
          >
            {VERIFY_METHODS.map((m) => (
              <option key={m} value={m}>
                {VERIFY_METHOD_LABEL[m]}
              </option>
            ))}
          </SelectField>
          <AreaField
            id="verify-note"
            name="note"
            label="Note"
            hint="For example who you spoke to and on which number. Do not repeat the bank details."
            state={state}
            maxLength={500}
            rows={2}
          />
        </>
      )}
    </StayForm>
  );
}

export function AttestPayoutForm({ editorId }: { editorId: string }) {
  return (
    <StayForm
      action={attestPayoutAction}
      submitLabel="Record: verified outside the app"
      variant="outline"
      confirm="This records your name and today's date."
    >
      {(state) => (
        <>
          <input type="hidden" name="editorId" value={editorId} />
          <AreaField
            id="attest-note"
            name="note"
            label="Note"
            hint="How and when you verified the editor's payout account. Do not enter bank details."
            state={state}
            maxLength={500}
            rows={2}
          />
        </>
      )}
    </StayForm>
  );
}

const REVEAL_SECONDS = 30;

/**
 * Reveal with a required reason. The full number is held only in component state: shown until
 * Hide or after REVEAL_SECONDS, never written to storage or the URL.
 */
export function RevealPayoutForm({ editorId }: { editorId: string }) {
  const [state, formAction, pending] = useActionState<RevealState, FormData>(
    revealPayoutAction,
    initialFormState,
  );
  const [, startTransition] = useTransition();
  const [hiddenFor, setHiddenFor] = useState<RevealState | null>(null);
  const shown = state.revealed && hiddenFor !== state ? state.revealed : null;

  useEffect(() => {
    if (!state.revealed) return;
    const timer = setTimeout(() => setHiddenFor(state), REVEAL_SECONDS * 1000);
    return () => clearTimeout(timer);
  }, [state]);

  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        const formData = new FormData(event.currentTarget);
        startTransition(() => formAction(formData));
      }}
      className="grid gap-3"
      noValidate
    >
      <FormMessage state={state} />
      {shown ? (
        <div role="status" className="flex flex-wrap items-center gap-3 rounded-md border p-3">
          <span className="text-sm">
            Full account number: <strong className="font-mono">{shown}</strong>
          </span>
          <Button type="button" variant="outline" size="sm" onClick={() => setHiddenFor(state)}>
            Hide
          </Button>
          <span className="text-muted-foreground text-xs">
            Hidden automatically after {REVEAL_SECONDS} seconds.
          </span>
        </div>
      ) : null}
      <input type="hidden" name="editorId" value={editorId} />
      <TextField
        id="reveal-reason"
        name="reason"
        label="Reason (recorded in the activity log)"
        hint="Say why in words. Do not type bank details or account numbers here."
        state={state}
        maxLength={500}
      />
      <div>
        <Button type="submit" variant="outline" disabled={pending}>
          {pending ? "Working…" : "Reveal full number"}
        </Button>
      </div>
    </form>
  );
}

export function PayoutEnabledForm({ enabled }: { enabled: boolean }) {
  return (
    <StayForm
      action={setPayoutEnabledAction}
      submitLabel={enabled ? "Turn payout details off" : "Turn payout details on"}
      variant={enabled ? "outline" : "destructive"}
      confirm={
        enabled
          ? "Editors will not be able to change payout details."
          : "Only continue if counsel has confirmed PDPA handling."
      }
    >
      {(state) => (
        <>
          <input type="hidden" name="enabled" value={enabled ? "off" : "on"} />
          <label className="flex min-h-11 items-center gap-2 text-sm">
            <input type="checkbox" name="confirm" value="yes" className="size-4" />
            {enabled
              ? "I want to lock payout details again."
              : "Counsel has confirmed how bank details are handled under the PDPA."}
          </label>
          {state.fieldErrors?.confirm?.length ? (
            <p role="alert" className="text-destructive text-sm">
              {state.fieldErrors.confirm[0]}
            </p>
          ) : null}
        </>
      )}
    </StayForm>
  );
}
