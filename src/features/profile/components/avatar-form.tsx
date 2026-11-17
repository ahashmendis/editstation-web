"use client";

import { useActionState, useId } from "react";

import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { FormMessage } from "@/features/authentication/components/form-parts";
import { initialFormState } from "@/features/authentication/schemas";

import { removeAvatarAction, uploadAvatarAction } from "../actions";
import { AVATAR_ACCEPT, AVATAR_LIMITS_TEXT } from "../avatar";
import { UserAvatar } from "./user-avatar";

/** Upload, replace or remove the signed-in user's own picture. */
export function AvatarForm({
  url,
  name,
  email,
  hasPicture,
}: {
  url: string | null;
  name: string | null;
  email: string | null;
  hasPicture: boolean;
}) {
  const [uploadState, uploadAction, uploading] = useActionState(
    uploadAvatarAction,
    initialFormState,
  );
  const [removeState, removeAction, removing] = useActionState(
    removeAvatarAction,
    initialFormState,
  );
  const inputId = useId();
  const hintId = `${inputId}-hint`;
  const errorId = `${inputId}-error`;
  const fieldError = uploadState.fieldErrors?.avatar?.[0];
  const busy = uploading || removing;

  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap items-center gap-4">
        <UserAvatar
          url={url}
          name={name}
          email={email}
          size="xl"
          label={hasPicture ? "Your current picture" : "No picture yet; initials are shown"}
        />
        <p className="text-muted-foreground min-w-0 flex-1 text-sm">
          Shown only to you and to Lenscape Studios admins. Never to clients or other editors.
        </p>
      </div>

      <div aria-live="polite" className="grid gap-2">
        <FormMessage state={uploadState} />
        <FormMessage state={removeState} />
      </div>

      <form action={uploadAction} className="grid gap-3" noValidate>
        <div className="grid gap-2">
          <Label htmlFor={inputId}>{hasPicture ? "Replace picture" : "Upload a picture"}</Label>
          <input
            id={inputId}
            name="avatar"
            type="file"
            accept={AVATAR_ACCEPT}
            required
            aria-describedby={fieldError ? `${hintId} ${errorId}` : hintId}
            aria-invalid={fieldError ? true : undefined}
            className="border-input file:bg-muted file:text-foreground focus-visible:ring-ring w-full max-w-full min-w-0 rounded-md border bg-transparent text-sm file:mr-3 file:min-h-11 file:border-0 file:px-3 file:text-sm focus-visible:ring-2 focus-visible:outline-none"
          />
          <p id={hintId} className="text-muted-foreground text-xs">
            {AVATAR_LIMITS_TEXT} Square pictures look best.
          </p>
          {fieldError ? (
            <p id={errorId} className="text-destructive text-sm">
              {fieldError}
            </p>
          ) : null}
        </div>
        <Button type="submit" className="min-h-11 justify-self-start" disabled={busy}>
          {uploading ? "Uploading…" : hasPicture ? "Replace picture" : "Upload picture"}
        </Button>
      </form>

      {hasPicture ? (
        <form action={removeAction}>
          <Button type="submit" variant="outline" className="min-h-11" disabled={busy}>
            {removing ? "Removing…" : "Remove picture"}
          </Button>
        </form>
      ) : null}
    </div>
  );
}
