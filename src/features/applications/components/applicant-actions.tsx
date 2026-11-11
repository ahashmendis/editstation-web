"use client";

import { useActionState, useState, useTransition } from "react";

import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Field, FormMessage } from "@/features/authentication/components/form-parts";
import { initialFormState, type FormState } from "@/features/authentication/schemas";

import { respondToRequestAction, withdrawApplicationAction } from "../actions";

export function RequestResponseForm({ requestId, isTest }: { requestId: string; isTest: boolean }) {
  const [state, action, pending] = useActionState(respondToRequestAction, initialFormState);
  if (state.status === "success") return <FormMessage state={state} />;

  return (
    <form action={action} className="grid gap-3" noValidate>
      <FormMessage state={state} />
      <input type="hidden" name="requestId" value={requestId} />
      <div className="grid gap-2">
        <Label htmlFor={`response-${requestId}`}>Your response</Label>
        <Textarea id={`response-${requestId}`} name="response" rows={4} />
        {state.fieldErrors?.response ? (
          <p className="text-destructive text-sm">{state.fieldErrors.response[0]}</p>
        ) : null}
      </div>
      <Field
        name="responseLink"
        label={isTest ? "Link to your test edit" : "Link (optional)"}
        type="url"
        inputMode="text"
        hint="A full https:// link, for example a shared Drive or Vimeo link."
        state={state}
      />
      <Button type="submit" disabled={pending} className="justify-self-start">
        {pending ? "Sending…" : "Send response"}
      </Button>
    </form>
  );
}

export function WithdrawButton() {
  const [confirming, setConfirming] = useState(false);
  const [result, setResult] = useState<FormState | null>(null);
  const [pending, startTransition] = useTransition();

  if (result?.status === "success") return <FormMessage state={result} />;

  return (
    <div className="grid gap-2">
      {result ? <FormMessage state={result} /> : null}
      {confirming ? (
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span>Withdraw your application? You&apos;ll need us to reopen it to apply again.</span>
          <Button
            variant="destructive"
            size="sm"
            disabled={pending}
            onClick={() =>
              startTransition(async () => setResult(await withdrawApplicationAction()))
            }
          >
            {pending ? "Withdrawing…" : "Yes, withdraw"}
          </Button>
          <Button variant="ghost" size="sm" onClick={() => setConfirming(false)}>
            Cancel
          </Button>
        </div>
      ) : (
        <Button
          variant="outline"
          size="sm"
          className="justify-self-start"
          onClick={() => setConfirming(true)}
        >
          Withdraw application
        </Button>
      )}
    </div>
  );
}
