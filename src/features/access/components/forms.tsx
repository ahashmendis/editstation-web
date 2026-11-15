"use client";

import { useRef, useState } from "react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { selectClassName } from "@/features/projects/components/select-class";

import {
  addNoteAction,
  confirmAssignmentAction,
  confirmRemovalAction,
  grantAccessAction,
  makeOfferAction,
  reassignAction,
  recordGrantAction,
  requestRemovalAction,
  resolveReportAction,
  revokeAccessAction,
  saveAssetsAction,
  setEarlyAccessAction,
  respondCounterAction,
  verifyAssetAction,
  withdrawOfferAction,
} from "../admin-actions";
import {
  confirmAssetAccessAction,
  editorRespondAction,
  reportAssetAction,
} from "../editor-actions";
import {
  ACCESS_REASONS,
  ACCESS_REASON_LABEL,
  ASSET_ACCESS_TYPES,
  ASSET_ACCESS_TYPE_LABEL,
  ASSET_KIND_SUGGESTIONS,
  ASSET_PROVIDERS,
  ASSET_PROVIDER_LABEL,
  EARLY_ACCESS_HINT,
  MAX_ASSETS,
} from "../constants";
import { AreaField, SelectField, StayForm, TextField } from "./stay-form";

const hiddenIds = (ids: Record<string, string>) =>
  Object.entries(ids).map(([name, value]) => (
    <input key={name} type="hidden" name={name} value={value} />
  ));

// --- Assets ------------------------------------------------------------------------------------

export type AssetRow = {
  id: string;
  label: string;
  url: string;
  provider: string;
  kind: string;
  notes: string;
  description: string;
  accessInstructions: string;
};

const blankAsset: AssetRow = {
  id: "",
  label: "",
  url: "",
  provider: "other",
  kind: "",
  notes: "",
  description: "",
  accessInstructions: "",
};

