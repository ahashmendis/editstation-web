"use server";

import { refresh } from "next/cache";

import { userMessageFromDbError } from "@/features/applications/db-errors";
import type { FormState } from "@/features/authentication/schemas";
import { requireSignedIn } from "@/lib/auth/access";
import { createClient } from "@/lib/supabase/server";

import { AVATAR_BUCKET, AVATAR_TYPES, avatarPath, avatarPathsFor, detectImageType } from "./avatar";
import { avatarUploadSchema } from "./schemas";

const UPLOAD_FAILED = "The picture could not be uploaded. Please try again.";

/**
 * Upload or replace the signed-in user's picture. Checks the declared type and size, then the
 * file's real type from its bytes, uploads with the user's own session (storage RLS limits it to
 * their own folder), then records it with public.set_my_avatar. No server-side image processing.
 */
export async function uploadAvatarAction(_prev: FormState, formData: FormData): Promise<FormState> {
  const access = await requireSignedIn();
  const parsed = avatarUploadSchema.safeParse({ avatar: formData.get("avatar") });
  if (!parsed.success) {
    const message = parsed.error.issues[0]?.message ?? "Choose a picture to upload.";
    return { status: "error", message, fieldErrors: { avatar: [message] } };
  }
  const file = parsed.data.avatar;

  const bytes = new Uint8Array(await file.arrayBuffer());
  const ext = detectImageType(bytes);
  if (!ext) {
    const message = "That file is not a JPEG, PNG or WebP picture.";
    return { status: "error", message, fieldErrors: { avatar: [message] } };
  }

  const supabase = await createClient();
  const path = avatarPath(access.userId, ext);
  const current = await supabase
    .from("profiles")
    .select("avatar_path")
    .eq("id", access.userId)
    .maybeSingle();
  if (current.error) return { status: "error", message: userMessageFromDbError(current.error) };
  const previous = current.data?.avatar_path ?? null;

  const bucket = supabase.storage.from(AVATAR_BUCKET);
  const uploaded = await bucket
    .upload(path, bytes, { contentType: AVATAR_TYPES[ext], upsert: true, cacheControl: "60" })
    .catch(() => ({ error: true }));
  if (uploaded.error) return { status: "error", message: UPLOAD_FAILED };

  const saved = await supabase.rpc("set_my_avatar", { p_path: path });
  if (saved.error) {
    // Don't leave an unused object behind (never the picture still in use).
    if (path !== previous) await bucket.remove([path]).catch(() => undefined);
    return { status: "error", message: userMessageFromDbError(saved.error) };
  }

  // Pictures with the other extensions are now stale (an earlier save, a failed attempt or a
  // direct Storage upload): always remove them. Best effort, own folder only (storage RLS).
  const stale = avatarPathsFor(access.userId).filter((p) => p !== path);
  await bucket.remove(stale).catch(() => undefined);

  refresh();
  return { status: "success", message: "Your picture is saved." };
}

/** Remove the signed-in user's picture: clear the reference, then delete their objects. */
export async function removeAvatarAction(): Promise<FormState> {
  const access = await requireSignedIn();
  const supabase = await createClient();
  const cleared = await supabase.rpc("clear_my_avatar");
  if (cleared.error) return { status: "error", message: userMessageFromDbError(cleared.error) };
  await supabase.storage
    .from(AVATAR_BUCKET)
    .remove(avatarPathsFor(access.userId))
    .catch(() => undefined);
  refresh();
  return { status: "success", message: "Your picture is removed." };
}
