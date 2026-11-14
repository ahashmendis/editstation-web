"use client";

import { useActionState, useState, useTransition } from "react";

import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Input } from "@/components/ui/input";
import { Field, FormMessage, TextareaField } from "@/features/authentication/components/form-parts";
import { initialFormState, type FormState } from "@/features/authentication/schemas";

import { createProjectAction, saveBriefAction, updateProjectAction } from "../admin-actions";
import { selectClassName } from "./select-class";
import { BRIEF_TYPES, BRIEF_TYPE_HINT, BRIEF_TYPE_LABEL, type BriefType } from "../constants";
import {
  DeliverablesEditor,
  ReferencesEditor,
  type DeliverableRow,
  type ReferenceRow,
} from "./row-editors";

export type ServiceOption = { code: string; label: string; active: boolean };
export type ClientOption = { id: string; name: string; company: string | null; email: string };

export type DetailsDefaults = {
  title: string;
  briefType: BriefType;
  serviceTypeCode: string;
  summary: string;
  deadline: string;
  requiresInterpretation: "" | "yes" | "no";
  proposedAmount: string;
  proposedCurrency: string;
  revisionAllowance: string;
  clientId: string;
  clientPrice: string;
  clientPriceCurrency: string;
  internalNotes: string;
};

export type BriefDefaults = {
  instructions: string;
  desiredOutcome: string;
  audience: string;
  coreMessage: string;
  brandConstraints: string;
  mandatoryContent: string;
  prohibitedContent: string;
};

export const emptyDetails: DetailsDefaults = {
  title: "",
  briefType: "fully_instructed",
  serviceTypeCode: "",
  summary: "",
  deadline: "",
  requiresInterpretation: "",
  proposedAmount: "",
  proposedCurrency: "LKR",
  revisionAllowance: "3",
  clientId: "",
  clientPrice: "",
  clientPriceCurrency: "LKR",
  internalNotes: "",
};

export const emptyBrief: BriefDefaults = {
  instructions: "",
  desiredOutcome: "",
  audience: "",
  coreMessage: "",
  brandConstraints: "",
  mandatoryContent: "",
  prohibitedContent: "",
};

