"use client";

import { useSearchParams } from "next/navigation";
import { useActionState, useState } from "react";

import { Button } from "@/components/ui/button";
import { Field, FormMessage } from "@/features/authentication/components/form-parts";
import { initialFormState, type FormState } from "@/features/authentication/schemas";

import { requestClientCodeAction, verifyClientCodeAction } from "../actions";

/**
 * Two steps: request a code by email, then enter the 8-digit code. The second step appears after
 * any request, with the same message whether or not the email has access.
 */
export function ClientSignInForm() {
  const params = useSearchParams();
  const next = params.get("next") ?? "";
  const [requested, requestAction, requesting] = useActionState(
    requestClientCodeAction,
    initialFormState,
  );
  const [verified, verifyAction, verifying] = useActionState(
    verifyClientCodeAction,
    initialFormState,
  );
  // "Use a different email" returns to step 1 without a round trip.
  const [restartedFor, setRestartedFor] = useState<FormState | null>(null);

  const onCodeStep = requested.values?.step === "code" && restartedFor !== requested;
  const email = verified.values?.email ?? requested.values?.email ?? "";

  if (!onCodeStep) {
    return (
      <form action={requestAction} className="grid gap-4" noValidate>
        <FormMessage state={requested} />
        <Field
          name="email"
          label="Email"
          type="email"
          autoComplete="email"
          state={requested}
          required
        />
        <Button type="submit" disabled={requesting}>
          {requesting ? "Sending…" : "Email me a sign-in code"}
        </Button>
        <p className="text-muted-foreground text-sm">
          Client accounts are created by the studio. Use the email address the studio invited.
        </p>
      </form>
    );
  }

  return (
    <form action={verifyAction} className="grid gap-4" noValidate>
      <FormMessage state={verified.status === "idle" ? requested : verified} />
      <input type="hidden" name="email" value={email} />
      <input type="hidden" name="next" value={next} />
      <p className="text-sm break-words">
        Code sent to <span className="font-medium">{email}</span>
      </p>
      <Field
        name="code"
        label="8-digit code"
        inputMode="numeric"
        autoComplete="one-time-code"
        state={verified}
        required
      />
      <Button type="submit" disabled={verifying}>
        {verifying ? "Checking…" : "Sign in"}
      </Button>
      <Button type="button" variant="ghost" onClick={() => setRestartedFor(requested)}>
        Use a different email or send a new code
      </Button>
    </form>
  );
}
