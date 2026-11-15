import { describe, expect, it } from "vitest";

import {
  EDITOR_GATE_MESSAGE,
  EDITOR_GATE_UNKNOWN_MESSAGE,
  editorGateNotice,
  settlementEarnedLabel,
} from "./constants";

describe("editorGateNotice", () => {
  it("lets an open change begin and blocks the others with fixed wording", () => {
    expect(editorGateNotice("ok")).toBeNull();
    expect(editorGateNotice(undefined)).toBeNull();
    expect(editorGateNotice("needs_extra_pay")).toBe(EDITOR_GATE_MESSAGE.needs_extra_pay);
    expect(editorGateNotice("waiting_for_scope_approval")).toBe(
      EDITOR_GATE_MESSAGE.waiting_for_scope_approval,
    );
  });
  it("shows a neutral notice when the gate could not be checked", () => {
    expect(editorGateNotice("unknown")).toBe(EDITOR_GATE_UNKNOWN_MESSAGE);
  });
  it("never mentions client money", () => {
    for (const m of [...Object.values(EDITOR_GATE_MESSAGE), EDITOR_GATE_UNKNOWN_MESSAGE])
      expect(m).not.toMatch(/quote|price|client pay|LKR/i);
  });
});

describe("settlementEarnedLabel", () => {
  it("formats the proposed amount with its currency", () => {
    expect(settlementEarnedLabel(5500, "LKR")).toBe(
      "Editor earned, only to change the proposed 5,500 LKR",
    );
    expect(settlementEarnedLabel(12.5, "USD")).toBe(
      "Editor earned, only to change the proposed 12.50 USD",
    );
  });
});
