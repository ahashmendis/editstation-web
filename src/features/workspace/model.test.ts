import { describe, expect, it } from "vitest";

import {
  buildActivity,
  deriveStage,
  drivingAssignments,
  feedbackGroupOf,
  matchesFilter,
  outstandingPayments,
  paginate,
  parseFeedbackParams,
  parseProjectListParams,
  parseTab,
  paymentMilestone,
  pendingAction,
  queryProjectRows,
  shortRef,
  upcomingDeadlines,
  type ProjectListRow,
} from "./model";

const row = (over: Partial<ProjectListRow> = {}): ProjectListRow => ({
  id: "6f3c2d1e-0b4a-4c6d-8e9f-1a2b3c4d5e61",
  title: "Wedding film",
  stage: "in_progress",
  projectStatus: "in_progress",
  deadline: "2026-12-01",
  deadlineConfirmed: true,
  lastActivity: "2026-11-10T10:00:00Z",
  action: null,
  latestSubmission: null,
  revisionCount: 0,
  payment: null,
  ...over,
});

describe("deriveStage", () => {
  it("is awaiting acceptance while the offer is open or waiting for confirmation", () => {
    for (const a of ["offered", "counteroffer_pending", "accepted"] as const) {
      expect(deriveStage("open", a)).toBe("awaiting_acceptance");
    }
  });
  it("follows the project status once the editor is working", () => {
    expect(deriveStage("assigned", "confirmed")).toBe("confirmed");
    expect(deriveStage("in_progress", "in_progress")).toBe("in_progress");
    expect(deriveStage("in_review", "in_progress")).toBe("in_review");
    expect(deriveStage("revision_requested", "in_progress")).toBe("revision_requested");
    expect(deriveStage("approved", "in_progress")).toBe("approved");
    expect(deriveStage("completed", "in_progress")).toBe("completed");
  });
  it("puts cancelled and on hold before the assignment", () => {
    expect(deriveStage("cancelled", "in_progress")).toBe("cancelled");
    expect(deriveStage("cancelled", "offered")).toBe("cancelled");
    expect(deriveStage("on_hold", "confirmed")).toBe("on_hold");
    expect(deriveStage("on_hold", "offered")).toBe("on_hold");
  });
  it("closes the offer when the assignment ended", () => {
    for (const a of ["declined", "withdrawn", "not_selected", "reassigned"] as const) {
      expect(deriveStage("open", a)).toBe("offer_closed");
    }
  });
});

describe("matchesFilter", () => {
  it("all matches everything", () => {
    expect(matchesFilter("offer_closed", "all")).toBe(true);
  });
  it("active is ongoing work only", () => {
    for (const s of ["confirmed", "in_progress", "in_review", "revision_requested"] as const) {
      expect(matchesFilter(s, "active")).toBe(true);
    }
    for (const s of ["awaiting_acceptance", "approved", "completed", "on_hold"] as const) {
      expect(matchesFilter(s, "active")).toBe(false);
    }
  });
  it("completed includes approved work", () => {
    expect(matchesFilter("approved", "completed")).toBe(true);
    expect(matchesFilter("completed", "completed")).toBe(true);
    expect(matchesFilter("in_review", "completed")).toBe(false);
  });
  it("single-stage filters match their own stage", () => {
    expect(matchesFilter("in_review", "in_review")).toBe(true);
    expect(matchesFilter("in_progress", "in_review")).toBe(false);
    expect(matchesFilter("on_hold", "on_hold")).toBe(true);
    expect(matchesFilter("cancelled", "cancelled")).toBe(true);
  });
});

