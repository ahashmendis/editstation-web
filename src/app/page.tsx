import type { Metadata } from "next";

import { ClientsSection } from "@/features/landing/components/clients-section";
import { ClientsMarquee } from "@/features/landing/components/clients-marquee";
import { ClosingCta } from "@/features/landing/components/closing-cta";
import { Hero } from "@/features/landing/components/hero";
import { LandingFooter } from "@/features/landing/components/landing-footer";
import { LandingHeader } from "@/features/landing/components/landing-header";
import { Platform } from "@/features/landing/components/platform";
import { Process } from "@/features/landing/components/process";
import { Transparency } from "@/features/landing/components/transparency";
import { WorkSection } from "@/features/landing/components/work-section";
import { landingFontVariables } from "@/features/landing/fonts";
import { WORK } from "@/features/landing/work";
import { JsonLd, organizationJsonLd } from "@/lib/seo/json-ld";
import { pageMetadata } from "@/lib/seo/site";

export const metadata: Metadata = pageMetadata({
  title: "EDITSTATION: professional video editing, managed end to end",
  description:
    "EDITSTATION, a Lenscape Studios production network, matches video editing projects with vetted freelance editors and manages the work from brief to delivery.",
  path: "/",
});

// Public home (plan docs/superpowers/plans/2026-11-15-landing-page-upgrade.md, section 10).
// Light base with the brand purple whatever the system theme (`.landing` scopes the tokens in
// globals.css); IBM Plex Serif / DM Sans / Manrope on this page only. Copy states real product
// rules only: no invented figures, testimonials or prices. Two entry points: "Join as an
// editor" (/apply, primary) and "Start a project" (/inquire).
export default function Home() {
  const hasWork = WORK.length > 0;
  return (
    <div
      className={`landing ${landingFontVariables} bg-background text-foreground font-landing-sans flex min-h-full flex-1 flex-col`}
    >
      <JsonLd data={organizationJsonLd()} />
      <LandingHeader showWork={hasWork} />
      <main id="main" className="flex-1">
        <Hero />
        <ClientsMarquee />
        <WorkSection items={WORK} />
        <Platform />
        <ClientsSection />
        <Transparency />
        <Process />
        <ClosingCta />
      </main>
      <LandingFooter />
    </div>
  );
}
