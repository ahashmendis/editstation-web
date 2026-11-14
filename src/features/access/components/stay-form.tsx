"use client";

import { useActionState, useEffect, useRef, useState, useTransition, type ReactNode } from "react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { FormMessage } from "@/features/authentication/components/form-parts";
import { initialFormState, type FormState } from "@/features/authentication/schemas";
import { selectClassName } from "@/features/projects/components/select-class";

type Action = (prev: FormState, formData: FormData) => Promise<FormState>;

/**
 * One server action as a form. Submitting inside a transition (not `action={...}`) stops React
 * resetting the fields on a validation error, so nothing the person typed is lost. An optional
 * `confirm` adds a second click for consequential actions.
 */
export function StayForm({
  action,
  submitLabel,
  variant = "default",
  confirm,
  resetOnSuccess,
  children,
}: {
  action: Action;
  submitLabel: string;
  variant?: "default" | "outline" | "destructive" | "secondary";
  confirm?: string;
  resetOnSuccess?: boolean;
  children?: ReactNode | ((state: FormState) => ReactNode);
}) {
  const [state, formAction, pending] = useActionState(action, initialFormState);
  const [, startTransition] = useTransition();
  const ref = useRef<HTMLFormElement>(null);
  // Armed only for the current result, so every consequential action needs its own second click.
  const [armedFor, setArmedFor] = useState<FormState | null>(null);
  const armed = armedFor === state;

  useEffect(() => {
    if (resetOnSuccess && state.status === "success") ref.current?.reset();
  }, [resetOnSuccess, state]);

  return (
    <form
      ref={ref}
      onSubmit={(event) => {
        event.preventDefault();
        const formData = new FormData(event.currentTarget);
        startTransition(() => formAction(formData));
      }}
      className="grid gap-3"
      noValidate
    >
      <FormMessage state={state} />
      {typeof children === "function" ? children(state) : children}
      {confirm && !armed ? (
        <Button
          type="button"
          variant={variant}
          className="justify-self-start"
          onClick={() => setArmedFor(state)}
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
            <Button type="button" variant="ghost" onClick={() => setArmedFor(null)}>
              Cancel
            </Button>
          ) : null}
        </div>
      )}
    </form>
  );
}

type FieldBase = {
  /** Unique on the page: several forms share field names. */
  id: string;
  name: string;
  label: string;
  state: FormState;
  hint?: string;
};

function Errors({
  id,
  state,
  name,
  hint,
}: {
  id: string;
  state: FormState;
  name: string;
  hint?: string;
}) {
  const errors = state.fieldErrors?.[name];
  if (errors?.length) {
    return (
      <p id={`${id}-error`} role="alert" className="text-destructive text-sm">
        {errors[0]}
      </p>
    );
  }
  return hint ? (
    <p id={`${id}-hint`} className="text-muted-foreground text-sm">
      {hint}
    </p>
  ) : null;
}

function describedBy({ id, state, name, hint }: FieldBase) {
  return state.fieldErrors?.[name]?.length ? `${id}-error` : hint ? `${id}-hint` : undefined;
}

export function TextField(
  props: FieldBase & {
    defaultValue?: string;
    inputMode?: "numeric" | "text" | "email" | "decimal" | "url";
    type?: string;
    maxLength?: number;
    placeholder?: string;
  },
) {
  const { id, name, label, state, hint, defaultValue, inputMode, type, maxLength, placeholder } =
    props;
  return (
    <div className="grid gap-2">
      <Label htmlFor={id}>{label}</Label>
      <Input
        id={id}
        name={name}
        type={type}
        inputMode={inputMode}
        maxLength={maxLength}
        placeholder={placeholder}
        defaultValue={defaultValue ?? state.values?.[name]}
        aria-invalid={state.fieldErrors?.[name]?.length ? true : undefined}
        aria-describedby={describedBy(props)}
      />
      <Errors id={id} state={state} name={name} hint={hint} />
    </div>
  );
}

export function AreaField(props: FieldBase & { rows?: number; maxLength?: number }) {
  const { id, name, label, state, hint, rows = 3, maxLength } = props;
  return (
    <div className="grid gap-2">
      <Label htmlFor={id}>{label}</Label>
      <Textarea
        id={id}
        name={name}
        rows={rows}
        maxLength={maxLength}
        defaultValue={state.values?.[name]}
        aria-invalid={state.fieldErrors?.[name]?.length ? true : undefined}
        aria-describedby={describedBy(props)}
      />
      <Errors id={id} state={state} name={name} hint={hint} />
    </div>
  );
}

export function SelectField(props: FieldBase & { defaultValue?: string; children: ReactNode }) {
  const { id, name, label, state, hint, defaultValue, children } = props;
  return (
    <div className="grid gap-2">
      <Label htmlFor={id}>{label}</Label>
      <select
        id={id}
        name={name}
        className={selectClassName}
        defaultValue={state.values?.[name] ?? defaultValue}
        aria-invalid={state.fieldErrors?.[name]?.length ? true : undefined}
        aria-describedby={describedBy(props)}
      >
        {children}
      </select>
      <Errors id={id} state={state} name={name} hint={hint} />
    </div>
  );
}
