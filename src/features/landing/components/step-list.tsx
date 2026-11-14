// An ordered list of steps with a rail that fills as the list scrolls into view (CSS
// scroll-driven animation where supported; a full rail otherwise and under reduced motion).
export function StepList({ steps }: { steps: { title: string; body: string }[] }) {
  return (
    <div className="relative">
      <div aria-hidden="true" className="bg-border absolute top-2 bottom-2 left-[0.9375rem] w-px">
        <div className="landing-rail bg-brand-text absolute inset-0" />
      </div>
      <ol className="relative grid gap-6">
        {steps.map((step, i) => (
          <li key={step.title} className="grid grid-cols-[2rem_1fr] gap-4">
            <span
              aria-hidden="true"
              className="bg-card text-brand-text ring-border grid size-8 place-items-center rounded-full font-mono text-xs tabular-nums ring-1"
            >
              {i + 1}
            </span>
            <div className="grid gap-1 pt-1">
              <h4 className="font-semibold">{step.title}</h4>
              <p className="text-muted-foreground">{step.body}</p>
            </div>
          </li>
        ))}
      </ol>
    </div>
  );
}
