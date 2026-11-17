import type { Metadata } from "next";
import { Suspense } from "react";

import { Loading } from "@/components/auth-shell";
import { PublicPage } from "@/components/site-chrome";
import { Card, CardContent } from "@/components/ui/card";
import { JsonLd, breadcrumbJsonLd } from "@/lib/seo/json-ld";
import { pageMetadata } from "@/lib/seo/site";
import { InquiryForm } from "@/features/inquiries/components/inquiry-form";
import { getInquiryFormOptions } from "@/features/inquiries/queries";

export const metadata: Metadata = pageMetadata({
  title: "Send us your video editing project · EDITSTATION",
  description:
    "Tell us about your video editing project. No account needed. A vetted editor is matched and the work is managed from brief to delivery.",
  path: "/inquire",
});

export default function InquirePage() {
  return (
    <PublicPage>
      <JsonLd data={breadcrumbJsonLd("Send a project", "/inquire")} />
      <div className="mx-auto grid w-full max-w-3xl gap-6 px-4 py-12">
        <div className="grid gap-2">
          <h1 className="text-3xl font-semibold tracking-tight">Send us a project</h1>
          <p className="text-muted-foreground">
            Tell us what you need. No account required. We&apos;ll get back to you to discuss the
            details.
          </p>
        </div>
        <Card>
          <CardContent className="pt-6">
            <Suspense fallback={<Loading />}>
              <InquiryFormWithOptions />
            </Suspense>
          </CardContent>
        </Card>
      </div>
    </PublicPage>
  );
}

async function InquiryFormWithOptions() {
  const { services, budgets } = await getInquiryFormOptions();
  return <InquiryForm services={services} budgets={budgets} />;
}
