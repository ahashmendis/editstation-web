"use client";

import Link from "next/link";
import { useActionState, startTransition, type FormEvent } from "react";

import { Button, buttonVariants } from "@/components/ui/button";
import { FormMessage, TextareaField } from "@/features/authentication/components/form-parts";
import { initialFormState } from "@/features/authentication/schemas";
import {
  ProjectFields,
  ReferenceLinksFields,
  type InquiryFormOptions,
} from "@/features/inquiries/components/project-fields";

import { submitClientProjectAction } from "../actions";

/** "New project" for a signed-in client. No contact fields: the studio already has them. */
export function ClientProjectForm({ services, budgets }: InquiryFormOptions) {
  const [state, formAction, pending] = useActionState(submitClientProjectAction, initialFormState);

  // No automatic reset, so a validation error never wipes what the client typed.
  function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    startTransition(() => formAction(data));
  }

  if (state.status === "success") {
    return (
      <div className="grid gap-4">
        <FormMessage state={state} />
        <div className="flex flex-wrap gap-3">
          <Link href="/client/requests" className={buttonVariants()}>
            See my requests
          </Link>
          <Link href="/client" className={buttonVariants({ variant: "outline" })}>
            Back to overview
          </Link>
        </div>
      </div>
    );
  }

  const err = (name: string) => state.fieldErrors?.[name]?.[0];

  return (
    <form onSubmit={onSubmit} className="grid gap-8" noValidate>
      <FormMessage state={state} />

      {/* Honeypot, as on the public form: hidden from people and assistive tech. */}
      <div aria-hidden="true" className="absolute -left-[9999px] h-0 w-0 overflow-hidden">
        <label>
          Website
          <input type="text" name="website" tabIndex={-1} autoComplete="off" />
        </label>
      </div>

      <section className="grid gap-4">
        <h2 className="text-lg font-semibold">Your project</h2>
        <ProjectFields
          services={services}
          budgets={budgets}
          state={state}
          deadlineLabel="When would you like it by? (optional)"
          deadlineHint="Your preferred date. The studio confirms timing with you."
        />
      </section>

      <section className="grid gap-3">
        <h2 className="text-lg font-semibold">References (optional)</h2>
        <p className="text-muted-foreground text-sm">
          Links to videos whose style you like, or to a shared folder. Please use full https://
          links.
        </p>
        <ReferenceLinksFields state={state} />
        <TextareaField name="clientNotes" label="Anything else? (optional)" state={state} />
      </section>

      <section className="grid gap-3 border-t pt-6">
        <p className="text-muted-foreground text-sm">
          The studio will contact you using the details on your client account.
        </p>
        <label className="flex items-start gap-2 text-sm">
          <input
            type="checkbox"
            name="acceptPrivacy"
            className="mt-0.5 size-4"
            aria-describedby={err("acceptPrivacy") ? "acceptPrivacy-error" : undefined}
          />
          <span>
            I&apos;ve read the{" "}
            <Link href="/legal/privacy" target="_blank" className="underline">
              privacy notice
            </Link>{" "}
            and agree to Lenscape Studios using these details to respond to my request.
          </span>
        </label>
        {err("acceptPrivacy") ? (
          <p id="acceptPrivacy-error" className="text-destructive text-sm">
            {err("acceptPrivacy")}
          </p>
        ) : null}
        <Button type="submit" disabled={pending} className="justify-self-start">
          {pending ? "Sending…" : "Send request"}
        </Button>
        <p className="text-muted-foreground text-sm">
          Sending a request doesn&apos;t commit you to anything. The studio reviews it and gets in
          touch about scope, timing and pricing.
        </p>
      </section>
    </form>
  );
}
