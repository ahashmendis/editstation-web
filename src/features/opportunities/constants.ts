import type { StatusTone } from "@/components/status-pill";
import type { Database } from "@/lib/supabase/database.types";

/** Open opportunities (spec docs/superpowers/specs/2026-11-16-open-opportunities-design.md). */

export type OpportunityStatus = Database["public"]["Enums"]["opportunity_status"];
export type InterestStatus = Database["public"]["Enums"]["opportunity_interest_status"];

/** The database refuses an 11th live interest (call 3); the UI says so up front. */
export const MAX_LIVE_INTERESTS = 10;

/** Business timezone (the database uses Asia/Colombo for dates): UTC+05:30, no daylight saving. */
export const BUSINESS_UTC_OFFSET = "+05:30";

export const INTEREST_STATUS_LABEL: Record<InterestStatus, string> = {
  interested: "Interested",
  withdrawn: "Withdrawn",
  selected: "Selected",
  not_selected: "Not selected",
};

export const INTEREST_STATUS_TONE: Record<InterestStatus, StatusTone> = {
  interested: "info",
  withdrawn: "neutral",
  selected: "success",
  not_selected: "neutral",
};

export const OPPORTUNITY_STATUS_LABEL: Record<OpportunityStatus, string> = {
  open: "Open",
  closed: "Closed",
  filled: "Editor chosen",
};

export const OPPORTUNITY_STATUS_TONE: Record<OpportunityStatus, StatusTone> = {
  open: "info",
  closed: "neutral",
  filled: "success",
};

/** One line every editor sees above the list (call 7). */
export const CONFIDENTIALITY_NOTICE =
  "These summaries are confidential. Do not share them outside EDITSTATION.";

/** The closing date is a business-timezone day: interest closes at the end of it. */
export function closesAtFromDate(date: string): string {
  return `${date}T23:59:59${BUSINESS_UTC_OFFSET}`;
}

/** The business-timezone day of a closing timestamp, for prefilling a date input. */
export function dateFromClosesAt(value: string | null): string {
  if (!value) return "";
  const shifted = new Date(new Date(value).getTime() + 5.5 * 60 * 60 * 1000);
  return Number.isNaN(shifted.getTime()) ? "" : shifted.toISOString().slice(0, 10);
}
