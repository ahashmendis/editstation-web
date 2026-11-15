"use client";

import { useActionState } from "react";

import { Button } from "@/components/ui/button";

import {
  markAllNotificationsReadAction,
  markNotificationReadAction,
  type MarkState,
} from "../actions";

const idle: MarkState = { status: "idle" };

export function MarkReadButton({ id, title }: { id: string; title: string }) {
  const [state, action, pending] = useActionState(markNotificationReadAction, idle);
  return (
    <form action={action} className="grid justify-items-end gap-1">
      <input type="hidden" name="id" value={id} />
      <Button
        type="submit"
        variant="outline"
        size="sm"
        className="min-h-9"
        disabled={pending}
        aria-label={`Mark "${title}" read`}
      >
        {pending ? "Marking…" : "Mark read"}
      </Button>
      {state.status === "error" ? (
        <p role="alert" className="text-destructive text-xs">
          {state.message}
        </p>
      ) : null}
    </form>
  );
}

export function MarkAllReadButton() {
  const [state, action, pending] = useActionState(markAllNotificationsReadAction, idle);
  return (
    <form action={action} className="flex flex-wrap items-center gap-2">
      <Button type="submit" variant="outline" className="min-h-11" disabled={pending}>
        {pending ? "Marking…" : "Mark all read"}
      </Button>
      <p
        role={state.status === "error" ? "alert" : "status"}
        className={
          state.status === "error" ? "text-destructive text-sm" : "text-muted-foreground text-sm"
        }
      >
        {state.message}
      </p>
    </form>
  );
}
