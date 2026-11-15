"use client";

import { useActionState, useTransition } from "react";

import { Button } from "@/components/ui/button";
import { Field, FormMessage, TextareaField } from "@/features/authentication/components/form-parts";
import { initialFormState, type FormState } from "@/features/authentication/schemas";

type Action = (prev: FormState, formData: FormData) => Promise<FormState>;

export type BillingField = {
  name: string;
  label: string;
  hint?: string;
  type?: "text" | "date";
  textarea?: boolean;
  defaultValue?: string;
};

/**
 * One billing form with typed inputs. Props are plain data (no function children). Submitted
 * inside a transition, and failed submits echo the values back, so input is never lost.
 */
export function BillingForm({
  action,
  submitLabel,
  hidden,
  fields,
  idPrefix,
}: {
  action: Action;
  submitLabel: string;
  hidden: Record<string, string>;
  fields: BillingField[];
  idPrefix: string;
}) {
  const [state, formAction, pending] = useActionState(action, initialFormState);
  const [, startTransition] = useTransition();
  // Field ids must be unique on a page with several milestone forms.
  const scoped: FormState = {
    ...state,
    fieldErrors: state.fieldErrors
      ? Object.fromEntries(
          Object.entries(state.fieldErrors).map(([k, v]) => [`${idPrefix}-${k}`, v]),
        )
      : undefined,
  };
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        const raw = new FormData(event.currentTarget);
        const data = new FormData();
        for (const [k, v] of raw.entries()) data.set(k.replace(`${idPrefix}-`, ""), v);
        startTransition(() => formAction(data));
      }}
      className="grid gap-3"
      noValidate
    >
      <FormMessage state={state} />
      {Object.entries(hidden).map(([name, value]) => (
        <input key={name} type="hidden" name={name} value={value} />
      ))}
      {fields.map((f) => {
        const value = state.values?.[f.name] ?? f.defaultValue ?? "";
        return f.textarea ? (
          <TextareaField
            key={f.name}
            name={`${idPrefix}-${f.name}`}
            label={f.label}
            hint={f.hint}
            defaultValue={value}
            state={scoped}
          />
        ) : (
          <Field
            key={f.name}
            name={`${idPrefix}-${f.name}`}
            label={f.label}
            hint={f.hint}
            type={f.type ?? "text"}
            defaultValue={value}
            state={scoped}
          />
        );
      })}
      <div>
        <Button type="submit" variant="outline" disabled={pending}>
          {pending ? "Working…" : submitLabel}
        </Button>
      </div>
    </form>
  );
}
