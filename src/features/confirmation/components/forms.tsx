"use client";

import { AreaField, StayForm } from "@/features/access/components/stay-form";

import { reviewInterpretationAction } from "../admin-actions";
import { submitInterpretationAction } from "../editor-actions";

/** Client form wrappers: render-prop children cannot cross the server/client boundary. */

export function InterpretationForm({
  projectId,
  assignmentId,
  briefVersion,
  willReproduce,
  willAdapt,
  questions,
}: {
  projectId: string;
  assignmentId: string;
  briefVersion: number;
  willReproduce?: string;
  willAdapt?: string;
  questions?: string;
}) {
  return (
    <StayForm action={submitInterpretationAction} submitLabel="Send interpretation">
      {(state) => (
        <>
          <input type="hidden" name="projectId" value={projectId} />
          <input type="hidden" name="assignmentId" value={assignmentId} />
          <input type="hidden" name="briefVersion" value={briefVersion} />
          <AreaField
            id="interp-reproduce"
            name="willReproduce"
            label="What you will reproduce"
            hint="The parts of the references you will follow closely."
            state={state}
            maxLength={4000}
            defaultValue={willReproduce}
          />
          <AreaField
            id="interp-adapt"
            name="willAdapt"
            label="What you will adapt"
            hint="What you will change to fit this brief."
            state={state}
            maxLength={4000}
            defaultValue={willAdapt}
          />
          <AreaField
            id="interp-questions"
            name="questions"
            label="Questions or limitations (optional)"
            state={state}
            maxLength={4000}
            defaultValue={questions}
          />
        </>
      )}
    </StayForm>
  );
}

export function RequestChangesForm({
  projectId,
  interpretationId,
}: {
  projectId: string;
  interpretationId: string;
}) {
  return (
    <StayForm action={reviewInterpretationAction} submitLabel="Request changes" variant="outline">
      {(formState) => (
        <>
          <input type="hidden" name="projectId" value={projectId} />
          <input type="hidden" name="interpretationId" value={interpretationId} />
          <input type="hidden" name="decision" value="request_changes" />
          <AreaField
            id={`feedback-${interpretationId}`}
            name="feedback"
            label="What should change?"
            state={formState}
            maxLength={4000}
          />
        </>
      )}
    </StayForm>
  );
}
