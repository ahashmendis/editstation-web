"use client";

import Link from "next/link";
import { useActionState, startTransition, type FormEvent } from "react";

import { Button } from "@/components/ui/button";
import { Field, FormMessage, TextareaField } from "@/features/authentication/components/form-parts";
import { initialFormState } from "@/features/authentication/schemas";

import { submitInquiryAction } from "../actions";
import { ProjectFields, ReferenceLinksFields, type InquiryFormOptions } from "./project-fields";

export function InquiryForm({ services, budgets }: InquiryFormOptions) {
  const [state, formAction, pending] = useActionState(submitInquiryAction, initialFormState);

  // No automatic reset, so a validation error never wipes what the client typed.
  function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    startTransition(() => formAction(data));
  }

  if (state.status === "success") return <FormMessage state={state} />;

  const err = (name: string) => state.fieldErrors?.[name]?.[0];

  return (
    <form onSubmit={onSubmit} className="grid gap-8" noValidate>
      <FormMessage state={state} />

      {/* Honeypot: hidden from people and assistive tech; bots tend to fill it in. */}
      <div aria-hidden="true" className="absolute -left-[9999px] h-0 w-0 overflow-hidden">
        <label>
          Website
          <input type="text" name="website" tabIndex={-1} autoComplete="off" />
        </label>
      </div>

      <section className="grid gap-4">
        <h2 className="text-lg font-semibold">Your details</h2>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field name="contactName" label="Your name" autoComplete="name" state={state} required />
          <Field
            name="company"
            label="Company or agency (optional)"
            autoComplete="organization"
            state={state}
          />
          <Field
            name="email"
            label="Email"
            type="email"
            autoComplete="email"
            state={state}
            required
          />
          <Field
            name="phone"
            label="Phone (optional)"
            type="tel"
            autoComplete="tel"
            state={state}
          />
        </div>
      </section>

      <section className="grid gap-4">
        <h2 className="text-lg font-semibold">Your project</h2>
        <ProjectFields services={services} budgets={budgets} state={state} />
      </section>

      <section className="grid gap-3">
        <h2 className="text-lg font-semibold">References (optional)</h2>
        <p className="text-muted-foreground text-sm">
          Links to videos whose style you like, or to a shared folder. Please use full https://
          links; we can arrange file transfers after we&apos;ve spoken.
        </p>
        <ReferenceLinksFields state={state} />
        <TextareaField name="clientNotes" label="Anything else? (optional)" state={state} />
      </section>

      <section className="grid gap-3 border-t pt-6">
        <label className="flex items-start gap-2 text-sm">
          <input type="checkbox" name="acceptPrivacy" className="mt-0.5 size-4" />
          <span>
            I&apos;ve read the{" "}
            <Link href="/legal/privacy" target="_blank" className="underline">
              privacy notice
            </Link>{" "}
            and agree to Lenscape Studios using these details to respond to my inquiry.
          </span>
        </label>
        {err("acceptPrivacy") ? (
          <p className="text-destructive text-sm">{err("acceptPrivacy")}</p>
        ) : null}
        <Button type="submit" disabled={pending} className="justify-self-start">
          {pending ? "Sending…" : "Send inquiry"}
        </Button>
        <p className="text-muted-foreground text-sm">
          Sending an inquiry doesn&apos;t commit you to anything. We&apos;ll reply to discuss scope,
          timing and pricing.
        </p>
      </section>
    </form>
  );
}
