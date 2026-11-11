import type { Metadata } from "next";

import { AuthShell } from "@/components/auth-shell";
import { PRIVACY_NOTICE_VERSION } from "@/features/applications/constants";

export const metadata: Metadata = { title: "Privacy notice · EDITSTATION" };

// Placeholder. The privacy notice must be prepared with qualified local counsel
// (KB §12.3, OPEN_QUESTIONS P). Do not write legal terms here.
export default function PrivacyPage() {
  return (
    <AuthShell title="Privacy notice" description={`Version: ${PRIVACY_NOTICE_VERSION}`}>
      <p className="text-sm">
        The EDITSTATION privacy notice is being finalised and will be published here before public
        launch. Every application records which version was accepted.
      </p>
    </AuthShell>
  );
}
