import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { defaultRobots, SITE_NAME, siteUrl } from "@/lib/seo/site";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

// Site-wide defaults. Every public page sets its own title, description and canonical via
// pageMetadata(); private areas set NO_INDEX. Indexing stays off until SEO_INDEXING=on.
export const metadata: Metadata = {
  metadataBase: new URL(siteUrl()),
  title: "EDITSTATION: professional video editing, managed end to end",
  description:
    "EDITSTATION, a Lenscape Studios production network, matches video editing projects with vetted freelance editors and manages the work from brief to delivery.",
  applicationName: SITE_NAME,
  robots: defaultRobots(),
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}>
      <body className="flex min-h-full flex-col">{children}</body>
    </html>
  );
}
