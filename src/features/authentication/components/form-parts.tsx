"use client";

import { Alert, AlertDescription } from "@/components/ui/alert";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

import type { FormState } from "../schemas";

type FieldProps = {
  name: string;
  label: string;
  type?: string;
  autoComplete?: string;
  inputMode?: "numeric" | "email" | "text";
  defaultValue?: string;
  hint?: string;
  state: FormState;
  required?: boolean;
};

export function Field({ name, label, hint, state, defaultValue, ...inputProps }: FieldProps) {
  const errors = state.fieldErrors?.[name];
  const value = defaultValue ?? state.values?.[name];
  const describedBy = errors?.length ? `${name}-error` : hint ? `${name}-hint` : undefined;
  return (
    <div className="grid gap-2">
      <Label htmlFor={name}>{label}</Label>
      <Input
        id={name}
        name={name}
        aria-invalid={errors?.length ? true : undefined}
        aria-describedby={describedBy}
        defaultValue={value}
        {...inputProps}
      />
      {errors?.length ? (
        <p id={`${name}-error`} className="text-destructive text-sm">
          {errors[0]}
        </p>
      ) : hint ? (
        <p id={`${name}-hint`} className="text-muted-foreground text-sm">
          {hint}
        </p>
      ) : null}
    </div>
  );
}

export function FormMessage({ state }: { state: FormState }) {
  if (!state.message) return null;
  return (
    <Alert variant={state.status === "error" ? "destructive" : "default"} role="status">
      <AlertDescription>{state.message}</AlertDescription>
    </Alert>
  );
}
