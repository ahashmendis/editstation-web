import { readFileSync } from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

// Keeps the colour tokens in src/app/globals.css (documented in docs/DESIGN_SYSTEM.md) from
// drifting below WCAG contrast. Reads the real stylesheet; no browser needed.

const css = readFileSync(path.join(process.cwd(), "src/app/globals.css"), "utf8").replaceAll(
  "\r\n",
  "\n",
);
const MIN_TOKENS = 20; // guards against the parser silently matching almost nothing

function block(startMarker: string, endMarker: string) {
  const start = css.indexOf(startMarker);
  expect(start, `${startMarker} not found`).toBeGreaterThan(-1);
  const end = css.indexOf(endMarker, start);
  expect(end, `${endMarker} not found after ${startMarker}`).toBeGreaterThan(start);
  return css.slice(start, end);
}

function tokens(source: string) {
  const map = new Map<string, [number, number, number]>();
  for (const m of source.matchAll(/--([\w-]+):\s*oklch\(([\d.]+)\s+([\d.]+)\s+([\d.]+)\)/g)) {
    map.set(m[1], [Number(m[2]), Number(m[3]), Number(m[4])]);
  }
  return map;
}

const light = tokens(block(":root {", "\n}\n"));
const dark = tokens(block(".dark {", "\n}\n"));
// The landing page's light base (brand purple as --primary), applied only while .landing exists.
const landing = tokens(block(":root:has(.landing) {", "\n}\n"));

function luminance([L, C, h]: [number, number, number]) {
  const a = C * Math.cos((h * Math.PI) / 180);
  const b = C * Math.sin((h * Math.PI) / 180);
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3;
  const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3;
  const s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3;
  const rgb = [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  ].map((v) => Math.min(1, Math.max(0, v))); // linear sRGB (no gamma), clamped to the gamut
  return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2];
}

function contrast(theme: Map<string, [number, number, number]>, fg: string, bg: string) {
  const f = theme.get(fg);
  const g = theme.get(bg);
  expect(f, `missing token ${fg}`).toBeDefined();
  expect(g, `missing token ${bg}`).toBeDefined();
  const [hi, lo] = [luminance(f!), luminance(g!)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

// [foreground token, background token, minimum ratio]
const PAIRS: [string, string, number][] = [
  ["foreground", "background", 7],
  ["card-foreground", "card", 7],
  ["muted-foreground", "background", 4.5],
  ["muted-foreground", "card", 4.5],
  ["muted-foreground", "muted", 4.5],
  ["secondary-foreground", "secondary", 4.5],
  ["primary-foreground", "primary", 4.5],
  ["brand-text", "background", 4.5],
  ["brand-text", "card", 4.5],
  ["destructive", "background", 4.5],
  ["destructive", "card", 4.5],
  ["destructive", "muted", 4.5],
  ["success", "card", 4.5],
  ["success", "background", 4.5],
  ["warning", "card", 4.5],
  ["warning", "background", 4.5],
  ["ring", "background", 3],
  ["ring", "card", 3],
  ["primary", "background", 3], // brand purple as a graphic or large text on the page
];

describe.each([
  ["dark", dark],
  ["light", light],
])("%s theme contrast", (_name, theme) => {
  it("defines every token the other theme defines", () => {
    expect(theme.size).toBeGreaterThan(MIN_TOKENS);
    const other = theme === dark ? light : dark;
    expect([...theme.keys()].sort()).toEqual([...other.keys()].sort());
  });

  it.each(PAIRS)("%s on %s is at least %d:1", (fg, bg, min) => {
    expect(contrast(theme, fg, bg)).toBeGreaterThanOrEqual(min);
  });
});

describe("landing page tokens", () => {
  it.each([
    ...PAIRS.filter(([fg, bg]) => !fg.startsWith("chart") && !bg.startsWith("chart")),
    ["landing-ink-foreground", "landing-ink", 7],
    ["landing-ink-muted", "landing-ink", 4.5],
  ] as [string, string, number][])("%s on %s is at least %d:1", (fg, bg, min) => {
    expect(landing.size).toBeGreaterThan(MIN_TOKENS);
    expect(contrast(landing, fg, bg)).toBeGreaterThanOrEqual(min);
  });
});
