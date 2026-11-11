"use client";

import { useActionState, useState, type ReactNode } from "react";

import { Button } from "@/components/ui/button";
import { FormMessage } from "@/features/authentication/components/form-parts";
import { initialFormState, type FormState } from "@/features/authentication/schemas";

type Action = (prev: FormState, formData: FormData) => Promise<FormState>;

/**
 * Wraps one admin action. Hidden ids and fields are passed as children. Optional `confirm`
 * adds a second click for consequential actions (approve, reject, revoke...).
 */
export function AdminActionForm({
  action,
  submitLabel,
  variant = "default",
  confirm,
  children,
}: {
  action: Action;
  submitLabel: string;
  variant?: "default" | "outline" | "destructive" | "secondary";
  confirm?: string;
  children?: ReactNode;
}) {
  const [state, formAction, pending] = useActionState(action, initialFormState);
  // Armed only for the current result: once the action returns (success or error), the
  // confirmation resets, so every consequential action needs its own second click.
  const [armedFor, setArmedFor] = useState<FormState | null>(null);
  const armed = armedFor === state;
  const setArmed = (value: boolean) => setArmedFor(value ? state : null);

  return (
    <form action={formAction} className="grid gap-3" noValidate>
      <FormMessage state={state} />
      {state.fieldErrors
        ? Object.values(state.fieldErrors)
            .flat()
            .slice(0, 1)
            .map((message) => (
              <p key={message} className="text-destructive text-sm">
                {message}
              </p>
            ))
        : null}
      {children}
      {confirm && !armed ? (
        <Button
          type="button"
          variant={variant}
          className="justify-self-start"
          onClick={() => setArmed(true)}
        >
          {submitLabel}
        </Button>
      ) : (
        <div className="flex flex-wrap items-center gap-2">
          {confirm ? <span className="text-sm">{confirm}</span> : null}
          <Button type="submit" variant={variant} disabled={pending}>
            {pending ? "Working…" : confirm ? "Confirm" : submitLabel}
          </Button>
          {confirm ? (
            <Button type="button" variant="ghost" onClick={() => setArmed(false)}>
              Cancel
            </Button>
          ) : null}
        </div>
      )}
    </form>
  );
}
