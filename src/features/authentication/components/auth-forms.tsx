"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useActionState } from "react";

import { Button } from "@/components/ui/button";

import {
  requestPasswordResetAction,
  signInAction,
  signUpAction,
  updatePasswordAction,
} from "../actions";
import { initialFormState, PASSWORD_MIN_LENGTH } from "../schemas";
import { Field, FormMessage } from "./form-parts";

const passwordHint = `At least ${PASSWORD_MIN_LENGTH} characters, with letters and numbers.`;

export function SignUpForm() {
  const [state, action, pending] = useActionState(signUpAction, initialFormState);

  if (state.status === "success") return <FormMessage state={state} />;

  return (
    <form action={action} className="grid gap-4" noValidate>
      <FormMessage state={state} />
      <Field name="email" label="Email" type="email" autoComplete="email" state={state} required />
      <Field
        name="password"
        label="Password"
        type="password"
        autoComplete="new-password"
        hint={passwordHint}
        state={state}
        required
      />
      <Field
        name="confirmPassword"
        label="Confirm password"
        type="password"
        autoComplete="new-password"
        state={state}
        required
      />
      <Button type="submit" disabled={pending}>
        {pending ? "Creating account…" : "Create account"}
      </Button>
      <p className="text-muted-foreground text-sm">
        Creating an account lets you apply. Editor access is granted only after our team approves
        your application.
      </p>
    </form>
  );
}

const linkErrors: Record<string, string> = {
  link: "That link is invalid or has expired. Please try again.",
};

export function SignInForm() {
  const params = useSearchParams();
  const [state, action, pending] = useActionState(signInAction, initialFormState);
  const linkError = linkErrors[params.get("error") ?? ""];

  return (
    <form action={action} className="grid gap-4" noValidate>
      {linkError && state.status === "idle" ? (
        <FormMessage state={{ status: "error", message: linkError }} />
      ) : (
        <FormMessage state={state} />
      )}
      <input type="hidden" name="next" value={params.get("next") ?? ""} />
      <Field name="email" label="Email" type="email" autoComplete="email" state={state} required />
      <Field
        name="password"
        label="Password"
        type="password"
        autoComplete="current-password"
        state={state}
        required
      />
      <Button type="submit" disabled={pending}>
        {pending ? "Signing in…" : "Sign in"}
      </Button>
      <Link href="/forgot-password" className="text-muted-foreground text-sm underline">
        Forgot your password?
      </Link>
    </form>
  );
}

export function ForgotPasswordForm() {
  const [state, action, pending] = useActionState(requestPasswordResetAction, initialFormState);

  if (state.status === "success") return <FormMessage state={state} />;

  return (
    <form action={action} className="grid gap-4" noValidate>
      <FormMessage state={state} />
      <Field name="email" label="Email" type="email" autoComplete="email" state={state} required />
      <Button type="submit" disabled={pending}>
        {pending ? "Sending…" : "Send reset link"}
      </Button>
    </form>
  );
}

export function ResetPasswordForm() {
  const [state, action, pending] = useActionState(updatePasswordAction, initialFormState);

  return (
    <form action={action} className="grid gap-4" noValidate>
      <FormMessage state={state} />
      <Field
        name="password"
        label="New password"
        type="password"
        autoComplete="new-password"
        hint={passwordHint}
        state={state}
        required
      />
      <Field
        name="confirmPassword"
        label="Confirm new password"
        type="password"
        autoComplete="new-password"
        state={state}
        required
      />
      <Button type="submit" disabled={pending}>
        {pending ? "Saving…" : "Save new password"}
      </Button>
    </form>
  );
}
