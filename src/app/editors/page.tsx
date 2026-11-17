import type { Metadata } from "next";
import Link from "next/link";

import { PublicPage } from "@/components/site-chrome";
import { buttonVariants } from "@/components/ui/button";
import { JsonLd, breadcrumbJsonLd } from "@/lib/seo/json-ld";
import { pageMetadata } from "@/lib/seo/site";

// Public page for editor recruitment searches. The application itself lives behind sign-in
// (/apply), so this page explains the process using only rules already built and documented
// (docs/BUSINESS_RULES.md, docs/WORKFLOWS.md). No eligibility criteria, pay figures or volumes are
// stated because none are set.
export const metadata: Metadata = pageMetadata({
  title: "Join as a freelance video editor · EDITSTATION",
  description:
    "Apply to join EDITSTATION's vetted network of freelance video editors. See how applications, vetting and project opportunities work.",
  path: "/editors",
});

const STEPS = [
  {
    title: "Create an account and your editor profile",
    body: "Add your experience, the software you use, your availability, your usual turnaround and links to your portfolio.",
  },
  {
    title: "Submit your application",
    body: "An admin reviews your portfolio. A review may include further steps, such as a practical test or a short interview.",
  },
  {
    title: "Approval or decline",
    body: "Registering gives you no access to work. Access to projects starts only if an admin approves your application.",
  },
];

export default function EditorsPage() {
  return (
    <PublicPage>
      <JsonLd data={breadcrumbJsonLd("Join as an editor", "/editors")} />
      <article className="mx-auto grid w-full max-w-3xl gap-10 px-4 py-12">
        <header className="grid gap-3">
          <h1 className="text-3xl font-semibold tracking-tight">
            Join EDITSTATION as a freelance video editor
          </h1>
          <p className="text-muted-foreground">
            EDITSTATION is a managed network of vetted freelance video editors, run by Lenscape
            Studios. Every application is reviewed, work is offered to editors by the studio, and
            each project is managed from brief to delivery. There is no open bidding.
          </p>
        </header>

        <section aria-labelledby="who-title" className="grid gap-3">
          <h2 id="who-title" className="text-xl font-semibold">
            Who can apply
          </h2>
          <p>
            Video editors with a portfolio of their work. The application asks about your
            experience, tools and availability, so the studio can judge whether your work fits the
            projects it takes on.
          </p>
        </section>

        <section aria-labelledby="steps-title" className="grid gap-4">
          <h2 id="steps-title" className="text-xl font-semibold">
            How applying works
          </h2>
          <ol className="grid gap-4">
            {STEPS.map((step, index) => (
              <li key={step.title} className="grid gap-1">
                <h3 className="font-medium">
                  {index + 1}. {step.title}
                </h3>
                <p className="text-muted-foreground">{step.body}</p>
              </li>
            ))}
          </ol>
        </section>

        <section aria-labelledby="work-title" className="grid gap-3">
          <h2 id="work-title" className="text-xl font-semibold">
            How work is offered
          </h2>
          <p>
            Approved editors can see short summaries of open opportunities, without client names,
            prices or files, and register interest. The studio chooses an editor and sends an offer,
            or invites an editor directly. Your pay for a project is agreed and approved before any
            editing starts, and you see the brief and files only for work you are assigned.
          </p>
        </section>

        <section aria-labelledby="expect-title" className="grid gap-3">
          <h2 id="expect-title" className="text-xl font-semibold">
            What to expect
          </h2>
          <p>
            Applying does not guarantee approval, and approval does not guarantee projects. Work
            depends on what the studio has available and on who fits it best.
          </p>
        </section>

        <div className="flex flex-wrap items-center gap-3">
          <Link href="/sign-up" className={buttonVariants()}>
            Create your editor account
          </Link>
          <p className="text-muted-foreground text-sm">
            Need an editor instead?{" "}
            <Link href="/inquire" className="underline">
              Send us a project
            </Link>
            .
          </p>
        </div>
      </article>
    </PublicPage>
  );
}
