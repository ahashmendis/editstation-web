import type { Metadata } from "next";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { Card, CardContent } from "@/components/ui/card";
import { ClientProjectForm } from "@/features/client-area/components/client-project-form";
import { getInquiryFormOptions } from "@/features/inquiries/queries";
import { requireClient } from "@/lib/auth/access";

export const metadata: Metadata = { title: "New project · Client · EDITSTATION" };

export default function ClientNewProjectPage() {
  return (
    <Suspense fallback={<Loading />}>
      <NewProject />
    </Suspense>
  );
}

async function NewProject() {
  await requireClient();
  const { services, budgets } = await getInquiryFormOptions();

  return (
    <AreaShell
      title="New project"
      subtitle="Tell the studio what you need. Your request is reviewed before any work starts."
    >
      <Card>
        <CardContent className="pt-6">
          <ClientProjectForm services={services} budgets={budgets} />
        </CardContent>
      </Card>
    </AreaShell>
  );
}