/** Rows live in state (not the DOM) so a failed save keeps everything the admin typed. */
export function AssetsForm({
  projectId,
  initial,
  locked,
}: {
  projectId: string;
  initial: AssetRow[];
  locked: boolean;
}) {
  const counter = useRef(initial.length);
  const [rows, setRows] = useState(() => initial.map((row, i) => ({ key: i, row })));
  const set = (key: number, field: keyof AssetRow, value: string) =>
    setRows((r) => r.map((x) => (x.key === key ? { ...x, row: { ...x.row, [field]: value } } : x)));

  return (
    <StayForm action={saveAssetsAction} submitLabel="Save assets">
      {(state) => (
        <fieldset disabled={locked} className="m-0 grid min-w-0 gap-3 border-0 p-0">
          <input type="hidden" name="projectId" value={projectId} />
          {state.fieldErrors
            ? Object.values(state.fieldErrors)
                .flat()
                .slice(0, 1)
                .map((m) => (
                  <p key={m} className="text-destructive text-sm">
                    {m}
                  </p>
                ))
            : null}
          <datalist id="asset-kinds">
            {ASSET_KIND_SUGGESTIONS.map((k) => (
              <option key={k} value={k} />
            ))}
          </datalist>
          {rows.length === 0 ? (
            <p className="text-muted-foreground text-sm">
              No assets yet. Add links to footage, music, graphics or brand files.
            </p>
          ) : null}
          {rows.map(({ key, row }, i) => {
            const id = (f: string) => `asset-${key}-${f}`;
            const bind = (f: keyof AssetRow) => ({
              id: id(f),
              name: `asset.${f}`,
              value: row[f],
              onChange: (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
                set(key, f, e.target.value),
            });
            return (
              <div key={key} className="grid gap-3 rounded-lg border p-3">
                <input type="hidden" name="asset.id" value={row.id} />
                <p className="text-muted-foreground text-xs font-medium">Asset {i + 1}</p>
                <div className="grid gap-3 sm:grid-cols-2">
                  <div className="grid gap-1">
                    <Label htmlFor={id("label")}>Label</Label>
                    <Input {...bind("label")} maxLength={200} />
                  </div>
                  <div className="grid gap-1">
                    <Label htmlFor={id("url")}>Link (https only)</Label>
                    <Input {...bind("url")} type="url" inputMode="url" maxLength={2048} />
                  </div>
                  <div className="grid gap-1">
                    <Label htmlFor={id("provider")}>Provider</Label>
                    <select
                      id={id("provider")}
                      name="asset.provider"
                      className={selectClassName}
                      value={row.provider}
                      onChange={(e) => set(key, "provider", e.target.value)}
                    >
                      {ASSET_PROVIDERS.map((p) => (
                        <option key={p} value={p}>
                          {ASSET_PROVIDER_LABEL[p]}
                        </option>
                      ))}
                    </select>
                  </div>
                  <div className="grid gap-1">
                    <Label htmlFor={id("kind")}>Kind</Label>
                    <Input
                      {...bind("kind")}
                      list="asset-kinds"
                      maxLength={40}
                      placeholder="footage"
                    />
                  </div>
                  <div className="grid gap-1 sm:col-span-2">
                    <Label htmlFor={id("description")}>Description</Label>
                    <Textarea
                      {...bind("description")}
                      rows={2}
                      maxLength={2000}
                      placeholder="What is in this folder or file"
                    />
                  </div>
                  <div className="grid gap-1 sm:col-span-2">
                    <Label htmlFor={id("accessInstructions")}>Access instructions</Label>
                    <Textarea
                      {...bind("accessInstructions")}
                      rows={2}
                      maxLength={2000}
                      aria-describedby={id("access-hint")}
                      placeholder="e.g. Shared with your Google account; request access if it does not open"
                    />
                    <p id={id("access-hint")} className="text-muted-foreground text-xs">
                      Editors see these. Never put passwords here. Changing the link or provider
                      resets the access check.
                    </p>
                  </div>
                  <div className="grid gap-1 sm:col-span-2">
                    <Label htmlFor={id("notes")}>Notes</Label>
                    <Textarea
                      {...bind("notes")}
                      rows={2}
                      maxLength={2000}
                      aria-describedby={id("notes-hint")}
                    />
                    <p id={id("notes-hint")} className="text-muted-foreground text-xs">
                      {EARLY_ACCESS_HINT}
                    </p>
                  </div>
                </div>
                <Button
                  type="button"
                  variant="outline"
                  className="justify-self-start"
                  onClick={() => setRows((r) => r.filter((x) => x.key !== key))}
                >
                  Remove asset {i + 1}
                </Button>
              </div>
            );
          })}
          <Button
            type="button"
            variant="outline"
            className="justify-self-start"
            disabled={rows.length >= MAX_ASSETS}
            onClick={() =>
              setRows((r) => [...r, { key: counter.current++, row: { ...blankAsset } }])
            }
          >
            Add asset
          </Button>
        </fieldset>
      )}
    </StayForm>
  );
}

export function EarlyAccessToggle({
  projectId,
  target,
  targetId,
  value,
  name,
}: {
  projectId: string;
  target: "reference" | "asset";
  targetId: string;
  value: boolean;
  name: string;
}) {
  return (
    <StayForm
      action={setEarlyAccessAction}
      submitLabel={value ? `Hide ${name} from the summary` : `Show ${name} in the summary`}
      variant="outline"
    >
      {hiddenIds({ projectId, target, targetId, value: value ? "false" : "true" })}
    </StayForm>
  );
}

// --- Editors -----------------------------------------------------------------------------------

export type EditorOption = { id: string; name: string; email: string };

export function InviteEditorsForm({
  projectId,
  options,
}: {
  projectId: string;
  options: EditorOption[];
}) {
  if (options.length === 0) {
    return (
      <p className="text-muted-foreground text-sm">
        Every active editor already has access, or there are no active editors yet.
      </p>
    );
  }
  return (
    <StayForm action={grantAccessAction} submitLabel="Invite selected editors" resetOnSuccess>
      {(state) => (
        <>
          <input type="hidden" name="projectId" value={projectId} />
          <fieldset className="grid gap-2">
            <legend className="text-sm font-medium">Active editors</legend>
            {options.map((o) => (
              <label key={o.id} className="flex items-start gap-2 text-sm">
                <Input
                  type="checkbox"
                  name="editorIds"
                  value={o.id}
                  className="mt-0.5 size-4 shrink-0"
                />
                <span>
                  {o.name}
                  {o.name !== o.email ? (
                    <span className="text-muted-foreground"> ({o.email})</span>
                  ) : null}
                </span>
              </label>
            ))}
            {state.fieldErrors?.editorIds?.length ? (
              <p className="text-destructive text-sm">{state.fieldErrors.editorIds[0]}</p>
            ) : null}
          </fieldset>
          <SelectField
            id="invite-reason"
            name="reason"
            label="Why are they being invited?"
            state={state}
            defaultValue="invited"
          >
            {ACCESS_REASONS.map((r) => (
              <option key={r} value={r}>
                {ACCESS_REASON_LABEL[r]}
              </option>
            ))}
          </SelectField>
        </>
      )}
    </StayForm>
  );
}

export function MakeOfferForm({
  projectId,
  editorId,
  defaultCurrency,
  defaultAmount,
  label,
}: {
  projectId: string;
  editorId: string;
  defaultCurrency: string;
  defaultAmount?: string;
  label: string;
}) {
  const p = `offer-${editorId}`;
  return (
    <StayForm action={makeOfferAction} submitLabel={label} resetOnSuccess>
      {(state) => (
        <>
          {hiddenIds({ projectId, editorId })}
          <div className="grid gap-3 sm:grid-cols-2">
            <TextField
              id={`${p}-amount`}
              name="amount"
              label="Pay offered"
              inputMode="decimal"
              defaultValue={defaultAmount}
              hint="The agreed pay must be set before any editing starts."
              state={state}
            />
            <TextField
              id={`${p}-currency`}
              name="currency"
              label="Currency"
              defaultValue={defaultCurrency}
              maxLength={3}
              state={state}
            />
          </div>
          <AreaField
            id={`${p}-message`}
            name="message"
            label="Message (optional)"
            rows={2}
            maxLength={2000}
            state={state}
          />
        </>
      )}
    </StayForm>
  );
}

/**
 * Accept, decline or counter: the same three choices for the admin (answering a counteroffer)
 * and the editor (answering an offer).
 */
export function RespondForms({
  role,
  projectId,
  assignmentId,
  currency,
  acceptLabel,
  acceptAmount,
}: {
  role: "admin" | "editor";
  projectId: string;
  assignmentId: string;
  currency: string;
  acceptLabel: string;
  /** Formatted amount being accepted; adds a confirm step that shows it. */
  acceptAmount?: string;
}) {
  const action = role === "admin" ? respondCounterAction : editorRespondAction;
  const p = `respond-${assignmentId}`;
  return (
    <div className="grid gap-4">
      <StayForm
        action={action}
        submitLabel={acceptLabel}
        confirm={acceptAmount ? `Accept at ${acceptAmount}?` : undefined}
      >
        {hiddenIds({ projectId, assignmentId, action: "accept" })}
      </StayForm>
      <details className="rounded-lg border p-3">
        <summary className="cursor-pointer text-sm font-medium">Propose a different amount</summary>
        <div className="pt-3">
          <StayForm action={action} submitLabel="Send counteroffer" variant="outline">
            {(state) => (
              <>
                {hiddenIds({ projectId, assignmentId, action: "counter", currency })}
                <TextField
                  id={`${p}-counter-amount`}
                  name="amount"
                  label={`New amount (${currency})`}
                  inputMode="decimal"
                  state={state}
                />
                <AreaField
                  id={`${p}-counter-message`}
                  name="message"
                  label="Message (optional)"
                  rows={2}
                  maxLength={2000}
                  state={state}
                />
              </>
            )}
          </StayForm>
        </div>
      </details>
      <details className="rounded-lg border p-3">
        <summary className="cursor-pointer text-sm font-medium">Decline</summary>
        <div className="pt-3">
          <StayForm
            action={action}
            submitLabel="Decline"
            variant="destructive"
            confirm="Decline? This closes the offer."
          >
            {(state) => (
              <>
                {hiddenIds({ projectId, assignmentId, action: "decline" })}
                <AreaField
                  id={`${p}-decline-message`}
                  name="message"
                  label="Reason (optional)"
                  rows={2}
                  maxLength={2000}
                  state={state}
                />
              </>
            )}
          </StayForm>
        </div>
      </details>
    </div>
  );
}

export function WithdrawOfferForm({
  projectId,
  assignmentId,
}: {
  projectId: string;
  assignmentId: string;
}) {
  return (
    <StayForm
      action={withdrawOfferAction}
      submitLabel="Withdraw offer"
      variant="outline"
      confirm="Withdraw this offer?"
    >
      {(state) => (
        <>
          {hiddenIds({ projectId, assignmentId })}
          <AreaField
            id={`withdraw-${assignmentId}`}
            name="message"
            label="Message to the editor (optional)"
            rows={2}
            maxLength={2000}
            state={state}
          />
        </>
      )}
    </StayForm>
  );
}

export function ConfirmAssignmentForm({
  projectId,
  assignmentId,
}: {
  projectId: string;
  assignmentId: string;
}) {
  return (
    <StayForm
      action={confirmAssignmentAction}
      submitLabel="Confirm this editor"
      confirm="Confirm this editor? Everyone else on the project is marked not selected and loses access."
    >
      {hiddenIds({ projectId, assignmentId })}
    </StayForm>
  );
}

export function ReassignForm({
  projectId,
  assignmentId,
}: {
  projectId: string;
  assignmentId: string;
}) {
  return (
    <StayForm
      action={reassignAction}
      submitLabel="Remove this editor and reopen"
      variant="destructive"
      confirm="Remove this editor? The project opens again for new offers."
    >
      {(state) => (
        <>
          {hiddenIds({ projectId, assignmentId })}
          <AreaField
            id={`reassign-${assignmentId}`}
            name="message"
            label="Reason (the editor will see this)"
            rows={2}
            maxLength={2000}
            state={state}
          />
        </>
      )}
    </StayForm>
  );
}

export function RevokeAccessForm({ projectId, editorId }: { projectId: string; editorId: string }) {
  return (
    <StayForm
      action={revokeAccessAction}
      submitLabel="Remove access"
      variant="outline"
      confirm="Remove this editor's access? Any open offer is withdrawn."
    >
      {hiddenIds({ projectId, editorId })}
    </StayForm>
  );
}

// --- Folder shares -----------------------------------------------------------------------------

export function RecordGrantForm({
  projectId,
  options,
  locked,
}: {
  projectId: string;
  options: EditorOption[];
  locked: boolean;
}) {
  if (locked) {
    return (
      <p className="text-muted-foreground text-sm">
        Shares cannot be recorded on a cancelled or archived project.
      </p>
    );
  }
  return (
    <StayForm action={recordGrantAction} submitLabel="Record share" resetOnSuccess>
      {(state) => (
        <>
          {hiddenIds({ projectId })}
          <div className="grid gap-3 sm:grid-cols-2">
            <SelectField
              id="grant-editor"
              name="editorId"
              label="Editor"
              state={state}
              defaultValue=""
            >
              <option value="" disabled>
                Choose…
              </option>
              {options.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.name}
                </option>
              ))}
            </SelectField>
            <SelectField
              id="grant-provider"
              name="provider"
              label="Provider"
              state={state}
              defaultValue="google_drive"
            >
              {ASSET_PROVIDERS.map((p) => (
                <option key={p} value={p}>
                  {ASSET_PROVIDER_LABEL[p]}
                </option>
              ))}
            </SelectField>
            <SelectField
              id="grant-access-type"
              name="accessType"
              label="How the client shared it"
              state={state}
              defaultValue="editor_account"
              hint="The editor's own account is preferred. Anyone-with-the-link shares are accepted but flagged with a security warning."
            >
              {ASSET_ACCESS_TYPES.map((t) => (
                <option key={t} value={t}>
                  {ASSET_ACCESS_TYPE_LABEL[t]}
                </option>
              ))}
            </SelectField>
            <TextField
              id="grant-email"
              name="email"
              label="Shared with (email)"
              type="email"
              inputMode="email"
              hint="The editor account the client shared the folder with (or sent the link to)."
              state={state}
            />
            <TextField
              id="grant-url"
              name="folderUrl"
              label="Folder link (optional)"
              type="url"
              inputMode="url"
              state={state}
            />
          </div>
        </>
      )}
    </StayForm>
  );
}

