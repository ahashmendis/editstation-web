import { EmptyState } from "@/components/empty-state";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { AdminActionForm } from "@/features/applications/components/admin-action-form";
import { formatDateTime } from "@/features/applications/components/status-badge";

import { agreeTermsAction } from "../admin-actions";
import { TERMS_STAGE_LABEL } from "../constants";
import type { ProjectTermsRow } from "../queries";
import { TERMS_STAGES, type TermsStage } from "../schemas";
import { TermsDraftForm, type TermsDefaults } from "./terms-forms";

const STATUS_LABEL = { draft: "Draft", agreed: "Agreed (in force)", superseded: "Superseded" };

const str = (value: string | number | null | undefined) =>
  value === null || value === undefined ? "" : String(value);

function stageOf(t: ProjectTermsRow, s: TermsStage) {
  return t.project_terms_stages.find((row) => row.stage === s);
}

function TermsSummary({ t }: { t: ProjectTermsRow }) {
  const stages = TERMS_STAGES.flatMap((s) => {
    const row = stageOf(t, s);
    return row ? [{ s, row }] : [];
  });
  return (
    <dl className="grid gap-x-4 gap-y-1 text-sm sm:grid-cols-[auto_1fr]">
      <dt className="text-muted-foreground">Included revision rounds</dt>
      <dd>{t.included_rounds === 0 ? "None (chargeable from round 1)" : t.included_rounds}</dd>
      <dt className="text-muted-foreground">Client charge per extra round</dt>
      <dd>
        {t.extra_round_charge === null
          ? "Not set"
          : `${t.extra_round_charge} ${t.charge_currency ?? ""}`}
      </dd>
      <dt className="text-muted-foreground">Payment days</dt>
      <dd>
        Deposit {t.deposit_days} · balance {t.balance_days} · editor pay {t.editor_pay_days} ·
        late-balance protection {t.late_balance_days}
      </dd>
      <dt className="text-muted-foreground">Editor pay milestones</dt>
      <dd>{t.editor_milestone_shares.map((n) => `${n}%`).join(" / ")}</dd>
      <dt className="text-muted-foreground">Cancellation schedule</dt>
      <dd>
        {stages.length === 0 ? (
          "Not entered (a cancellation cannot be settled without it)"
        ) : (
          <ul className="grid gap-0.5">
            {stages.map(({ s, row }) => (
              <li key={s}>
                {TERMS_STAGE_LABEL[s]}: editor earns {row.editor_earned_percent}%, client charged{" "}
                {row.client_charge_percent}%
              </li>
            ))}
          </ul>
        )}
      </dd>
      {t.change_reason ? (
        <>
          <dt className="text-muted-foreground">Reason for change</dt>
          <dd className="break-words">{t.change_reason}</dd>
        </>
      ) : null}
    </dl>
  );
}

function defaultsFrom(t: ProjectTermsRow | undefined, isDraft: boolean): TermsDefaults {
  return {
    includedRounds: str(t?.included_rounds ?? 3),
    extraRoundCharge: str(t?.extra_round_charge),
    chargeCurrency: t?.charge_currency ?? "LKR",
    depositDays: str(t?.deposit_days ?? 14),
    balanceDays: str(t?.balance_days ?? 7),
    editorPayDays: str(t?.editor_pay_days ?? 7),
    lateBalanceDays: str(t?.late_balance_days ?? 14),
    editorShares: (t?.editor_milestone_shares ?? [50, 50]).join(", "),
    // A reason belongs to one change: never carried into a new version.
    changeReason: isDraft ? str(t?.change_reason) : "",
    stages: Object.fromEntries(
      TERMS_STAGES.map((s) => {
        const row = t ? stageOf(t, s) : undefined;
        return [
          s,
          { editor: str(row?.editor_earned_percent), client: str(row?.client_charge_percent) },
        ];
      }),
    ) as TermsDefaults["stages"],
  };
}