describe("parseProjectListParams", () => {
  it("defaults", () => {
    expect(parseProjectListParams({})).toEqual({ filter: "all", q: "", sort: "activity", page: 1 });
  });
  it("accepts known values and trims the search", () => {
    expect(
      parseProjectListParams({ filter: "on_hold", q: "  promo ", sort: "deadline", page: "3" }),
    ).toEqual({ filter: "on_hold", q: "promo", sort: "deadline", page: 3 });
  });
  it("maps the submitted alias onto in review", () => {
    expect(parseProjectListParams({ filter: "submitted" }).filter).toBe("in_review");
  });
  it("ignores unknown or malformed values", () => {
    expect(
      parseProjectListParams({ filter: "x", sort: "price", page: "-2", q: ["a", "b"] }),
    ).toEqual({ filter: "all", q: "a", sort: "activity", page: 1 });
    expect(parseProjectListParams({ q: "x".repeat(300) }).q).toHaveLength(100);
  });
});

describe("queryProjectRows", () => {
  const rows = [
    row({ id: "a", title: "Bravo", deadline: "2026-12-05", lastActivity: "2026-11-01T00:00:00Z" }),
    row({ id: "b", title: "alpha", deadline: null, lastActivity: "2026-11-12T00:00:00Z" }),
    row({
      id: "c",
      title: "Charlie promo",
      stage: "completed",
      deadline: "2026-11-20",
      lastActivity: "2026-11-05T00:00:00Z",
    }),
  ];
  it("sorts by last activity, newest first", () => {
    expect(
      queryProjectRows(rows, { filter: "all", q: "", sort: "activity" }).map((r) => r.id),
    ).toEqual(["b", "c", "a"]);
  });
  it("sorts by deadline, soonest first, missing last", () => {
    expect(
      queryProjectRows(rows, { filter: "all", q: "", sort: "deadline" }).map((r) => r.id),
    ).toEqual(["c", "a", "b"]);
  });
  it("sorts by title, case-insensitive", () => {
    expect(
      queryProjectRows(rows, { filter: "all", q: "", sort: "title" }).map((r) => r.id),
    ).toEqual(["b", "a", "c"]);
  });
  it("filters by stage and title search (case-insensitive)", () => {
    expect(
      queryProjectRows(rows, { filter: "active", q: "", sort: "title" }).map((r) => r.id),
    ).toEqual(["b", "a"]);
    expect(
      queryProjectRows(rows, { filter: "all", q: "PROMO", sort: "title" }).map((r) => r.id),
    ).toEqual(["c"]);
  });
});

describe("paginate", () => {
  it("clamps the page and reports the count", () => {
    const items = Array.from({ length: 45 }, (_, i) => i);
    expect(paginate(items, 1, 20)).toMatchObject({ page: 1, pageCount: 3, total: 45 });
    expect(paginate(items, 3, 20).items).toEqual([40, 41, 42, 43, 44]);
    expect(paginate(items, 9, 20).page).toBe(3);
    expect(paginate([], 2, 20)).toMatchObject({ items: [], page: 1, pageCount: 1, total: 0 });
  });
});

describe("pendingAction", () => {
  const base = {
    stage: "in_progress" as const,
    assignmentStatus: "in_progress" as const,
    projectStatus: "in_progress" as const,
    openRevisionStatus: null,
  };
  it("asks the editor to reply to an open offer only while the project is open", () => {
    expect(
      pendingAction({
        ...base,
        stage: "awaiting_acceptance",
        assignmentStatus: "offered",
        projectStatus: "open",
      }),
    ).toEqual({ text: "Reply to the offer", by: "you" });
  });
  it("names who acts next", () => {
    expect(
      pendingAction({ ...base, stage: "awaiting_acceptance", assignmentStatus: "accepted" })?.by,
    ).toBe("studio");
    expect(pendingAction({ ...base, stage: "in_review" })?.by).toBe("studio");
    expect(pendingAction(base)).toEqual({ text: "Submit your work", by: "you" });
  });
  it("follows the open change request", () => {
    const r = { ...base, stage: "revision_requested" as const };
    expect(pendingAction({ ...r, openRevisionStatus: "requested" })?.by).toBe("you");
    expect(pendingAction({ ...r, openRevisionStatus: "in_progress" })?.text).toBe(
      "Submit the revised version",
    );
    expect(pendingAction({ ...r, openRevisionStatus: "disputed" })?.by).toBe("studio");
  });
  it("is nothing once the work is closed", () => {
    expect(pendingAction({ ...base, stage: "completed" })).toBeNull();
    expect(pendingAction({ ...base, stage: "cancelled" })).toBeNull();
    expect(pendingAction({ ...base, stage: "offer_closed" })).toBeNull();
  });
});

