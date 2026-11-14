"use client";

import { AreaField, StayForm, TextField } from "@/features/access/components/stay-form";

import {
  addPaymentNoteAction,
  markPaymentPaidAction,
  releasePaymentHoldAction,
  reversePaymentAction,
  setPaymentDueDateAction,
  setPaymentStatusAction,
} from "../admin-actions";
import { HOLD_REASON_HINT, type AdminPaymentAction } from "../constants";

/** Client form wrappers: render-prop children cannot cross the server/client boundary. */

const ADVANCE: Partial<Record<AdminPaymentAction, { status: string; label: string }>> = {
  to_pending_approval: { status: "pending_approval", label: "Send for approval" },
  approve: { status: "approved", label: "Approve payment" },
  to_processing: { status: "processing", label: "Mark transfer in progress" },
};

function AdvanceForm({ paymentId, action }: { paymentId: string; action: AdminPaymentAction }) {
  const advance = ADVANCE[action];
  if (!advance) return null;
  return (
    <StayForm action={setPaymentStatusAction} submitLabel={advance.label}>
      <input type="hidden" name="paymentId" value={paymentId} />
      <input type="hidden" name="status" value={advance.status} />
    </StayForm>
  );
}

function HoldForm({ paymentId }: { paymentId: string }) {
  return (
    <StayForm action={setPaymentStatusAction} submitLabel="Put on hold" variant="outline">
      {(state) => (
        <>
          <input type="hidden" name="paymentId" value={paymentId} />
          <input type="hidden" name="status" value="on_hold" />
          <AreaField
            id="hold-reason"
            name="reason"
            label="Reason for the hold"
            hint={HOLD_REASON_HINT}
            state={state}
            maxLength={500}
            rows={2}
          />
        </>
      )}
    </StayForm>
  );
}

function ReleaseForm({ paymentId }: { paymentId: string }) {
  return (
    <StayForm action={releasePaymentHoldAction} submitLabel="Release hold">
      <input type="hidden" name="paymentId" value={paymentId} />
    </StayForm>
  );
}

function DueDateForm({ paymentId, dueDate }: { paymentId: string; dueDate: string | null }) {
  return (
    <StayForm action={setPaymentDueDateAction} submitLabel="Save due date" variant="outline">
      {(state) => (
        <>
          <input type="hidden" name="paymentId" value={paymentId} />
          <TextField
            id="due-date"
            name="dueDate"
            label="Due date"
            type="date"
            hint="Leave empty to clear it."
            state={state}
            defaultValue={dueDate ?? undefined}
          />
        </>
      )}
    </StayForm>
  );
}

function MarkPaidForm({ paymentId, today }: { paymentId: string; today: string }) {
  return (
    <StayForm
      action={markPaymentPaidAction}
      submitLabel="Mark as paid"
      confirm="A paid payment cannot be edited."
    >
      {(state) => (
        <>
          <input type="hidden" name="paymentId" value={paymentId} />
          <TextField
            id="paid-reference"
            name="reference"
            label="Transaction reference"
            hint="The editor can see this reference."
            state={state}
            maxLength={120}
          />
          <TextField
            id="paid-date"
            name="transferDate"
            label="Transfer date"
            type="date"
            state={state}
            defaultValue={state.values?.transferDate ?? today}
          />
        </>
      )}
    </StayForm>
  );
}

function ReverseForm({ paymentId }: { paymentId: string }) {
  return (
    <StayForm
      action={reversePaymentAction}
      submitLabel="Reverse payment"
      variant="destructive"
      confirm="A paid payment cannot be edited; this adds a correction."
    >
      {(state) => (
        <>
          <input type="hidden" name="paymentId" value={paymentId} />
          <AreaField
            id="reverse-reason"
            name="reason"
            label="Reason for the reversal"
            hint="The editor can see this reason."
            state={state}
            maxLength={500}
            rows={2}
          />
          <label className="flex min-h-11 items-center gap-2 text-sm">
            <input type="checkbox" name="reopen" className="size-4" />
            Re-open the payment for re-approval
          </label>
        </>
      )}
    </StayForm>
  );
}

/** The forms valid for the payment's current status (a hint; the database decides). */
export function PaymentActions({
  paymentId,
  actions,
  dueDate,
  today,
}: {
  paymentId: string;
  actions: AdminPaymentAction[];
  dueDate: string | null;
  today: string;
}) {
  return (
    <div className="grid gap-6">
      {actions.map((action) => {
        switch (action) {
          case "to_pending_approval":
          case "approve":
          case "to_processing":
            return <AdvanceForm key={action} paymentId={paymentId} action={action} />;
          case "mark_paid":
            return <MarkPaidForm key={action} paymentId={paymentId} today={today} />;
          case "hold":
            return <HoldForm key={action} paymentId={paymentId} />;
          case "release":
            return <ReleaseForm key={action} paymentId={paymentId} />;
          case "set_due_date":
            return <DueDateForm key={action} paymentId={paymentId} dueDate={dueDate} />;
          case "reverse":
            return <ReverseForm key={action} paymentId={paymentId} />;
        }
      })}
    </div>
  );
}

export function PaymentNoteForm({ paymentId }: { paymentId: string }) {
  return (
    <StayForm action={addPaymentNoteAction} submitLabel="Add note" resetOnSuccess>
      {(state) => (
        <>
          <input type="hidden" name="paymentId" value={paymentId} />
          <AreaField
            id="payment-note"
            name="note"
            label="Internal note"
            hint="Only admins can see notes."
            state={state}
            maxLength={4000}
          />
        </>
      )}
    </StayForm>
  );
}
