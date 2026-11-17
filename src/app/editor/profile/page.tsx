import type { Metadata } from "next";
import { Suspense } from "react";

import { AreaShell, Loading } from "@/components/auth-shell";
import { SignOutButton } from "@/components/sign-out-button";
import { ProfilePictureCard } from "@/features/profile/components/profile-picture-card";
import { requireActiveEditor } from "@/lib/auth/access";

export const metadata: Metadata = { title: "Profile · EDITSTATION" };

export default function EditorProfilePage() {
  return (
    <Suspense fallback={<Loading />}>
      <ProfileContent />
    </Suspense>
  );
}

async function ProfileContent() {
  const access = await requireActiveEditor();
  return (
    <AreaShell title="Profile" subtitle={access.email ?? undefined} actions={<SignOutButton />}>
      <ProfilePictureCard />
    </AreaShell>
  );
}