describe("paymentMilestone", () => {
  const p = (over: object) => ({
    kind: "assignment" as const,
    status: "not_due" as const,
    milestoneSeq: 1 as number | null,
    lineKind: "milestone" as const,
    dueDate: null as string | null,
    createdAt: "2026-11-01T00:00:00Z",
    ...over,
  });
  it("is null without payments", () => {
    expect(paymentMilestone([])).toBeNull();
  });
  it("shows the first outstanding milestone", () => {
    expect(
      paymentMilestone([
        p({ milestoneSeq: 2, status: "not_due" }),
        p({ milestoneSeq: 1, status: "paid" }),
        p({ milestoneSeq: null, lineKind: "extra_round", status: "pending_approval" }),
      ]),
    ).toEqual({ status: "not_due", label: "Milestone 2" });
  });
  it("counts on hold as outstanding and ignores cancelled rows and corrections", () => {
    expect(
      paymentMilestone([
        p({ status: "cancelled" }),
        p({ kind: "reversal", status: "paid" }),
        p({ milestoneSeq: 2, status: "on_hold" }),
      ]),
    ).toEqual({ status: "on_hold", label: "Milestone 2" });
  });
  it("is paid when everything is paid", () => {
    expect(
      paymentMilestone([p({ status: "paid" }), p({ milestoneSeq: 2, status: "paid" })]),
    ).toEqual({ status: "paid", label: "All paid" });
  });
});

describe("outstandingPayments", () => {
  it("keeps unpaid and on-hold assignment rows, soonest due first", () => {
    const rows = [
      { id: "1", kind: "assignment" as const, status: "paid" as const, dueDate: null },
      { id: "2", kind: "assignment" as const, status: "on_hold" as const, dueDate: null },
      { id: "3", kind: "assignment" as const, status: "approved" as const, dueDate: "2026-12-01" },
      { id: "4", kind: "reversal" as const, status: "approved" as const, dueDate: null },
      { id: "5", kind: "assignment" as const, status: "cancelled" as const, dueDate: null },
    ];
    expect(outstandingPayments(rows).map((r) => r.id)).toEqual(["3", "2"]);
  });
});

describe("upcomingDeadlines", () => {
  it("keeps confirmed deadlines of ongoing work, soonest first, and flags overdue", () => {
    const rows = [
      row({ id: "a", deadline: "2026-12-05" }),
      row({ id: "b", deadline: "2026-11-10" }),
      row({ id: "c", deadline: "2026-11-20", deadlineConfirmed: false }),
      row({ id: "d", deadline: "2026-11-21", stage: "completed" }),
      row({ id: "e", deadline: null }),
    ];
    expect(upcomingDeadlines(rows, "2026-11-17")).toEqual([
      { row: rows[1], overdue: true },
      { row: rows[0], overdue: false },
    ]);
  });
});

describe("feedback", () => {
  it("groups revision statuses into the editor's filters", () => {
    expect(feedbackGroupOf("requested")).toBe("open");
    expect(feedbackGroupOf("disputed")).toBe("open");
    expect(feedbackGroupOf("acknowledged")).toBe("in_progress");
    expect(feedbackGroupOf("in_progress")).toBe("in_progress");
    expect(feedbackGroupOf("resubmitted")).toBe("resubmitted");
    expect(feedbackGroupOf("approved")).toBe("resolved");
  });
  it("parses the filter", () => {
    expect(parseFeedbackParams({})).toEqual({ status: "all", page: 1 });
    expect(parseFeedbackParams({ status: "resolved", page: "2" })).toEqual({
      status: "resolved",
      page: 2,
    });
    expect(parseFeedbackParams({ status: "nope" }).status).toBe("all");
  });
});

