import { describe, expect, it } from "vitest";

import {
  budgetRangeSchema,
  inquiryFormInput,
  inquiryKeptValues,
  inquirySchema,
  inquiryStatusSchema,
  serviceTypeSchema,
} from "./schemas";

function form(entries: [string, string][]) {
  const data = new FormData();
  for (const [key, value] of entries) data.append(key, value);
  return data;
}

const minimal: [string, string][] = [
  ["contactName", "Asha"],
  ["email", " Asha@Example.com "],
  ["serviceType", "long_form"],
  ["description", "A 3-minute brand film."],
  ["budgetRangeId", "discuss"],
];

describe("inquirySchema", () => {
  it("accepts a minimal inquiry and normalises it", () => {
    const result = inquirySchema.safeParse(inquiryFormInput(form(minimal)));
    expect(result.success).toBe(true);
    expect(result.data?.email).toBe("asha@example.com");
    expect(result.data?.budgetRangeId).toBeNull();
    expect(result.data?.expectedDeadline).toBeNull();
    expect(result.data?.links).toEqual([]);
  });

  it.each(["contactName", "description"])("requires %s", (field) => {
    const entries = minimal.map(([k, v]): [string, string] => [k, k === field ? " " : v]);
    expect(inquirySchema.safeParse(inquiryFormInput(form(entries))).success).toBe(false);
  });

  it("requires a service type", () => {
    const entries = minimal.filter(([k]) => k !== "serviceType");
    expect(inquirySchema.safeParse(inquiryFormInput(form(entries))).success).toBe(false);
  });

  it("accepts a budget range id and rejects junk", () => {
    const withRange = minimal.map(([k, v]): [string, string] => [
      k,
      k === "budgetRangeId" ? "3b0d2f3e-8a3c-4d2b-9c1f-1a2b3c4d5e6f" : v,
    ]);
    expect(inquirySchema.safeParse(inquiryFormInput(form(withRange))).success).toBe(true);
    const junk = minimal.map(([k, v]): [string, string] => [
      k,
      k === "budgetRangeId" ? "1; drop" : v,
    ]);
    expect(inquirySchema.safeParse(inquiryFormInput(form(junk))).success).toBe(false);
  });

  it.each(["2026-13-01", "31/12/2026", "tomorrow"])("rejects the deadline %j", (date) => {
    const result = inquirySchema.safeParse(
      inquiryFormInput(form([...minimal, ["expectedDeadline", date]])),
    );
    expect(result.success).toBe(false);
  });

  it("rejects http reference links and keeps https ones", () => {
    const bad = inquirySchema.safeParse(
      inquiryFormInput(
        form([...minimal, ["linkUrl", "http://insecure.example"], ["linkLabel", ""]]),
      ),
    );
    expect(bad.success).toBe(false);
    const good = inquirySchema.safeParse(
      inquiryFormInput(
        form([...minimal, ["linkUrl", "https://vimeo.com/1"], ["linkLabel", "Pacing"]]),
      ),
    );
    expect(good.data?.links).toEqual([{ url: "https://vimeo.com/1", label: "Pacing" }]);
  });

  it("keeps entered values for refilling the form, but not the honeypot", () => {
    const kept = inquiryKeptValues(form([...minimal, ["website", "spam"]]));
    expect(kept.contactName).toBe("Asha");
    expect(kept).not.toHaveProperty("website");
  });
});

describe("admin inquiry schemas", () => {
  const id = "3b0d2f3e-8a3c-4d2b-9c1f-1a2b3c4d5e6f";

  it("never allows setting 'converted' by hand", () => {
    expect(
      inquiryStatusSchema.safeParse({ inquiryId: id, status: "converted", note: "" }).success,
    ).toBe(false);
    expect(inquiryStatusSchema.safeParse({ inquiryId: id, status: "spam", note: "" }).success).toBe(
      true,
    );
  });

  it("validates service type codes", () => {
    expect(
      serviceTypeSchema.safeParse({ code: "Event Films", label: "x", sortOrder: "1" }).success,
    ).toBe(false);
    const ok = serviceTypeSchema.safeParse({
      code: "event_films",
      label: "Event films",
      sortOrder: "",
    });
    expect(ok.data).toEqual({
      code: "event_films",
      label: "Event films",
      sortOrder: 0,
      active: false,
    });
  });

  it("checks budget range amounts and currency", () => {
    const base = { id: "", label: "Small", currency: "lkr", sortOrder: "1", active: "on" };
    const ok = budgetRangeSchema.safeParse({ ...base, minAmount: "100", maxAmount: "200" });
    expect(ok.data?.currency).toBe("LKR");
    expect(ok.data?.active).toBe(true);
    expect(
      budgetRangeSchema.safeParse({ ...base, minAmount: "300", maxAmount: "200" }).success,
    ).toBe(false);
    expect(
      budgetRangeSchema.safeParse({ ...base, minAmount: "", maxAmount: "", currency: "rupees" })
        .success,
    ).toBe(false);
  });
});
