import Image from "next/image";

import { CLIENT_LOGOS, type ClientLogo } from "@/features/landing/clients";
import { container } from "@/features/landing/styles";

// Looping strip of client logos on a dark band (most logos are white marks). Grayscale until
// hovered; the loop pauses on hover/focus and is replaced by a static wrapped row under reduced
// motion (globals.css). The second copy exists only for the seamless loop and is hidden from
// assistive technology.

function LogoList({ copy }: { copy: 0 | 1 }) {
  const hidden = copy === 1;
  return (
    <ul
      aria-label={hidden ? undefined : "Clients"}
      aria-hidden={hidden ? "true" : undefined}
      className="landing-marquee-copy"
    >
      {CLIENT_LOGOS.map((logo) => (
        <li key={logo.src} className="flex h-16 items-center">
          <Logo logo={logo} decorative={hidden} />
        </li>
      ))}
    </ul>
  );
}

function Logo({ logo, decorative }: { logo: ClientLogo; decorative: boolean }) {
  const w = Math.round((logo.width / logo.height) * logo.displayHeight);
  return (
    <span
      className={`flex items-center opacity-75 grayscale transition-[filter,opacity] duration-300 hover:opacity-100 hover:grayscale-0 motion-reduce:transition-none ${
        logo.plate ? "rounded-md bg-white/90 px-2.5 py-1.5" : ""
      }`}
    >
      <Image
        src={logo.src}
        alt={decorative ? "" : logo.name}
        width={w}
        height={logo.displayHeight}
        sizes={`${w}px`}
        className="h-auto max-w-none"
        style={{ height: logo.displayHeight, width: w }}
      />
    </span>
  );
}

export function ClientsMarquee() {
  return (
    <section aria-labelledby="clients-title" className={`${container} pb-6`}>
      <div className="overflow-hidden rounded-3xl bg-[var(--landing-ink)] py-10 text-[var(--landing-ink-foreground)] sm:py-12">
        <h2
          id="clients-title"
          className="font-landing-ui px-6 text-center text-xs font-bold tracking-[0.14em] text-[var(--landing-ink-muted)] uppercase"
        >
          Brands we have worked with
        </h2>
        <div className="landing-marquee mt-8">
          <div className="landing-marquee-track">
            <LogoList copy={0} />
            <LogoList copy={1} />
          </div>
        </div>
      </div>
    </section>
  );
}
