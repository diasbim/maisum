'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

export function MerchantTabs({ merchantId }: { merchantId: string }) {
  const pathname = usePathname();
  const base = `/admin/merchants/${encodeURIComponent(merchantId)}`;

  const tabs = [
    { href: base, label: 'Resumo' },
    { href: `${base}/entitlements`, label: 'Entitlements' },
    { href: `${base}/audit`, label: 'Auditoria' },
  ];

  return (
    <nav className="tabs" aria-label="Vistas do negócio">
      {tabs.map((tab) => (
        <Link
          key={tab.href}
          href={tab.href}
          // Decoded before comparing: the href is percent-encoded and the
          // pathname the router reports is not, so an id with a space or an
          // accent would never match.
          aria-current={
            decodeURIComponent(pathname) === decodeURIComponent(tab.href)
              ? 'page'
              : undefined
          }
        >
          {tab.label}
        </Link>
      ))}
    </nav>
  );
}