describe("parseTab", () => {
  it("defaults to overview so old links still work", () => {
    expect(parseTab(undefined)).toBe("overview");
    expect(parseTab("bogus")).toBe("overview");
    expect(parseTab("feedback")).toBe("feedback");
    expect(parseTab(["files", "brief"])).toBe("files");
  });
});

describe("shortRef", () => {
  it("is the first 8 characters of the id, upper case", () => {
    expect(shortRef("6f3c2d1e-0b4a-4c6d-8e9f-1a2b3c4d5e61")).toBe("6F3C2D1E");
  });
});

describe("buildActivity", () => {
  it("merges events newest first without amounts", () => {
    const events = buildActivity({
      negotiations: [
        { id: "n1", fromRole: "admin", action: "offer", createdAt: "2026-11-01T00:00:00Z" },
        { id: "n2", fromRole: "editor", action: "accept", createdAt: "2026-11-02T00:00:00Z" },
      ],
      assignments: [{ id: "a1", confirmedAt: "2026-11-03T00:00:00Z" }],
      confirmations: [
        { id: "c1", briefVersion: 1, deadline: "2026-12-01", confirmedAt: "2026-11-04T00:00:00Z" },
      ],
      submissions: [
        {
          id: "s1",
          version: 1,
          isLate: false,
          submittedAt: "2026-11-05T00:00:00Z",
          outcome: "revision_requested",
          reviewedAt: "2026-11-06T00:00:00Z",
        },
      ],
      revisions: [
        {
          id: "r1",
          type: "client_revision",
          roundNumber: 1,
          createdAt: "2026-11-06T00:00:01Z",
          acknowledgedAt: "2026-11-07T00:00:00Z",
          resubmittedAt: null,
          resolvedAt: null,
        },
      ],
    });
    expect(events.map((e) => e.label)).toEqual([
      "You acknowledged the client revision (round 1)",
      "Change request: client revision (round 1)",
      "Version 1 reviewed: Revision requested",
      "Version 1 submitted",
      "Brief version 1 confirmed, deadline 2026-12-01",
      "The studio confirmed you",
      "You accepted",
      "The studio made an offer",
    ]);
    expect(events.every((e) => !/\d{3,}\.\d|LKR/.test(e.label))).toBe(true);
  });
});

describe("drivingAssignments", () => {
  const a = (id: string, project_id: string, status: string) =>
    ({ id, project_id, status }) as { id: string; project_id: string; status: "offered" };
  it("prefers the newest live assignment, else the newest, per project", () => {
    const rows = [
      a("a3", "p1", "declined"),
      a("a2", "p1", "in_progress"),
      a("a1", "p1", "offered"),
      a("b1", "p2", "not_selected"),
    ];
    const { current, projectIds } = drivingAssignments(rows, 10);
    expect(current.get("p1")?.id).toBe("a2");
    expect(current.get("p2")?.id).toBe("b1");
    expect(projectIds).toEqual(["p1", "p2"]);
  });
  it("caps the number of projects, keeping the most recently assigned", () => {
    const rows = [a("x", "p1", "offered"), a("y", "p2", "offered"), a("z", "p3", "offered")];
    const { current, projectIds } = drivingAssignments(rows, 2);
    expect(projectIds).toEqual(["p1", "p2"]);
    expect(current.has("p3")).toBe(false);
  });
});

describe("queryProjectRows tie-break", () => {
  it("orders equal keys by id so pages are stable", () => {
    const rows = [
      row({ id: "c", title: "Same", deadline: "2026-12-01" }),
      row({ id: "a", title: "Same", deadline: "2026-12-01" }),
      row({ id: "b", title: "same", deadline: "2026-12-01" }),
    ];
    for (const sort of ["title", "deadline", "activity"] as const) {
      expect(queryProjectRows(rows, { filter: "all", q: "", sort }).map((r) => r.id)).toEqual([
        "a",
        "b",
        "c",
      ]);
    }
  });
});
