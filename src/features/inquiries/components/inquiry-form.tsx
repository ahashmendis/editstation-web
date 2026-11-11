"use client";

import Link from "next/link";
import { useActionState, useState, startTransition, type FormEvent } from "react";

import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Field, FormMessage, TextareaField } from "@/features/authentication/components/form-parts";
import { initialFormState } from "@/features/authentication/schemas";

import { submitInquiryAction } from "../actions";
import { MAX_REFERENCE_LINKS } from "../constants";

const selectClass =
  "border-input h-9 w-full rounded-md border bg-transparent px-3 text-sm aria-invalid:border-destructive";
const inputClass = "border-input h-9 rounded-md border bg-transparent px-3 text-sm";

export function InquiryForm({
  services,
  budgets,
}: {
  services: { code: string; label: string }[];
  budgets: { id: string; label: string; currency: string }[];
}) {
  const [state, formAction, pending] = useActionState(submitInquiryAction, initialFormState);
  const [links, setLinks] = useState([{ url: "", label: "" }]);

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
        <div className="grid gap-2">
          <Label htmlFor="serviceType">Type of editing</Label>
          <select
            id="serviceType"
            name="serviceType"
            className={selectClass}
            defaultValue={state.values?.serviceType ?? ""}
            aria-invalid={err("serviceType") ? true : undefined}
            required
          >
            <option value="" disabled>
              Choose…
            </option>
            {services.map((s) => (
              <option key={s.code} value={s.code}>
                {s.label}
              </option>
            ))}
          </select>
          {err("serviceType") ? (
            <p className="text-destructive text-sm">{err("serviceType")}</p>
          ) : null}
        </div>
        <TextareaField
          name="description"
          label="Project description"
          hint="What is the video for, who is it for, and what footage do you have?"
          state={state}
          required
        />
        <TextareaField
          name="expectedDeliverables"
          label="Expected deliverables (optional)"
          hint="For example: one 3-minute film and three 30-second cut-downs for Instagram."
          state={state}
        />
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="grid gap-2">
            <Label htmlFor="budgetRangeId">Estimated budget</Label>
            <select
              id="budgetRangeId"
              name="budgetRangeId"
              className={selectClass}
              defaultValue={state.values?.budgetRangeId || "discuss"}
            >
              {budgets.map((b) => (
                <option key={b.id} value={b.id}>
                  {b.label}
                </option>
              ))}
              <option value="discuss">Prefer to discuss</option>
            </select>
          </div>
          <Field
            name="expectedDeadline"
            label="Expected deadline (optional)"
            type="date"
            state={state}
          />
        </div>
      </section>

      <section className="grid gap-3">
        <h2 className="text-lg font-semibold">References (optional)</h2>
        <p className="text-muted-foreground text-sm">
          Links to videos whose style you like, or to a shared folder. Please use full https://
          links; we can arrange file transfers after we&apos;ve spoken.
        </p>
        {links.map((link, index) => (
          <div key={index} className="grid gap-2 sm:grid-cols-[2fr_1fr_auto] sm:items-end">
            <div className="grid gap-1">
              <Label htmlFor={`linkUrl-${index}`}>Link {index + 1}</Label>
              <input
                id={`linkUrl-${index}`}
                name="linkUrl"
                type="url"
                value={link.url}
                onChange={(e) =>
                  setLinks(links.map((l, i) => (i === index ? { ...l, url: e.target.value } : l)))
                }
                placeholder="https://"
                className={inputClass}
              />
            </div>
            <div className="grid gap-1">
              <Label htmlFor={`linkLabel-${index}`}>What to look at (optional)</Label>
              <input
                id={`linkLabel-${index}`}
                name="linkLabel"
                value={link.label}
                onChange={(e) =>
                  setLinks(links.map((l, i) => (i === index ? { ...l, label: e.target.value } : l)))
                }
                className={inputClass}
              />
            </div>
            <Button
              type="button"
              variant="ghost"
              size="sm"
              onClick={() => setLinks(links.filter((_, i) => i !== index))}
              aria-label={`Remove link ${index + 1}`}
            >
              Remove
            </Button>
          </div>
        ))}
        {err("links") ? <p className="text-destructive text-sm">{err("links")}</p> : null}
        {links.length < MAX_REFERENCE_LINKS ? (
          <Button
            type="button"
            variant="outline"
            size="sm"
            className="justify-self-start"
            onClick={() => setLinks([...links, { url: "", label: "" }])}
          >
            Add a link
          </Button>
        ) : null}
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
