import type { PostgrestError } from "@supabase/supabase-js";

/**
 * Our database functions raise ES4xx errors with user-safe messages (see the Phase 2
 * migration). Anything else is unexpected and must not leak details to the user.
 */
export function userMessageFromDbError(error: Pick<PostgrestError, "code" | "message">): string {
  if (/^ES4\d\d$/.test(error.code ?? "")) return error.message;
  return "Something went wrong. Please try again.";
}
