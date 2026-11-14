"use client";

import { useRef, useState } from "react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";

import { selectClassName } from "./select-class";
import { MAX_DELIVERABLES, MAX_REFERENCES } from "../constants";

export type DeliverableRow = {
  id: string;
  name: string;
  format: string;
  resolution: string;
  aspectRatio: string;
  durationSeconds: string;
  notes: string;
};

export type ReferenceRow = {
  id: string;
  title: string;
  url: string;
  startSeconds: string;
  endSeconds: string;
  observationNotes: string;
  priority: string;
  category: string;
  accessNotes: string;
};

const emptyDeliverable: DeliverableRow = {
  id: "",
  name: "",
  format: "",
  resolution: "",
  aspectRatio: "",
  durationSeconds: "",
  notes: "",
};

const emptyReference: ReferenceRow = {
  id: "",
  title: "",
  url: "",
  startSeconds: "",
  endSeconds: "",
  observationNotes: "",
  priority: "essential",
  category: "",
  accessNotes: "",
};

/** Rows live in state (not the DOM) so a failed save keeps everything the admin typed. */
function useRows<T extends Record<string, string>>(initial: T[], blank: T) {
  const counter = useRef(initial.length);
  const [rows, setRows] = useState(() => initial.map((row, i) => ({ key: i, row })));
  return {
    rows,
    add: () => setRows((r) => [...r, { key: counter.current++, row: { ...blank } }]),
    remove: (key: number) => setRows((r) => r.filter((x) => x.key !== key)),
    set: (key: number, field: keyof T, value: string) =>
      setRows((r) =>
        r.map((x) => (x.key === key ? { ...x, row: { ...x.row, [field]: value } } : x)),
      ),
  };
}

function Cell({
  id,
  label,
  children,
  className,
}: {
  id: string;
  label: string;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={`grid gap-1 ${className ?? ""}`}>
      <Label htmlFor={id}>{label}</Label>
      {children}
    </div>
  );
}

export function DeliverablesEditor({ initial }: { initial: DeliverableRow[] }) {
  const { rows, add, remove, set } = useRows(initial, emptyDeliverable);
  return (
    <fieldset className="grid gap-3">
      <legend className="text-sm font-medium">Deliverables</legend>
      <p className="text-muted-foreground text-sm">
        What the editor hands back. At least one is needed to open the project.
      </p>
      {rows.length === 0 ? (
        <p className="text-muted-foreground text-sm">No deliverables yet.</p>
      ) : null}
      {rows.map(({ key, row }, i) => {
        const id = (f: string) => `deliverable-${key}-${f}`;
        const bind = (f: keyof DeliverableRow) => ({
          id: id(f),
          name: `deliverable.${f}`,
          value: row[f],
          onChange: (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
            set(key, f, e.target.value),
        });
        return (
          <div key={key} className="grid gap-3 rounded-lg border p-3">
            <input type="hidden" name="deliverable.id" value={row.id} />
            <p className="text-muted-foreground text-xs font-medium">Deliverable {i + 1}</p>
            <div className="grid gap-3 sm:grid-cols-2">
              <Cell id={id("name")} label="Name" className="sm:col-span-2">
                <Input {...bind("name")} maxLength={200} />
              </Cell>
              <Cell id={id("format")} label="Format">
                <Input {...bind("format")} placeholder="MP4" maxLength={100} />
              </Cell>
              <Cell id={id("resolution")} label="Resolution">
                <Input {...bind("resolution")} placeholder="1920x1080" maxLength={100} />
              </Cell>
              <Cell id={id("aspectRatio")} label="Aspect ratio">
                <Input {...bind("aspectRatio")} placeholder="16:9" maxLength={50} />
              </Cell>
              <Cell id={id("durationSeconds")} label="Duration (seconds)">
                <Input {...bind("durationSeconds")} inputMode="numeric" />
              </Cell>
              <Cell id={id("notes")} label="Notes" className="sm:col-span-2">
                <Textarea {...bind("notes")} rows={2} maxLength={2000} />
              </Cell>
            </div>
            <Button
              type="button"
              variant="outline"
              className="justify-self-start"
              onClick={() => remove(key)}
            >
              Remove deliverable {i + 1}
            </Button>
          </div>
        );
      })}
      <Button
        type="button"
        variant="outline"
        className="justify-self-start"
        onClick={add}
        disabled={rows.length >= MAX_DELIVERABLES}
      >
        Add deliverable
      </Button>
    </fieldset>
  );
}

export function ReferencesEditor({ initial }: { initial: ReferenceRow[] }) {
  const { rows, add, remove, set } = useRows(initial, emptyReference);
  return (
    <fieldset className="grid gap-3">
      <legend className="text-sm font-medium">References</legend>
      <p className="text-muted-foreground text-sm">
        Example videos to follow. Links must start with https://. Times are whole seconds or m:ss.
      </p>
      {rows.length === 0 ? (
        <p className="text-muted-foreground text-sm">No references yet.</p>
      ) : null}
      {rows.map(({ key, row }, i) => {
        const id = (f: string) => `reference-${key}-${f}`;
        const bind = (f: keyof ReferenceRow) => ({
          id: id(f),
          name: `reference.${f}`,
          value: row[f],
          onChange: (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
            set(key, f, e.target.value),
        });
        return (
          <div key={key} className="grid gap-3 rounded-lg border p-3">
            <input type="hidden" name="reference.id" value={row.id} />
            <p className="text-muted-foreground text-xs font-medium">Reference {i + 1}</p>
            <div className="grid gap-3 sm:grid-cols-2">
              <Cell id={id("title")} label="Title">
                <Input {...bind("title")} maxLength={200} />
              </Cell>
              <Cell id={id("url")} label="Link (https only)">
                <Input {...bind("url")} type="url" inputMode="url" maxLength={2048} />
              </Cell>
              <Cell id={id("startSeconds")} label="Start (seconds)">
                <Input {...bind("startSeconds")} inputMode="numeric" />
              </Cell>
              <Cell id={id("endSeconds")} label="End (seconds)">
                <Input {...bind("endSeconds")} inputMode="numeric" />
              </Cell>
              <Cell id={id("priority")} label="Priority">
                <select
                  id={id("priority")}
                  name="reference.priority"
                  className={selectClassName}
                  value={row.priority}
                  onChange={(e) => set(key, "priority", e.target.value)}
                >
                  <option value="essential">Essential</option>
                  <option value="optional">Optional</option>
                </select>
              </Cell>
              <Cell id={id("category")} label="Category">
                <Input {...bind("category")} placeholder="Pacing, colour, sound…" maxLength={80} />
              </Cell>
              <Cell id={id("observationNotes")} label="What to notice" className="sm:col-span-2">
                <Textarea {...bind("observationNotes")} rows={2} maxLength={2000} />
              </Cell>
              <Cell id={id("accessNotes")} label="Access notes" className="sm:col-span-2">
                <Input
                  {...bind("accessNotes")}
                  placeholder="Password, login hints…"
                  maxLength={1000}
                />
              </Cell>
            </div>
            <Button
              type="button"
              variant="outline"
              className="justify-self-start"
              onClick={() => remove(key)}
            >
              Remove reference {i + 1}
            </Button>
          </div>
        );
      })}
      <Button
        type="button"
        variant="outline"
        className="justify-self-start"
        onClick={add}
        disabled={rows.length >= MAX_REFERENCES}
      >
        Add reference
      </Button>
    </fieldset>
  );
}
