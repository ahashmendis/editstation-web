import { describe, expect, it } from "vitest";

import { driftReasons, gateChecklist, gateState, type GateRow } from "./constants";

const gate: GateRow = {
  compensation_approved: true,
  interpretation_required: false,
  interpretation_accepted: false,
  current_brief_version: 2,
  confirmed_brief_version: null,
  reacknowledgement_required: true,
  deadline_changed: false,
  amount_changed: false,
  deliverables_changed: false,
  brief_confirmed: false,
  client_deposit_verified: true,
  ready: false,
};
const confirmed: GateRow = {
  ...gate,
  brief_confirmed: true,
  confirmed_brief_version: 2,
  reacknowledgement_required: false,
  ready: true,
};

describe("gate helpers", () => {
  it("lists the interpretation step only when required", () => {
    expect(gateChecklist(gate, "editor").map((i) => i.key)).toEqual(["pay", "brief", "deposit"]);
    expect(
      gateChecklist({ ...gate, interpretation_required: true }, "editor").map((i) => i.key),
    ).toEqual(["pay", "interpretation", "brief", "deposit"]);
  });

  it("explains drift only after a confirmation exists", () => {
    expect(driftReasons(gate)).toEqual([]);
    expect(
      driftReasons({ ...gate, confirmed_brief_version: 1, deadline_changed: true }),
    ).toHaveLength(2);
  });

  it("derives the state label", () => {
    expect(gateState(gate, "confirmed", null).label).toBe("Awaiting brief confirmation");
    expect(gateState({ ...gate, confirmed_brief_version: 1 }, "confirmed", null).label).toBe(
      "Re-confirmation needed",
    );
    expect(
      gateState({ ...gate, interpretation_required: true }, "confirmed", "submitted").label,
    ).toBe("Interpretation to review");
    expect(gateState(confirmed, "confirmed", null).label).toBe("Ready to start");
    expect(gateState(confirmed, "in_progress", null).label).toBe("In progress");
  });

  it("shows only a status while the client deposit is unverified (Phase 12C)", () => {
    const waiting = { ...confirmed, client_deposit_verified: false, ready: false };
    expect(gateState(waiting, "confirmed", null).label).toBe("Waiting for the client deposit");
    const item = gateChecklist(waiting, "editor").find((i) => i.key === "deposit");
    expect(item).toMatchObject({ met: false, detail: "Waiting for the client deposit." });
    expect(JSON.stringify(gateChecklist(waiting, "editor"))).not.toMatch(/d{3,}|LKR|price/i);
  });
});
