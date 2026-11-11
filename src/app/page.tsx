import Link from "next/link";

import { PublicPage } from "@/components/site-chrome";
import { buttonVariants } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

// Public home (Phase 3). Placeholder copy (decision S); the positioning line and descriptor
// are the working suggestions from KB §2.1, pending brand clearance (KB2).
export default function Home() {
  return (
    <PublicPage>
      <section className="mx-auto grid w-full max-w-5xl gap-6 px-4 py-16 sm:py-24">
        <p className="text-muted-foreground text-sm font-medium tracking-widest uppercase">
          A Lenscape Studios production network
        </p>
        <h1 className="max-w-3xl text-4xl font-semibold tracking-tight sm:text-5xl">
          Where every edit comes together.
        </h1>
        <p className="text-muted-foreground max-w-2xl text-lg">
          Lenscape Studios works with a vetted network of video editors in Sri Lanka. Send us your
          project and we&apos;ll take care of the edit, from brief to final delivery.
        </p>
        <div className="flex flex-wrap gap-3">
          <Link href="/inquire" className={buttonVariants({ size: "lg" })}>
            Send us a project
          </Link>
          <Link href="/sign-up" className={buttonVariants({ size: "lg", variant: "outline" })}>
            Join the editor network
          </Link>
        </div>
      </section>

      <section className="mx-auto grid w-full max-w-5xl gap-4 px-4 pb-20 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>For clients and agencies</CardTitle>
            <CardDescription>
              Tell us what you need. We review every inquiry, discuss scope, timing and pricing with
              you, and manage the edit and quality checks through to delivery. You work with
              Lenscape Studios throughout.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Link href="/inquire" className={buttonVariants({ variant: "outline" })}>
              Start an inquiry
            </Link>
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>For video editors</CardTitle>
            <CardDescription>
              Create an account and apply with your portfolio. Every application is reviewed by our
              team; approved editors are invited to suitable projects. This isn&apos;t an open
              marketplace or a bidding platform.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Link href="/sign-up" className={buttonVariants({ variant: "outline" })}>
              Apply to join
            </Link>
          </CardContent>
        </Card>
      </section>
    </PublicPage>
  );
}
