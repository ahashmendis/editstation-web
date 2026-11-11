import { z } from "zod";

// Mirrors supabase/config.toml: minimum_password_length = 10, letters_digits.
export const PASSWORD_MIN_LENGTH = 10;

export const emailSchema = z
  .string()
  .trim()
  .toLowerCase()
  .pipe(z.email({ error: "Enter a valid email address." }).max(254));

export const passwordSchema = z
  .string()
  .min(PASSWORD_MIN_LENGTH, { error: `Use at least ${PASSWORD_MIN_LENGTH} characters.` })
  .max(128, { error: "Use at most 128 characters." })
  .regex(/[A-Za-z]/, { error: "Include at least one letter." })
  .regex(/[0-9]/, { error: "Include at least one number." });

export const signUpSchema = z
  .object({
    email: emailSchema,
    password: passwordSchema,
    confirmPassword: z.string(),
  })
  .refine((data) => data.password === data.confirmPassword, {
    error: "Passwords do not match.",
    path: ["confirmPassword"],
  });

export const signInSchema = z.object({
  email: emailSchema,
  // Don't apply strength rules at sign-in; just require something.
  password: z.string().min(1, { error: "Enter your password." }).max(128),
});

export const passwordResetRequestSchema = z.object({ email: emailSchema });

export const newPasswordSchema = z
  .object({ password: passwordSchema, confirmPassword: z.string() })
  .refine((data) => data.password === data.confirmPassword, {
    error: "Passwords do not match.",
    path: ["confirmPassword"],
  });

export const totpCodeSchema = z.object({
  code: z
    .string()
    .trim()
    .regex(/^\d{6}$/, { error: "Enter the 6-digit code from your authenticator app." }),
});

export type FormState = {
  status: "idle" | "error" | "success";
  message?: string;
  fieldErrors?: Partial<Record<string, string[]>>;
  /** Echoed non-secret input so React's post-submit form reset doesn't wipe it. */
  values?: Partial<Record<string, string>>;
};

export const initialFormState: FormState = { status: "idle" };

export function validationError(error: z.ZodError, values?: FormState["values"]): FormState {
  return {
    status: "error",
    message: "Please fix the highlighted fields.",
    fieldErrors: z.flattenError(error).fieldErrors as Partial<Record<string, string[]>>,
    values,
  };
}

/** Non-secret fields to refill after a failed submit. Never include passwords or codes. */
export function keptValues(formData: FormData): FormState["values"] {
  const email = formData.get("email");
  return typeof email === "string" ? { email: email.slice(0, 254) } : undefined;
}
