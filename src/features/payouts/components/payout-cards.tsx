import type { ReactNode } from "react";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { formatDateTime } from "@/features/applications/components/status-badge";

import {
  VERIFY_METHOD_LABEL,
  verificationLabel,
  type AdminPayout,
  type EditorPayout,
} from "../schemas";

import {
  AttestPayoutForm,
  EditorPayoutForm,
  RevealPayoutForm,
  VerifyPayoutForm,
} from "./payout-forms";

function Fact({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="grid gap-0.5">
      <dt className="text-muted-foreground text-xs">{label}</dt>
      <dd className="break-words">{children}</dd>
    </div>
  );
}

function SavedDetails({ p }: { p: EditorPayout }) {
  return (
    <dl className="grid gap-3 text-sm sm:grid-cols-2">
      <Fact label="Status">
        <strong>{verificationLabel(p)}</strong>
      </Fact>
      <Fact label="Account holder">{p.account_holder}</Fact>
      <Fact label="Bank">{p.bank}</Fact>
      <Fact label="Branch">{p.branch}</Fact>
      <Fact label="Account number">{p.account_number_masked}</Fact>
      {p.last_changed_at ? (
        <Fact label="Last changed">{formatDateTime(p.last_changed_at)}</Fact>
      ) : null}
    </dl>
  );
}

/** Editor earnings: payout details card. Shows a "not available yet" state while locked. */
export function EditorPayoutCard({ payout }: { payout: EditorPayout }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>
          <h2>Payout details</h2>
        </CardTitle>
        <CardDescription>
          The bank account Lenscape transfers your pay to. Only you and Lenscape admins can see it;
          the account number is shown masked.
        </CardDescription>
      </CardHeader>
      <CardContent className="grid gap-4">
        {!payout.enabled ? (
          <div role="status" className="grid gap-1 text-sm">
            <p className="font-medium">Not available yet</p>
            <p className="text-muted-foreground">
              You can&apos;t add bank details in EDITSTATION yet. Lenscape is confirming how they
              will be protected first. Until then, Lenscape confirms your payout account with you
              directly before paying.
            </p>
          </div>
        ) : null}
        {payout.saved ? <SavedDetails p={payout} /> : null}
        {payout.enabled ? (
          <>
            {!payout.saved ? (
              <p className="text-muted-foreground text-sm">
                No payout details yet. Add them so Lenscape can pay you. Lenscape confirms them with
                you by phone before the first transfer.
              </p>
            ) : null}
            <EditorPayoutForm
              saved={payout.saved}
              accountHolder={payout.account_holder}
              bank={payout.bank}
              branch={payout.branch}
            />
          </>
        ) : null}
      </CardContent>
    </Card>
  );
}

/** Admin: one editor's payout card (masked view, verify, attest while locked, reveal). */
export function AdminPayoutCard({
  editorId,
  editorName,
  payout,
}: {
  editorId: string;
  editorName: string;
  payout: AdminPayout;
}) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>
          <h2>Payout account · {editorName}</h2>
        </CardTitle>
        <CardDescription>
          {payout.enabled
            ? "Payout details are live. A payment can be marked paid only when the editor's details are verified."
            : "Payout details are locked (no bank data is stored). Until they are live, record that the payout account was verified outside the app."}
        </CardDescription>
      </CardHeader>
      <CardContent className="grid gap-5">
        <p className="text-sm" role="status">
          <strong>Marking paid: </strong>
          {payout.mark_paid_block ?? "allowed for this editor."}
        </p>

        {!payout.enabled ? (
          <div className="grid gap-3">
            {payout.attestation ? (
              <p className="text-sm">
                Verified outside the app by {payout.attestation.attested_by ?? "a former admin"} on{" "}
                {formatDateTime(payout.attestation.attested_at)}.
                <span className="text-muted-foreground block">{payout.attestation.note}</span>
              </p>
            ) : (
              <p className="text-muted-foreground text-sm">No attestation recorded yet.</p>
            )}
            <AttestPayoutForm editorId={editorId} />
          </div>
        ) : payout.attestation ? (
          <p className="text-muted-foreground text-sm">
            An earlier &quot;verified outside the app&quot; attestation (
            {formatDateTime(payout.attestation.attested_at)}) no longer counts now that payout
            details are live.
          </p>
        ) : null}

        {payout.saved ? (
          <div className="grid gap-4">
            <SavedDetails p={payout} />
            {payout.verification_status === "verified" ? (
              <p className="text-sm">
                Verified
                {payout.verified_method ? ` (${VERIFY_METHOD_LABEL[payout.verified_method]})` : ""}
                {payout.verified_by ? ` by ${payout.verified_by}` : ""}
                {payout.verified_at ? ` on ${formatDateTime(payout.verified_at)}` : ""}.
                {payout.verification_note ? (
                  <span className="text-muted-foreground block">{payout.verification_note}</span>
                ) : null}
              </p>
            ) : payout.enabled && payout.version ? (
              <div className="grid gap-2">
                <p className="text-sm font-medium">Verify by phone</p>
                <p className="text-muted-foreground text-sm">
                  Call the editor on a number you already hold and confirm the details above.
                </p>
                <VerifyPayoutForm editorId={editorId} version={payout.version} />
              </div>
            ) : null}
            <div className="grid gap-2">
              <p className="text-sm font-medium">Reveal the full account number</p>
              <p className="text-muted-foreground text-sm">
                Every reveal is recorded with your name and reason.
              </p>
              <RevealPayoutForm editorId={editorId} />
            </div>
          </div>
        ) : payout.enabled ? (
          <p className="text-muted-foreground text-sm">
            The editor has not added payout details yet.
          </p>
        ) : null}
      </CardContent>
    </Card>
  );
}