/** Admin-only project terms: versions, the draft editor and agreement. */
export function TermsCard({
  projectId,
  terms,
  locked,
}: {
  projectId: string;
  terms: ProjectTermsRow[];
  locked: boolean;
}) {
  const agreed = terms.find((t) => t.status === "agreed");
  const draft = terms.find((t) => t.status === "draft");
  const latest = terms[0];
  const nextVersion = draft?.version ?? (latest?.version ?? 0) + 1;
  return (
    <Card>
      <CardHeader>
        <CardTitle>Terms</CardTitle>
        <CardDescription>
          The agreed commercial terms. Agreed versions are never edited: a change is a new version.
          An editor can be confirmed only once terms are agreed. Editors see only the included
          rounds and their own pay shares.
        </CardDescription>
      </CardHeader>
      <CardContent className="grid gap-6">
        <section className="grid gap-2" aria-labelledby="terms-agreed">
          <h3 id="terms-agreed" className="font-medium">
            {agreed ? `In force: version ${agreed.version}` : "No terms agreed yet"}
          </h3>
          {agreed ? (
            <>
              <p className="text-muted-foreground text-sm">
                Agreed {agreed.agreed_at ? formatDateTime(agreed.agreed_at) : ""}
              </p>
              <TermsSummary t={agreed} />
            </>
          ) : (
            <p className="text-muted-foreground text-sm">
              Review the draft below and agree it before confirming an editor.
            </p>
          )}
        </section>

        {draft ? (
          <section className="grid gap-3 rounded-lg border p-3" aria-labelledby="terms-draft">
            <h3 id="terms-draft" className="font-medium">
              Draft: version {draft.version}
            </h3>
            <TermsSummary t={draft} />
            {locked ? null : (
              <AdminActionForm
                action={agreeTermsAction}
                submitLabel={`Agree version ${draft.version}`}
                confirm={
                  agreed
                    ? `Replace version ${agreed.version} with version ${draft.version}?`
                    : `Agree version ${draft.version}?`
                }
              >
                <input type="hidden" name="projectId" value={projectId} />
                <input type="hidden" name="version" value={draft.version} />
                {draft.version > 1 ? (
                  <div className="grid gap-2">
                    <Label htmlFor="agree-change-reason">Reason for the change</Label>
                    <Textarea
                      id="agree-change-reason"
                      name="changeReason"
                      rows={2}
                      maxLength={2000}
                      aria-describedby="agree-change-reason-hint"
                    />
                    <p id="agree-change-reason-hint" className="text-muted-foreground text-sm">
                      Required after work has begun, unless the draft already has one. Editor pay
                      shares cannot change once an editor has accepted.
                    </p>
                  </div>
                ) : null}
              </AdminActionForm>
            )}
          </section>
        ) : null}

        {locked ? (
          <p className="text-muted-foreground text-sm">This project can no longer be edited.</p>
        ) : (
          <section className="grid gap-3" aria-labelledby="terms-edit">
            <h3 id="terms-edit" className="font-medium">
              {draft ? "Edit the draft" : "Change the terms"}
            </h3>
            <TermsDraftForm
              key={`${draft?.id ?? "new"}:${latest?.id ?? ""}`}
              projectId={projectId}
              defaults={defaultsFrom(draft ?? latest, Boolean(draft))}
              hasDraft={Boolean(draft)}
              nextVersion={nextVersion}
            />
          </section>
        )}

        <section className="grid gap-2" aria-labelledby="terms-history">
          <h3 id="terms-history" className="font-medium">
            Versions
          </h3>
          {terms.length === 0 ? (
            <EmptyState title="No terms recorded" />
          ) : (
            <ol className="grid gap-2 text-sm">
              {terms.map((t) => (
                <li key={t.id} className="border-t pt-2 first:border-t-0 first:pt-0">
                  <details>
                    <summary className="flex cursor-pointer flex-wrap justify-between gap-2">
                      <span>
                        Version {t.version}: {STATUS_LABEL[t.status]}
                      </span>
                      <span className="text-muted-foreground tabular-nums">
                        {formatDateTime(t.agreed_at ?? t.created_at)}
                      </span>
                    </summary>
                    <div className="pt-2">
                      <TermsSummary t={t} />
                    </div>
                  </details>
                </li>
              ))}
            </ol>
          )}
        </section>
      </CardContent>
    </Card>
  );
}
