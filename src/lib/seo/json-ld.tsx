import { SUPPORT_EMAIL } from "@/lib/site-contact";

import { absoluteUrl, SITE_NAME } from "./site";

type JsonLdValue = Record<string, unknown>;

/** Renders one JSON-LD block. "<" is escaped so page text can never close the script tag. */
export function JsonLd({ data }: { data: JsonLdValue }) {
  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: JSON.stringify(data).replace(/</g, "\\u003c") }}
    />
  );
}

/**
 * Organisation and website for the home page. Only facts the site already states: the name, the
 * URL, the Lenscape Studios relationship from the footer, and what the platform does. No address,
 * phone, ratings, reviews, awards or LocalBusiness markup: none of those are established.
 */
export function organizationJsonLd(): JsonLdValue {
  return {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "Organization",
        "@id": `${absoluteUrl("/")}#organization`,
        name: SITE_NAME,
        url: absoluteUrl("/"),
        logo: absoluteUrl("/apple-icon"),
        description:
          "A production network that matches video editing projects with vetted freelance editors and manages the work from brief to delivery.",
        parentOrganization: { "@type": "Organization", name: "Lenscape Studios" },
        contactPoint: {
          "@type": "ContactPoint",
          contactType: "customer support",
          email: SUPPORT_EMAIL,
        },
      },
      {
        "@type": "WebSite",
        "@id": `${absoluteUrl("/")}#website`,
        name: SITE_NAME,
        url: absoluteUrl("/"),
        publisher: { "@id": `${absoluteUrl("/")}#organization` },
      },
    ],
  };
}

/** Breadcrumb trail for a page one level below the home page. */
export function breadcrumbJsonLd(name: string, path: string): JsonLdValue {
  return {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: [
      { "@type": "ListItem", position: 1, name: "Home", item: absoluteUrl("/") },
      { "@type": "ListItem", position: 2, name, item: absoluteUrl(path) },
    ],
  };
}
