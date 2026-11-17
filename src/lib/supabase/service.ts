import "server-only";

import { createClient } from "@supabase/supabase-js";

import type { Database } from "./database.types";
import { supabaseUrl } from "./env";

/**
 * Supabase client with the secret (service) key. Two server-only callers: the email worker route
 * (src/app/api/cron/send-emails/route.ts), whose database functions accept only the service_role,
 * and the admin client-invitation action (src/features/client-area/admin-actions.ts), which only
 * creates (or, on refusal, deletes again) a password-less auth account after requireAdmin().
 * Never import this from client code or any user-facing page, and never give the key a
 * NEXT_PUBLIC_ name. No session is stored or refreshed.
 */
export function createServiceClient() {
  const key = process.env.SUPABASE_SECRET_KEY;
  if (!key) {
    throw new Error("SUPABASE_SECRET_KEY is not set.");
  }
  return createClient<Database>(supabaseUrl, key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}
