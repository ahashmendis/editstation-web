// Shared class strings for the landing page. Plain classes (not the shadcn Button) because its
// `dark:` variants follow the system theme, while the landing page is always light.

const ctaBase =
  "font-landing-ui inline-flex items-center justify-center gap-2 rounded-full font-bold whitespace-nowrap outline-none transition-[background-color,border-color,transform] duration-200 ease-out focus-visible:ring-4 focus-visible:ring-ring/40 active:translate-y-px motion-reduce:transition-none";

export const ctaSize = {
  sm: "h-10 px-4 text-[0.8125rem]",
  lg: "h-12 px-6 text-[0.9375rem]",
} as const;

/** Primary entry point: "Join as an editor" (owner decision 9). */
export const ctaPrimary = `${ctaBase} bg-primary text-primary-foreground hover:bg-[color-mix(in_oklch,var(--primary),black_14%)]`;

/** Secondary entry point: "Start a project". */
export const ctaSecondary = `${ctaBase} border border-foreground/15 bg-card text-foreground hover:border-foreground/35`;

export const sectionTitle =
  "font-landing-serif text-[2.5rem] leading-[1.02] font-medium tracking-[-0.01em] text-balance lg:text-[3.5rem]";

export const sectionLead = "text-muted-foreground text-lg font-light text-pretty";

export const eyebrow =
  "font-landing-ui text-brand-text text-xs font-bold tracking-[0.14em] uppercase";

export const container = "mx-auto w-full max-w-6xl px-4 md:px-6";

export const focusRing = "rounded-md outline-none focus-visible:ring-4 focus-visible:ring-ring/40";