/** KB7a-2: ask the client to remove the editor's access, then record their confirmation. */
export function RemovalForms({
  grantId,
  projectId,
  requested,
}: {
  grantId: string;
  projectId: string | null;
  requested: boolean;
}) {
  const ids = hiddenIds({ grantId, projectId: projectId ?? "" });
  return requested ? (
    <StayForm
      action={confirmRemovalAction}
      submitLabel="Confirm removal"
      variant="outline"
      confirm="Has the client confirmed the editor's access is removed?"
    >
      {ids}
    </StayForm>
  ) : (
    <StayForm
      action={requestRemovalAction}
      submitLabel="Request removal"
      variant="outline"
      confirm="Have you asked the client to remove this editor's access? This only records it."
    >
      {ids}
    </StayForm>
  );
}

// --- Asset access ------------------------------------------------------------------------------

export function VerifyAssetForm({
  projectId,
  assetId,
  label,
}: {
  projectId: string;
  assetId: string;
  label: string;
}) {
  return (
    <StayForm
      action={verifyAssetAction}
      submitLabel={`Verify access to ${label}`}
      variant="outline"
      confirm="Have you checked the editor is authorised and can open it? A link that opens is not proof."
    >
      {hiddenIds({ projectId, assetId })}
    </StayForm>
  );
}

