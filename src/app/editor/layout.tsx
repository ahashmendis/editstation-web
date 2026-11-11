import { Suspense, type ReactNode } from "react";

import { Loading } from "@/components/auth-shell";
import { requireActiveEditor } from "@/lib/auth/access";

// Editor area: only accounts with access_status = 'active' (decision L).
// UI gate only; RLS (private.is_active_editor) is the real boundary.
export default function EditorLayout({ children }: { children: ReactNode }) {
  return (
    <Suspense fallback={<Loading />}>
      <EditorGate>{children}</EditorGate>
    </Suspense>
  );
}

async function EditorGate({ children }: { children: ReactNode }) {
  await requireActiveEditor();
  return children;
}
