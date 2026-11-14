"use client";

import {
  AreaField,
  SelectField,
  StayForm,
  TextField,
} from "@/features/access/components/stay-form";

import {
  classifyRevisionAction,
  completeProjectAction,
  reviewSubmissionAction,
} from "../admin-actions";
import { REVISION_TYPE_LABEL, REVISION_TYPES } from "../constants";
import { acknowledgeRevisionAction, submitWorkAction } from "../editor-actions";

/** Client form wrappers: render-prop children cannot cross the server/client boundary. */

export function SubmitWorkForm({
  projectId,
  assignmentId,
}: {
  projectId: string;
  assignmentId: string;
}) {
  return (
    <StayForm action={submitWorkAction} submitLabel="Submit work" resetOnSuccess>
      {(state) => (
        <>
          <input type="hidden" name="projectId" value={projectId} />
          <input type="hidden" name="assignmentId" value={assignmentId} />
          <TextField
            id="submit-link"
            name="link"
            label="Link to the work"
            hint="A share link (https://) to the preview or final files. Never upload media here."
            type="url"
            inputMode="url"
            maxLength={2048}
            state={state}
          />
          <AreaField
            id="submit-notes"
            name="notes"
            label="Notes (optional)"
            hint="What changed, anything the studio should check."
            maxLength={4000}
            state={state}
          />
          <AreaField
            id="submit-export"
            name="exportDetails"
            label="Export details (optional)"
            hint="Resolution, codec, frame rate, aspect ratio."
            rows={2}
            maxLength={2000}
            state={state}
          />
        </>
      )}
    </StayForm>
  );
}

export function AcknowledgeRevisionForm({
  projectId,
  revisionId,
  start,
}: {
  projectId: string;
  revisionId: string;
  start: boolean;
}) {
  return (
    <StayForm
      action={acknowledgeRevisionAction}
      submitLabel={start ? "Mark in progress" : "Acknowledge"}
      variant={start ? "outline" : "default"}
    >
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="revisionId" value={revisionId} />
      <input type="hidden" name="start" value={start ? "yes" : "no"} />
    </StayForm>
  );
}

function TypeOptions({ allowEmpty }: { allowEmpty: boolean }) {
  return (
    <>
      {allowEmpty ? <option value="">Not a change request (approve)</option> : null}
      {REVISION_TYPES.map((t) => (
        <option key={t} value={t}>
          {REVISION_TYPE_LABEL[t]}
        </option>
      ))}
    </>
  );
}

export function ReviewSubmissionForm({
  projectId,
  submissionId,
}: {
  projectId: string;
  submissionId: string;
}) {
  return (
    <StayForm action={reviewSubmissionAction} submitLabel="Save review">
      {(state) => (
        <>
          <input type="hidden" name="projectId" value={projectId} />
          <input type="hidden" name="submissionId" value={submissionId} />
          <SelectField
            id={`review-outcome-${submissionId}`}
            name="outcome"
            label="Outcome"
            defaultValue="revision_requested"
            state={state}
          >
            <option value="approved">Approve</option>
            <option value="revision_requested">Revision requested</option>
            <option value="rejected_needs_discussion">Rejected / needs discussion</option>
            <option value="scope_change_required">Scope change required</option>
          </SelectField>
          <AreaField
            id={`review-feedback-${submissionId}`}
            name="feedback"
            label="Feedback for the editor"
            hint="Required unless you approve. The editor sees this."
            maxLength={4000}
            state={state}
          />
          <SelectField
            id={`review-type-${submissionId}`}
            name="revisionType"
            label="Classify the change"
            hint="Only client revisions use the included rounds. Scope change required is always a scope change."
            defaultValue=""
            state={state}
          >
            <TypeOptions allowEmpty />
          </SelectField>
          <AreaField
            id={`review-reason-${submissionId}`}
            name="reason"
            label="Reason for this classification"
            hint="Required for any change request. The editor sees this."
            maxLength={4000}
            state={state}
          />
        </>
      )}
    </StayForm>
  );
}

export function ApproveSubmissionForm({
  projectId,
  submissionId,
}: {
  projectId: string;
  submissionId: string;
}) {
  return (
    <StayForm
      action={reviewSubmissionAction}
      submitLabel="Approve this version"
      variant="outline"
      confirm="Approve this version? The project moves to approved and the editor's pay is sent for approval."
    >
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="submissionId" value={submissionId} />
      <input type="hidden" name="outcome" value="approved" />
    </StayForm>
  );
}

export function ClassifyRevisionForm({
  projectId,
  revisionId,
  current,
}: {
  projectId: string;
  revisionId: string;
  current: string;
}) {
  return (
    <StayForm action={classifyRevisionAction} submitLabel="Save classification" variant="outline">
      {(state) => (
        <>
          <input type="hidden" name="projectId" value={projectId} />
          <input type="hidden" name="revisionId" value={revisionId} />
          <SelectField
            id={`classify-type-${revisionId}`}
            name="revisionType"
            label="Classification"
            defaultValue={current}
            state={state}
          >
            <TypeOptions allowEmpty={false} />
          </SelectField>
          <AreaField
            id={`classify-reason-${revisionId}`}
            name="reason"
            label="Reason"
            hint="The editor sees this."
            maxLength={4000}
            state={state}
          />
        </>
      )}
    </StayForm>
  );
}

export function CompleteProjectForm({ projectId }: { projectId: string }) {
  return (
    <StayForm
      action={completeProjectAction}
      submitLabel="Mark project completed"
      confirm="Mark this project completed?"
    >
      <input type="hidden" name="projectId" value={projectId} />
    </StayForm>
  );
}
