import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

import { TERMS_STAGE_LABEL } from "../constants";
import type { EditorTerms } from "../queries";

/** Editor-safe summary of the agreed project terms. Never client prices or charges. */
export function EditorTermsSummary({ terms }: { terms: EditorTerms | null }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Terms</CardTitle>
        <CardDescription>
          {terms
            ? `Agreed terms, version ${terms.version}. A change is always a new, recorded version.`
            : "The studio has not agreed the terms for this project yet."}
        </CardDescription>
      </CardHeader>
      {terms ? (
        <CardContent>
          <dl className="grid gap-x-4 gap-y-1 text-sm sm:grid-cols-[auto_1fr]">
            <dt className="text-muted-foreground">Included client revision rounds</dt>
            <dd>{terms.includedRounds}</dd>
            <dt className="text-muted-foreground">Your pay milestones</dt>
            <dd>{terms.editorShares.map((n) => `${n}%`).join(" / ")} of your agreed pay</dd>
            <dt className="text-muted-foreground">If the project is cancelled</dt>
            <dd>
              {terms.killFee.length === 0 ? (
                "Not set yet"
              ) : (
                <ul className="grid gap-0.5">
                  {terms.killFee.map((k) => (
                    <li key={k.stage}>
                      {TERMS_STAGE_LABEL[k.stage as keyof typeof TERMS_STAGE_LABEL] ?? k.stage}: you
                      earn {k.editor_earned_percent}% of your agreed pay
                    </li>
                  ))}
                </ul>
              )}
            </dd>
          </dl>
        </CardContent>
      ) : null}
    </Card>
  );
}
