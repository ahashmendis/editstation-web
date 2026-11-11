# Workflows and Lifecycles

Derived from KB §5, §6, §10. Statuses must be Postgres enums, not free-form strings.

## Project workflow (KB §5)

1. Admin creates project, selects brief type.
2. Adds deliverables, footage, instructions, references.
3. Sets proposed compensation and deadline.
4. Invites an editor, or makes the project available only to eligible approved editors.
5. Editor reviews; may ask questions or counteroffer.
6. Complex reference/creative jobs: editor submits an interpretation.
7. Editor confirms brief, deliverables, deadline, agreed compensation.
8. Admin confirms the assignment.
9. Editing begins → submission → admin review against brief and references.
10. Approve, or request revision → completed → payment recorded.

## Brief confirmation (KB §5.1)

Store editor, project, timestamp, confirmed brief version, deadline, deliverables, compensation,
status. A material brief change increments the version and may require re-acknowledgement.

## Status sets as written in the knowledge base

**Project (§10.1):** Draft · Open/Available · Invited · Negotiation · Awaiting editor confirmation ·
Assigned · In progress · Submitted for review · Revision requested · Approved · Completed ·
Cancelled/On hold.

**Assignment (§10.2):** Offered · Counteroffer pending · Accepted · Confirmed by admin · In progress ·
Declined · Withdrawn · Reassigned.

**Revision (§10.3):** Requested · Acknowledged · In progress · Resubmitted · Approved ·
Disputed/scope clarification.

**Submission review outcome (§6.2):** Approved · Revision requested · Rejected/needs discussion ·
Scope change required.

**Payment:** see OPEN_QUESTIONS I. §8.2 and §10.4 list different sets.

## Proposed refinement (pending owner confirmation)

Project and assignment statuses overlap (Invited/Negotiation/Awaiting confirmation). Proposal:
keep negotiation state on the **assignment**, and keep project status coarse
(draft → available → assigned → in_progress → in_review → revision_requested → approved →
completed, plus cancelled/on_hold). Not adopted until the owner agrees; see OPEN_QUESTIONS J.

## Reassignment / cancellation

A reassignment closes the current assignment (`reassigned`/`withdrawn`) and creates a new one;
history is never overwritten. Pay consequences: OPEN_QUESTIONS F.
