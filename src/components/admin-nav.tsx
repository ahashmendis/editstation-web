import Link from "next/link";

const LINKS = [
  { href: "/admin", label: "Overview" },
  { href: "/admin/applications", label: "Applications" },
];

export function AdminNav() {
  return (
    <nav aria-label="Admin" className="border-b">
      <ul className="mx-auto flex w-full max-w-4xl gap-4 px-4 text-sm">
        {LINKS.map((link) => (
          <li key={link.href}>
            <Link
              href={link.href}
              className="text-muted-foreground hover:text-foreground inline-block py-3"
            >
              {link.label}
            </Link>
          </li>
        ))}
      </ul>
    </nav>
  );
}
