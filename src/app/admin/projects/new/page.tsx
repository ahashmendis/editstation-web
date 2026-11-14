import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { SignOutButton } from "@/components/sign-out-button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { CreateProjectForm } from "@/features/projects/components/project-forms";
import { getProjectFormOptions } from "@/features/projects/queries";
import { requireAdmin } from "@/lib/auth/access";

export const metadata: Metadata = { title: "New project · Admin · EDITSTATION" };

export default function NewProjectPage() {
  return (
    <Suspense fallback={<Loading />}>
      <NewProjectContent />
    </Suspense>
  );
}

async function NewProjectContent() {
  await requireAdmin();
  const { services, clients } = await getProjectFormOptions();
  return (
    <AreaShell title="New project" actions={<SignOutButton />}>
      <Link href="/admin/projects" className="text-muted-foreground text-sm underline">
        ← All projects
      </Link>
      <Card>
        <CardHeader>
          <CardTitle>Project and brief</CardTitle>
          <CardDescription>
            The project starts as a draft. Editors cannot see it. To start from an inquiry, use
            Convert to project on the inquiry page instead.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <CreateProjectForm services={services} clients={clients} />
        </CardContent>
      </Card>
    </AreaShell>
  );
}
