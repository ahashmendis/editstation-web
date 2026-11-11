import type { Json } from "@/lib/supabase/database.types";

type Snapshot = {
  full_name?: string | null;
  email?: string | null;
  phone?: string | null;
  region?: string | null;
  experience_years?: number | null;
  experience_summary?: string | null;
  availability?: string | null;
  typical_turnaround?: string | null;
  hardware?: string | null;
  software_other?: string | null;
  specialisations?: string[];
  software?: string[];
  portfolio_links?: { url: string; label: string | null }[];
};

function asSnapshot(value: Json | null): Snapshot | null {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as Snapshot) : null;
}

/** Only render https links; anything else is shown as plain text. */
function SafeLink({ url, label }: { url: string; label: string | null }) {
  const isHttps = /^https:\/\//.test(url);
  const text = label ? `${label} — ${url}` : url;
  return isHttps ? (
    <a
      href={url}
      target="_blank"
      rel="noopener noreferrer nofollow"
      className="break-all underline"
    >
      {text}
    </a>
  ) : (
    <span className="break-all">{text}</span>
  );
}

/** Read-only view of what an applicant submitted (frozen at submission). */
export function SnapshotView({
  snapshot,
  showContact = false,
}: {
  snapshot: Json | null;
  showContact?: boolean;
}) {
  const s = asSnapshot(snapshot);
  if (!s) return <p className="text-muted-foreground text-sm">Nothing submitted yet.</p>;

  const rows: [string, string | null | undefined][] = [
    ["Full name", s.full_name],
    ...(showContact
      ? ([
          ["Email", s.email],
          ["Phone", s.phone],
        ] as [string, string | null | undefined][])
      : []),
    ["Location", s.region],
    ["Experience", s.experience_years != null ? `${s.experience_years} years` : null],
    ["Specialisations", s.specialisations?.join(", ")],
    ["Software", [...(s.software ?? []), s.software_other].filter(Boolean).join(", ")],
    ["Availability", s.availability],
    ["Typical turnaround", s.typical_turnaround],
    ["Hardware", s.hardware],
  ];

  return (
    <div className="grid gap-4 text-sm">
      <dl className="grid gap-x-6 gap-y-2 sm:grid-cols-[12rem_1fr]">
        {rows.map(([label, value]) => (
          <div key={label} className="contents">
            <dt className="text-muted-foreground">{label}</dt>
            <dd>{value || "—"}</dd>
          </div>
        ))}
      </dl>
      {s.experience_summary ? (
        <div className="grid gap-1">
          <p className="text-muted-foreground">Experience summary</p>
          <p className="whitespace-pre-wrap">{s.experience_summary}</p>
        </div>
      ) : null}
      <div className="grid gap-1">
        <p className="text-muted-foreground">Portfolio</p>
        <ul className="grid gap-1">
          {(s.portfolio_links ?? []).map((link) => (
            <li key={link.url}>
              <SafeLink url={link.url} label={link.label} />
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}

export { SafeLink };
