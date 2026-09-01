import type { Metadata } from 'next';
import { Bricolage_Grotesque, Outfit } from 'next/font/google';

import './globals.css';

/**
 * The design system's two families. Loaded through `next/font` rather than a
 * Google Fonts <link>: they are self-hosted at build time, so there is no
 * third-party request per page load and no flash of fallback text.
 */
const headingFont = Bricolage_Grotesque({
  subsets: ['latin'],
  weight: ['600', '700', '800'],
  variable: '--font-head',
  display: 'swap',
});

const bodyFont = Outfit({
  subsets: ['latin'],
  weight: ['400', '500', '600', '700'],
  variable: '--font-body',
  display: 'swap',
});

export const metadata: Metadata = {
  title: 'Portal de gestão | MaisUm',
  description: 'Operações internas MaisUm.',
  robots: { index: false, follow: false },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html
      lang="pt-MZ"
      className={`${headingFont.variable} ${bodyFont.variable}`}
    >
      <body>{children}</body>
    </html>
  );
}
