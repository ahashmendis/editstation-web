import { describe, expect, it } from "vitest";

import { inquiryActivityLabel } from "./constants";

describe("inquiryActivityLabel", () => {
  it.each([
    ["inquiry.submitted", "Submitted"],
    ["inquiry.reviewing", "Marked reviewing"],
    ["inquiry.contacted", "Marked contacted"],
    ["inquiry.in_discussion", "In discussion"],
    ["inquiry.converted", "Converted to project"],
    ["inquiry.declined", "Declined"],
    ["inquiry.closed", "Closed"],
    ["inquiry.spam", "Marked as spam"],
    ["inquiry.unknown", "Updated"],
  ])("%s -> %s", (code, label) => {
    expect(inquiryActivityLabel(code)).toBe(label);
  });
});