export function ResolveReportForm({
  projectId,
  reportId,
}: {
  projectId: string;
  reportId: string;
}) {
  return (
    <StayForm
      action={resolveReportAction}
      submitLabel="Mark report resolved"
      variant="outline"
      confirm="Has the client fixed access? You still verify the asset afterwards."
    >
      {hiddenIds({ projectId, reportId })}
    </StayForm>
  );
}

/** Editor: "I cannot open this", with a note for the studio. */
export function ReportAssetForm({
  projectId,
  assetId,
  label,
}: {
  projectId: string;
  assetId: string;
  label: string;
}) {
  return (
    <details className="rounded-lg border p-3">
      <summary className="cursor-pointer text-sm font-medium">Report {label} inaccessible</summary>
      <div className="pt-3">
        <StayForm action={reportAssetAction} submitLabel="Send report" resetOnSuccess>
          {(state) => (
            <>
              {hiddenIds({ projectId, assetId })}
              <AreaField
                id={`report-${assetId}`}
                name="note"
                label="What happens when you open it?"
                hint="For example: access denied, link expired, wrong folder. The studio is notified."
                rows={2}
                maxLength={1000}
                state={state}
              />
            </>
          )}
        </StayForm>
      </div>
    </details>
  );
}

/** Editor: "I can open this". Never verifies the asset; the studio does. */
export function ConfirmAssetAccessForm({
  projectId,
  assetId,
  label,
}: {
  projectId: string;
  assetId: string;
  label: string;
}) {
  return (
    <StayForm
      action={confirmAssetAccessAction}
      submitLabel={`I can open ${label}`}
      variant="outline"
    >
      {hiddenIds({ projectId, assetId })}
    </StayForm>
  );
}

// --- Notes -------------------------------------------------------------------------------------

export function AddNoteForm({ projectId }: { projectId: string }) {
  return (
    <StayForm action={addNoteAction} submitLabel="Add note" resetOnSuccess>
      {(state) => (
        <>
          {hiddenIds({ projectId })}
          <AreaField
            id="project-note"
            name="note"
            label="New note"
            hint="Notes cannot be edited or deleted. Editors never see them."
            rows={3}
            maxLength={4000}
            state={state}
          />
        </>
      )}
    </StayForm>
  );
}
