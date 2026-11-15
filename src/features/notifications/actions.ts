"use server";

import { refresh, revalidatePath } from "next/cache";

import { userMessageFromDbError } from "@/features/applications/db-errors";
import { requireSignedIn } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

import { notificationIdSchema } from "./schemas";

export type MarkState = { status: "idle" | "success" | "error"; message?: string };

/** Marks one of the caller's notifications read (the database checks ownership). */
export async function markNotificationReadAction(
  _prev: MarkState,
  formData: FormData,
): Promise<MarkState> {
  await requireSignedIn();
  const parsed = notificationIdSchema.safeParse({ id: formData.get("id") });
  if (!parsed.success) return { status: "error", message: "Notification not found." };
  const supabase = await createClient();
  const { error } = await supabase.rpc("mark_notification_read", { p_id: parsed.data.id });
  if (error) return { status: "error", message: userMessageFromDbError(error) };
  revalidatePath("/notifications");
  refresh();
  return { status: "success" };
}

/** Marks every unread notification of the caller read. */
export async function markAllNotificationsReadAction(): Promise<MarkState> {
  await requireSignedIn();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("mark_all_notifications_read");
  if (error) return { status: "error", message: userMessageFromDbError(error) };
  revalidatePath("/notifications");
  refresh();
  return {
    status: "success",
    message: data === 1 ? "1 notification marked read." : `${data ?? 0} notifications marked read.`,
  };
}