function Select({
  name,
  label,
  state,
  defaultValue,
  children,
  hint,
  onChange,
  value,
}: {
  name: string;
  label: string;
  state: FormState;
  defaultValue?: string;
  children: React.ReactNode;
  hint?: string;
  onChange?: (value: string) => void;
  value?: string;
}) {
  const errors = state.fieldErrors?.[name];
  const controlled = value !== undefined;
  return (
    <div className="grid gap-2">
      <Label htmlFor={name}>{label}</Label>
      <select
        id={name}
        name={name}
        className={selectClassName}
        aria-invalid={errors?.length ? true : undefined}
        aria-describedby={errors?.length ? `${name}-error` : hint ? `${name}-hint` : undefined}
        {...(controlled
          ? { value, onChange: (e) => onChange?.(e.target.value) }
          : { defaultValue: state.values?.[name] ?? defaultValue })}
      >
        {children}
      </select>
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

function DetailsFields({
  state,
  d,
  services,
  clients,
  briefType,
  onBriefType,
}: {
  state: FormState;
  d: DetailsDefaults;
  services: ServiceOption[];
  clients: ClientOption[];
  briefType: BriefType;
  onBriefType: (value: BriefType) => void;
}) {
  const v = (name: keyof DetailsDefaults) => state.values?.[name] ?? d[name];
  return (
    <div className="grid gap-4">
      <Field name="title" label="Title" required defaultValue={v("title")} state={state} />
      <div className="grid gap-4 sm:grid-cols-2">
        <Select
          name="briefType"
          label="Brief type"
          state={state}
          value={briefType}
          onChange={(value) => onBriefType(value as BriefType)}
          hint={BRIEF_TYPE_HINT[briefType]}
        >
          {BRIEF_TYPES.map((t) => (
            <option key={t} value={t}>
              {BRIEF_TYPE_LABEL[t]}
            </option>
          ))}
        </Select>
        <Select
          name="serviceTypeCode"
          label="Type of service"
          state={state}
          defaultValue={d.serviceTypeCode}
        >
          <option value="" disabled>
            Choose…
          </option>
          {services
            .filter((s) => s.active || s.code === d.serviceTypeCode)
            .map((s) => (
              <option key={s.code} value={s.code}>
                {s.label}
              </option>
            ))}
        </Select>
      </div>
      <TextareaField
        name="summary"
        label="Summary"
        hint="A short description. Editors may see this later."
        defaultValue={v("summary")}
        state={state}
      />
      <div className="grid gap-4 sm:grid-cols-2">
        <Field
          name="deadline"
          label="Deadline"
          type="date"
          defaultValue={v("deadline")}
          state={state}
        />
        <Select
          name="requiresInterpretation"
          label="Needs creative interpretation"
          state={state}
          defaultValue={d.requiresInterpretation}
        >
          <option value="">Default for the brief type</option>
          <option value="yes">Yes</option>
          <option value="no">No</option>
        </Select>
        <Field
          name="proposedAmount"
          label="Proposed editor pay"
          inputMode="text"
          hint="Not agreed until the editor accepts. Leave empty if undecided."
          defaultValue={v("proposedAmount")}
          state={state}
        />
        <Field
          name="proposedCurrency"
          label="Pay currency"
          defaultValue={v("proposedCurrency")}
          state={state}
        />
        <Field
          name="revisionAllowance"
          label="Free revision rounds"
          inputMode="numeric"
          defaultValue={v("revisionAllowance")}
          state={state}
        />
      </div>

      <fieldset className="grid gap-4 rounded-lg border p-3">
        <legend className="px-1 text-sm font-medium">Admin only: client and price</legend>
        <Select name="clientId" label="Client" state={state} defaultValue={d.clientId}>
          <option value="">No client</option>
          {clients.map((c) => (
            <option key={c.id} value={c.id}>
              {[c.name, c.company].filter(Boolean).join(", ")} ({c.email})
            </option>
          ))}
        </Select>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field
            name="clientPrice"
            label="Client price"
            defaultValue={v("clientPrice")}
            state={state}
          />
          <Field
            name="clientPriceCurrency"
            label="Client price currency"
            defaultValue={v("clientPriceCurrency")}
            state={state}
          />
        </div>
        <TextareaField
          name="internalNotes"
          label="Internal notes"
          hint="Never shown to editors or clients."
          defaultValue={v("internalNotes")}
          state={state}
        />
      </fieldset>
    </div>
  );
}

function BriefTextFields({
  state,
  b,
  briefType,
}: {
  state: FormState;
  b: BriefDefaults;
  briefType: BriefType;
}) {
  const v = (name: keyof BriefDefaults) => state.values?.[name] ?? b[name];
  const creative = briefType === "creative_led";
  return (
    <div className="grid gap-4">
      <TextareaField
        name="instructions"
        label={creative ? "Instructions (optional)" : "Instructions"}
        hint={
          briefType === "fully_instructed"
            ? "Required to open the project."
            : "Extra directions for the editor."
        }
        defaultValue={v("instructions")}
        state={state}
      />
      {/* Hidden, not removed, so switching brief type keeps what was typed. */}
      <div hidden={!creative} className="grid gap-4">
        <TextareaField
          name="desiredOutcome"
          label="Desired outcome"
          hint="Required to open a creative-led project."
          defaultValue={v("desiredOutcome")}
          state={state}
        />
        <TextareaField
          name="audience"
          label="Audience"
          defaultValue={v("audience")}
          state={state}
        />
        <TextareaField
          name="coreMessage"
          label="Core message"
          defaultValue={v("coreMessage")}
          state={state}
        />
        <TextareaField
          name="brandConstraints"
          label="Brand constraints"
          defaultValue={v("brandConstraints")}
          state={state}
        />
        <TextareaField
          name="mandatoryContent"
          label="Mandatory content"
          defaultValue={v("mandatoryContent")}
          state={state}
        />
        <TextareaField
          name="prohibitedContent"
          label="Prohibited content"
          defaultValue={v("prohibitedContent")}
          state={state}
        />
      </div>
    </div>
  );
}

function SubmitRow({ pending, label }: { pending: boolean; label: string }) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      <Button type="submit" disabled={pending}>
        {pending ? "Saving…" : label}
      </Button>
    </div>
  );
}

function Messages({ state }: { state: FormState }) {
  return (
    <>
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
    </>
  );
}

/** New project: details, brief, deliverables and references in one atomic save. */
export function CreateProjectForm({
  services,
  clients,
  details = emptyDetails,
  brief = emptyBrief,
}: {
  services: ServiceOption[];
  clients: ClientOption[];
  details?: DetailsDefaults;
  brief?: BriefDefaults;
}) {
  const [state, formAction, pending] = useActionState(createProjectAction, initialFormState);
  const [, startTransition] = useTransition();
  const [briefType, setBriefType] = useState<BriefType>(details.briefType);
  return (
    <form
      onSubmit={submitWithoutReset(formAction, startTransition)}
      className="grid gap-6"
      noValidate
    >
      <Messages state={state} />
      <DetailsFields
        state={state}
        d={details}
        services={services}
        clients={clients}
        briefType={briefType}
        onBriefType={setBriefType}
      />
      <BriefTextFields state={state} b={brief} briefType={briefType} />
      <DeliverablesEditor initial={[]} />
      <ReferencesEditor initial={[]} />
      <SubmitRow pending={pending} label="Create draft project" />
    </form>
  );
}

