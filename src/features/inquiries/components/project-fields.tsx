"use client";

import { useState } from "react";

import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Field, TextareaField } from "@/features/authentication/components/form-parts";
import type { FormState } from "@/features/authentication/schemas";

import { MAX_REFERENCE_LINKS } from "../constants";

// The project part of a request, shared by the public inquiry form and the client area's
// "New project" form (same fields, names and validation: inquirySchema).

const selectClass =
  "border-input h-9 w-full rounded-md border bg-transparent px-3 text-sm aria-invalid:border-destructive";
const inputClass = "border-input h-9 min-w-0 rounded-md border bg-transparent px-3 text-sm";

export type InquiryFormOptions = {
  services: { code: string; label: string }[];
  budgets: { id: string; label: string; currency: string }[];
};

/** Service type, description, deliverables, budget and the wished-for date. */
export function ProjectFields({
  services,
  budgets,
  state,
  deadlineLabel = "Expected deadline (optional)",
  deadlineHint,
}: InquiryFormOptions & { state: FormState; deadlineLabel?: string; deadlineHint?: string }) {
  const err = (name: string) => state.fieldErrors?.[name]?.[0];
  return (
    <>
      <div className="grid gap-2">
        <Label htmlFor="serviceType">Type of editing</Label>
        <select
          id="serviceType"
          name="serviceType"
          className={selectClass}
          defaultValue={state.values?.serviceType ?? ""}
          aria-invalid={err("serviceType") ? true : undefined}
          aria-describedby={err("serviceType") ? "serviceType-error" : undefined}
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
          <p id="serviceType-error" className="text-destructive text-sm">
            {err("serviceType")}
          </p>
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
          label={deadlineLabel}
          hint={deadlineHint}
          type="date"
          state={state}
        />
      </div>
    </>
  );
}

/** Reference links (https only, up to MAX_REFERENCE_LINKS). Kept in state across failed submits. */
export function ReferenceLinksFields({ state }: { state: FormState }) {
  const [links, setLinks] = useState([{ url: "", label: "" }]);
  const err = state.fieldErrors?.links?.[0];
  return (
    <>
      {links.map((link, index) => (
        <div key={index} className="grid gap-2 sm:grid-cols-[2fr_1fr_auto] sm:items-end">
          <div className="grid min-w-0 gap-1">
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
              aria-invalid={err ? true : undefined}
              aria-describedby={err ? "links-error" : undefined}
              className={inputClass}
            />
          </div>
          <div className="grid min-w-0 gap-1">
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
      {err ? (
        <p id="links-error" className="text-destructive text-sm">
          {err}
        </p>
      ) : null}
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
    </>
  );
}
