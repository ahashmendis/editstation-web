import { Suspense } from "react";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

import { getMyProfileSummary } from "../queries";
import { AvatarForm } from "./avatar-form";

/** The signed-in user's own picture card (any account type). Per-request read in Suspense. */
export function ProfilePictureCard() {
  return (
    <Card id="profile-picture">
      <CardHeader>
        <CardTitle>Profile picture</CardTitle>
        <CardDescription>Optional. You can replace or remove it at any time.</CardDescription>
      </CardHeader>
      <CardContent>
        <Suspense fallback={<p className="text-muted-foreground text-sm">Loading your picture…</p>}>
          <ProfilePictureForm />
        </Suspense>
      </CardContent>
    </Card>
  );
}

async function ProfilePictureForm() {
  const me = await getMyProfileSummary();
  return (
    <AvatarForm
      url={me.avatarUrl}
      name={me.name}
      email={me.email}
      hasPicture={me.avatarPath !== null}
    />
  );
}
