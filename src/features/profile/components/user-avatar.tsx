import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { cn } from "@/lib/utils";

import { initialsFor } from "../avatar";

/**
 * A person's picture (short-lived signed URL created server-side) with an initials fallback.
 * Decorative by default: the name is always shown next to it, so screen readers skip it.
 */
export function UserAvatar({
  url,
  name,
  email,
  size = "default",
  className,
  label,
}: {
  url: string | null | undefined;
  name: string | null | undefined;
  email?: string | null;
  size?: "default" | "sm" | "lg" | "xl";
  className?: string;
  /** Accessible name when the avatar stands alone. */
  label?: string;
}) {
  return (
    <Avatar
      size={size === "xl" ? "lg" : size}
      className={cn(size === "xl" && "size-20", className)}
      aria-hidden={label ? undefined : true}
      aria-label={label}
      role={label ? "img" : undefined}
    >
      {url ? <AvatarImage src={url} alt="" referrerPolicy="no-referrer" /> : null}
      <AvatarFallback className={cn(size === "xl" && "text-xl")}>
        {initialsFor(name, email)}
      </AvatarFallback>
    </Avatar>
  );
}
