"use client";

import { useActionState, type ReactNode } from "react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { FormMessage } from "@/features/authentication/components/form-parts";
import { initialFormState, type FormState } from "@/features/authentication/schemas";

import {
  inviteClientUserAction,
  publishClientUpdateAction,
  setBankDetailsAction,
} from "../admin-actions";

// Admin forms that keep the typed text when the server refuses it (state.values), unlike the
// generic AdminActionForm. Messages come only from userMessageFromDbError or Zod. Ids are unique
// per record because several of these forms can be on one page.

function FieldShell({
  id,
  name,
  label,
  hint,
  state,
  children,
}: {
  id: string;
  name: string;
  label: string;
  hint: string;
  state: FormState;
  children: (props: {
    id: string;
    name: string;
    "aria-invalid"?: true;
    "aria-describedby": string;
  }) => ReactNode;
}) {
  const error = state.fieldErrors?.[name]?.[0];
  return (
    <div className="grid gap-2">
      <Label htmlFor={id}>{label}</Label>
      {children({
        id,
        name,
        "aria-invalid": error ? true : undefined,
        "aria-describedby": `${id}-note`,
      })}
      <p
        id={`${id}-note`}
        className={error ? "text-destructive text-sm" : "text-muted-foreground text-sm"}
      >
        {error ?? hint}
      </p>
    </div>
  );
}

/** The submitted text to show again: kept after an error, cleared after a success. */
function kept(state: FormState, name: string): string | undefined {
  return state.status === "error" ? state.values?.[name] : undefined;
}

export function InviteClientUserForm({ clientId }: { clientId: string }) {
  const [state, action, pending] = useActionState(inviteClientUserAction, initialFormState);
  return (
    <form action={action} className="grid gap-3" noValidate>
      <FormMessage state={state} />
      <input type="hidden" name="clientId" value={clientId} />
      <FieldShell
        id={`invite-email-${clientId}`}
        name="email"
        label="Email of the person to invite"
        hint="They sign in at /client/sign-in with a one-time code sent to this address."
        state={state}
      >
        {(props) => (
          <Input
            {...props}
            type="email"
            autoComplete="off"
            required
            defaultValue={kept(state, "email")}
          />
        )}
      </FieldShell>
      <Button type="submit" variant="outline" className="justify-self-start" disabled={pending}>
        {pending ? "Inviting…" : "Invite client user"}
      </Button>
    </form>
  );
}

export function PublishClientUpdateForm({ projectId }: { projectId: string }) {
  const [state, action, pending] = useActionState(publishClientUpdateAction, initialFormState);
  return (
    <form action={action} className="grid gap-3" noValidate>
      <FormMessage state={state} />
      <input type="hidden" name="projectId" value={projectId} />
      <FieldShell
        id={`client-update-${projectId}`}
        name="body"
        label="New update for the client"
        hint="Visible to the client as soon as you publish. Never mention the editor, pay or internal notes."
        state={state}
      >
        {(props) => <Textarea {...props} rows={4} required defaultValue={kept(state, "body")} />}
      </FieldShell>
      <Button type="submit" className="justify-self-start" disabled={pending}>
        {pending ? "Publishing…" : "Publish update"}
      </Button>
    </form>
  );
}

export function BankDetailsForm({ current }: { current: string }) {
  const [state, action, pending] = useActionState(setBankDetailsAction, initialFormState);
  return (
    <form action={action} className="grid gap-3" noValidate>
      <FormMessage state={state} />
      <FieldShell
        id="client-bank-details"
        name="details"
        label="Bank transfer details shown to clients"
        hint="Account name, bank, branch, account number and any SWIFT code. Leave empty to hide the panel."
        state={state}
      >
        {(props) => (
          <Textarea {...props} rows={5} defaultValue={kept(state, "details") ?? current} />
        )}
      </FieldShell>
      <Button type="submit" className="justify-self-start" disabled={pending}>
        {pending ? "Saving…" : "Save bank details"}
      </Button>
    </form>
  );
}
