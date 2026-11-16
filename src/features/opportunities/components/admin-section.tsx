import { Suspense } from "react";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

import { getAdminOpportunity } from "../queries";
import { AdminOpportunityCard } from "./admin-card";

type Props = Omit<Parameters<typeof AdminOpportunityCard>[0], "opportunity" | "interests">;

/**
 * The opportunity card loads on its own so it never holds up the rest of the admin project page.
 * The page has already checked the admin (and the database function checks again).
 */
export function AdminOpportunitySection(props: Props) {
  return (
    <Suspense fallback={<OpportunityCardSkeleton />}>
      <OpportunityCardContent {...props} />
    </Suspense>
  );
}

async function OpportunityCardContent(props: Props) {
  const { opportunity, interests } = await getAdminOpportunity(props.projectId);
  return <AdminOpportunityCard {...props} opportunity={opportunity} interests={interests} />;
}

function OpportunityCardSkeleton() {
  return (
    <Card aria-busy="true">
      <CardHeader>
        <CardTitle>Open opportunity</CardTitle>
      </CardHeader>
      <CardContent className="grid gap-3">
        <p className="text-muted-foreground text-sm">Loading…</p>
        <div className="bg-muted h-24 animate-pulse rounded-md" aria-hidden />
      </CardContent>
    </Card>
  );
}
