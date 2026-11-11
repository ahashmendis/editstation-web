"use client";

import Link from "next/link";
import { useActionState, useState, startTransition, type FormEvent } from "react";

import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Field, FormMessage } from "@/features/authentication/components/form-parts";
import { initialFormState, type FormState } from "@/features/authentication/schemas";

import { saveApplicationAction } from "../actions";
import { MAX_PORTFOLIO_LINKS } from "../constants";

type Option = { kind: "specialisation" | "software"; code: string; label: string };

export type ApplicationFormValues = {
  fullName: string;
  phone: string;
  region: string;
  experienceYears: string;
  experienceSummary: string;
  availability: string;
  typicalTurnaround: string;
  hardware: string;
  softwareOther: string;
  specialisations: string[];
  software: string[];
  links: { url: string; label: string }[];
};

function TextareaField({
  name,
  label,
  hint,
  defaultValue,
  state,
}: {
  name: string;
  label: string;
  hint?: string;
  defaultValue: string;
  state: FormState;
}) {
  const errors = state.fieldErrors?.[name];
  return (
    <div className="grid gap-2">
      <Label htmlFor={name}>{label}</Label>
      <Textarea
        id={name}
        name={name}
        defaultValue={defaultValue}
        aria-invalid={errors?.length ? true : undefined}
        aria-describedby={errors?.length ? `${name}-error` : hint ? `${name}-hint` : undefined}
        rows={4}
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

function OptionGroup({
  legend,
  name,
  options,
  selected,
}: {
  legend: string;
  name: string;
  options: Option[];
  selected: string[];
}) {
  return (
    <fieldset className="grid gap-2">
      <legend className="mb-1 text-sm font-medium">{legend}</legend>
      <div className="grid gap-2 sm:grid-cols-2">
        {options.map((option) => (
          <label key={option.code} className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              name={name}
              value={option.code}
              defaultChecked={selected.includes(option.code)}
              className="size-4"
            />
            {option.label}
          </label>
        ))}
      </div>
    </fieldset>
  );
}

export function ApplicationForm({
  initial,
  options,
}: {
  initial: ApplicationFormValues;
  options: Option[];
}) {
  const [state, formAction, pending] = useActionState(saveApplicationAction, initialFormState);
  const [links, setLinks] = useState(
    initial.links.length ? initial.links : [{ url: "", label: "" }],
  );

  // Submit without React's automatic form reset, so a validation error never wipes edits.
  function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const submitter = (event.nativeEvent as SubmitEvent).submitter;
    const data = new FormData(event.currentTarget, submitter);
    startTransition(() => formAction(data));
  }

  const specialisations = options.filter((o) => o.kind === "specialisation");
  const software = options.filter((o) => o.kind === "software");
  const linkErrors = state.fieldErrors?.links;

  return (
    <form onSubmit={onSubmit} className="grid gap-8" noValidate>
      <FormMessage state={state} />

      <section className="grid gap-4">
        <h2 className="text-lg font-semibold">About you</h2>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field
            name="fullName"
            label="Full name"
            autoComplete="name"
            defaultValue={initial.fullName}
            state={state}
          />
          <Field
            name="phone"
            label="Phone"
            type="tel"
            autoComplete="tel"
            defaultValue={initial.phone}
            state={state}
          />
          <Field
            name="region"
            label="General location in Sri Lanka"
            hint="For example: Colombo, Kandy, Galle. A town or district is enough."
            defaultValue={initial.region}
            state={state}
          />
          <Field
            name="experienceYears"
            label="Years of editing experience"
            inputMode="numeric"
            defaultValue={initial.experienceYears}
            state={state}
          />
        </div>
        <TextareaField
          name="experienceSummary"
          label="Experience summary"
          hint="The kind of work you've edited and for whom (no confidential client details)."
          defaultValue={initial.experienceSummary}
          state={state}
        />
      </section>

      <section className="grid gap-4">
        <h2 className="text-lg font-semibold">Skills and tools</h2>
        <OptionGroup
          legend="Specialisations"
          name="specialisations"
          options={specialisations}
          selected={initial.specialisations}
        />
        <OptionGroup
          legend="Editing software"
          name="software"
          options={software}
          selected={initial.software}
        />
        <Field
          name="softwareOther"
          label="Other software (optional)"
          defaultValue={initial.softwareOther}
          state={state}
        />
        <TextareaField
          name="hardware"
          label="Workstation / hardware (optional)"
          defaultValue={initial.hardware}
          state={state}
        />
      </section>

      <section className="grid gap-4">
        <h2 className="text-lg font-semibold">Availability</h2>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field
            name="availability"
            label="Availability"
            hint="For example: weekdays, about 20 hours a week."
            defaultValue={initial.availability}
            state={state}
          />
          <Field
            name="typicalTurnaround"
            label="Typical turnaround"
            hint="For example: 2–3 days for a 60-second reel."
            defaultValue={initial.typicalTurnaround}
            state={state}
          />
        </div>
      </section>

      <section className="grid gap-4">
        <h2 className="text-lg font-semibold">Portfolio</h2>
        <p className="text-muted-foreground text-sm">
          Links to your work (YouTube, Vimeo, Behance, a shared folder…). Use full https:// links.
          Only share work you have permission to show.
        </p>
        <div className="grid gap-3">
          {links.map((link, index) => (
            <div key={index} className="grid gap-2 sm:grid-cols-[2fr_1fr_auto] sm:items-end">
              <div className="grid gap-1">
                <Label htmlFor={`linkUrl-${index}`}>Link {index + 1}</Label>
                <input
                  id={`linkUrl-${index}`}
                  name="linkUrl"
                  type="url"
                  inputMode="url"
                  value={link.url}
                  onChange={(e) =>
                    setLinks(links.map((l, i) => (i === index ? { ...l, url: e.target.value } : l)))
                  }
                  placeholder="https://"
                  className="border-input h-9 rounded-md border bg-transparent px-3 text-sm"
                />
              </div>
              <div className="grid gap-1">
                <Label htmlFor={`linkLabel-${index}`}>Label (optional)</Label>
                <input
                  id={`linkLabel-${index}`}
                  name="linkLabel"
                  value={link.label}
                  onChange={(e) =>
                    setLinks(
                      links.map((l, i) => (i === index ? { ...l, label: e.target.value } : l)),
                    )
                  }
                  placeholder="Showreel"
                  className="border-input h-9 rounded-md border bg-transparent px-3 text-sm"
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
          {linkErrors?.length ? <p className="text-destructive text-sm">{linkErrors[0]}</p> : null}
          {links.length < MAX_PORTFOLIO_LINKS ? (
            <Button
              type="button"
              variant="outline"
              size="sm"
              className="justify-self-start"
              onClick={() => setLinks([...links, { url: "", label: "" }])}
            >
              Add another link
            </Button>
          ) : null}
        </div>
      </section>

      <section className="grid gap-3 border-t pt-6">
        <label className="flex items-start gap-2 text-sm">
          <input type="checkbox" name="acceptTerms" className="mt-0.5 size-4" />
          <span>
            I accept the{" "}
            <Link href="/legal/editor-terms" target="_blank" className="underline">
              editor terms
            </Link>{" "}
            and{" "}
            <Link href="/legal/privacy" target="_blank" className="underline">
              privacy notice
            </Link>
            .
          </span>
        </label>
        {state.fieldErrors?.acceptTerms ? (
          <p className="text-destructive text-sm">{state.fieldErrors.acceptTerms[0]}</p>
        ) : null}
        <div className="flex flex-wrap gap-3">
          <Button type="submit" name="intent" value="submit" disabled={pending}>
            {pending ? "Saving…" : "Submit application"}
          </Button>
          <Button type="submit" name="intent" value="save" variant="outline" disabled={pending}>
            Save without submitting
          </Button>
        </div>
        <p className="text-muted-foreground text-sm">
          Submitting doesn&apos;t give access to projects. Our team reviews every application.
        </p>
      </section>
    </form>
  );
}
