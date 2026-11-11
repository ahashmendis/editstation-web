import { describe, expect, it } from "vitest";

import { userMessageFromDbError } from "./db-errors";
import {
  approveSchema,
  editorAccessSchema,
  editorProfileSchema,
  profileFormInput,
  requestResponseSchema,
} from "./schemas";

function form(entries: [string, string][]) {
  const data = new FormData();
  for (const [key, value] of entries) data.append(key, value);
  return data;
}

describe("editorProfileSchema via profileFormInput", () => {
  it("accepts a partial draft and turns blanks into null", () => {
    const result = editorProfileSchema.safeParse(profileFormInput(form([["fullName", " Nimal "]])));
    expect(result.success).toBe(true);
    expect(result.data?.fullName).toBe("Nimal");
    expect(result.data?.phone).toBeNull();
    expect(result.data?.experienceYears).toBeNull();
    expect(result.data?.links).toEqual([]);
  });

  it("collects repeated checkbox and link fields, dropping empty link rows", () => {
    const input = profileFormInput(
      form([
        ["specialisations", "long_form"],
        ["specialisations", "motion_graphics"],
        ["software", "capcut"],
        ["linkUrl", "https://vimeo.com/1"],
        ["linkLabel", "Reel"],
        ["linkUrl", ""],
        ["linkLabel", ""],
      ]),
    );
    const result = editorProfileSchema.safeParse(input);
    expect(result.success).toBe(true);
    expect(result.data?.specialisations).toEqual(["long_form", "motion_graphics"]);
    expect(result.data?.links).toEqual([{ url: "https://vimeo.com/1", label: "Reel" }]);
  });

  it.each(["http://insecure.example", "javascript:alert(1)", "vimeo.com/1", "https://a b.com"])(
    "rejects the portfolio link %j",
    (url) => {
      const result = editorProfileSchema.safeParse(profileFormInput(form([["linkUrl", url]])));
      expect(result.success).toBe(false);
    },
  );

  it("rejects more than 10 links", () => {
    const entries: [string, string][] = Array.from({ length: 11 }, (_, i) => [
      "linkUrl",
      `https://example.com/${i}`,
    ]);
    expect(editorProfileSchema.safeParse(profileFormInput(form(entries))).success).toBe(false);
  });

  it.each(["-1", "61", "2.5", "abc"])("rejects experience years %j", (years) => {
    const result = editorProfileSchema.safeParse(
      profileFormInput(form([["experienceYears", years]])),
    );
    expect(result.success).toBe(false);
  });

  it("rejects option codes that are not simple identifiers", () => {
    const result = editorProfileSchema.safeParse(
      profileFormInput(form([["software", "x'; drop table"]])),
    );
    expect(result.success).toBe(false);
  });
});

describe("requestResponseSchema", () => {
  const requestId = "3b0d2f3e-8a3c-4d2b-9c1f-1a2b3c4d5e6f";

  it("needs a response or a link", () => {
    expect(
      requestResponseSchema.safeParse({ requestId, response: " ", responseLink: "" }).success,
    ).toBe(false);
    expect(
      requestResponseSchema.safeParse({
        requestId,
        response: "",
        responseLink: "https://drive.example.com/x",
      }).success,
    ).toBe(true);
  });

  it("rejects a non-https response link", () => {
    expect(
      requestResponseSchema.safeParse({ requestId, response: "ok", responseLink: "http://x.com" })
        .success,
    ).toBe(false);
  });
});

describe("admin schemas", () => {
  const id = "3b0d2f3e-8a3c-4d2b-9c1f-1a2b3c4d5e6f";

  it("requires a level to approve", () => {
    expect(approveSchema.safeParse({ applicationId: id, level: "", message: "" }).success).toBe(
      false,
    );
    expect(
      approveSchema.safeParse({ applicationId: id, level: "junior", message: "" }).success,
    ).toBe(true);
  });

  it("only allows active/suspended/revoked and requires a reason", () => {
    expect(
      editorAccessSchema.safeParse({ editorId: id, status: "none", reason: "x" }).success,
    ).toBe(false);
    expect(
      editorAccessSchema.safeParse({ editorId: id, status: "suspended", reason: " " }).success,
    ).toBe(false);
  });
});

describe("userMessageFromDbError", () => {
  it("passes through our own ES4xx messages", () => {
    expect(userMessageFromDbError({ code: "ES409", message: "Already submitted." })).toBe(
      "Already submitted.",
    );
  });

  it("hides unexpected database errors", () => {
    expect(
      userMessageFromDbError({ code: "23505", message: 'duplicate key value violates "x"' }),
    ).toBe("Something went wrong. Please try again.");
  });
});
