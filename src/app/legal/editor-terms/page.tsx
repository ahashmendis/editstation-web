import type { Metadata } from "next";

import { AuthShell } from "@/components/auth-shell";
import { EDITOR_TERMS_VERSION } from "@/features/applications/constants";

export const metadata: Metadata = { title: "Editor terms · EDITSTATION" };

// Placeholder. The editor agreement must be drafted and reviewed by a Sri Lankan lawyer
// (KB §12.2, OPEN_QUESTIONS KB8). Do not write legal terms here.
export default function EditorTermsPage() {
  return (
    <AuthShell title="Editor terms" description={`Version: ${EDITOR_TERMS_VERSION}`}>
      <p className="text-sm">
        The EDITSTATION editor terms are being finalised and will be published here before the
        editor network opens to the public. Every application records which version was accepted.
      </p>
    </AuthShell>
  );
}
