"use client";

import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import { Field, FormMessage, TextareaField } from "@/features/authentication/components/form-parts";
import { initialFormState } from "@/features/authentication/schemas";

import { createClientAction } from "../admin-actions";

export function CreateClientForm() {
  const [state, formAction, pending] = useActionState(createClientAction, initialFormState);
  return (
    <form action={formAction} className="grid gap-4" noValidate>
      <FormMessage state={state} />
      <div className="grid gap-4 sm:grid-cols-2">
        <Field name="name" label="Contact name" required state={state} />
        <Field name="company" label="Company or agency" state={state} />
        <Field name="email" label="Email" type="email" required state={state} />
        <Field name="phone" label="Phone" state={state} />
      </div>
      <TextareaField name="notes" label="Notes" hint="Admin only." state={state} />
      <Button type="submit" className="justify-self-start" disabled={pending}>
        {pending ? "Saving…" : "Add client"}
      </Button>
    </form>
  );
}