/** Project details only. Saving here never creates a brief version. */
export function EditDetailsForm({
  projectId,
  services,
  clients,
  details,
  locked,
  briefTypeLocked,
}: {
  projectId: string;
  services: ServiceOption[];
  clients: ClientOption[];
  details: DetailsDefaults;
  locked: boolean;
  briefTypeLocked: boolean;
}) {
  const [state, formAction, pending] = useActionState(updateProjectAction, initialFormState);
  const [, startTransition] = useTransition();
  const [briefType, setBriefType] = useState<BriefType>(details.briefType);
  return (
    <form
      onSubmit={submitWithoutReset(formAction, startTransition)}
      className="grid gap-6"
      noValidate
    >
      <input type="hidden" name="projectId" value={projectId} />
      <Messages state={state} />
      <DetailsFields
        state={state}
        d={details}
        services={services}
        clients={clients}
        briefType={briefType}
        onBriefType={setBriefType}
      />
      {briefTypeLocked ? (
        <p className="text-muted-foreground text-sm">
          The brief type cannot change once a project has been opened.
        </p>
      ) : null}
      {locked ? (
        <p className="text-muted-foreground text-sm">This project can no longer be edited.</p>
      ) : (
        <SubmitRow pending={pending} label="Save details" />
      )}
    </form>
  );
}

/** Brief editor: instructions, deliverables and references, saved together. */
export function BriefEditorForm({
  projectId,
  briefType,
  brief,
  deliverables,
  references,
  currentVersion,
  opened,
  locked,
}: {
  projectId: string;
  briefType: BriefType;
  brief: BriefDefaults;
  deliverables: DeliverableRow[];
  references: ReferenceRow[];
  currentVersion: number;
  opened: boolean;
  locked: boolean;
}) {
  const [state, formAction, pending] = useActionState(saveBriefAction, initialFormState);
  const [, startTransition] = useTransition();
  return (
    <form
      onSubmit={submitWithoutReset(formAction, startTransition)}
      className="grid gap-6"
      noValidate
    >
      <input type="hidden" name="projectId" value={projectId} />
      <Messages state={state} />
      <p className="text-sm">
        Current version: <strong>{currentVersion}</strong>.{" "}
        <span className="text-muted-foreground">
          {opened
            ? "This project has been opened, so any change saves as a new version and the old one is kept."
            : "This project has not been opened yet, so changes update version 1 in place."}
        </span>
      </p>
      <BriefTextFields state={state} b={brief} briefType={briefType} />
      <DeliverablesEditor initial={deliverables} />
      <ReferencesEditor initial={references} />
      {opened ? (
        <fieldset className="grid gap-3 rounded-lg border p-3">
          <legend className="px-1 text-sm font-medium">About this change</legend>
          <div className="grid gap-2">
            <Label htmlFor="changeSummary">What changed and why</Label>
            <Textarea
              id="changeSummary"
              name="changeSummary"
              rows={2}
              maxLength={1000}
              defaultValue={state.values?.changeSummary}
            />
            <p className="text-muted-foreground text-sm">Required when the content changes.</p>
          </div>
          <label className="flex items-start gap-2 text-sm">
            <Input
              type="checkbox"
              name="requiresReacknowledgement"
              defaultChecked
              className="mt-0.5 size-4 shrink-0"
            />
            <span>
              Editors must confirm the new version again. Changed deliverables always require it.
            </span>
          </label>
        </fieldset>
      ) : null}
      {locked ? (
        <p className="text-muted-foreground text-sm">This project can no longer be edited.</p>
      ) : (
        <SubmitRow pending={pending} label="Save brief" />
      )}
    </form>
  );
}

// React resets a form after an action submitted through `action={...}`, which wipes selects
// (controlled or not) on a validation error. Submitting from onSubmit inside a transition keeps
// every field as the admin left it while still driving useActionState.
function submitWithoutReset(
  formAction: (formData: FormData) => void,
  startTransition: React.TransitionStartFunction,
) {
  return (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const formData = new FormData(event.currentTarget);
    startTransition(() => formAction(formData));
  };
}
