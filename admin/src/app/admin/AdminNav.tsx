'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

/**
 * The console's map.
 *
 * Grouped rather than flat because the sections answer different questions:
 * "how is the platform doing" is a different job from "fix this business's
 * ledger", and mixing them in one list makes the destructive jobs sit one slip
 * away from the read-only screens.
 */
const GROUPS = [
  {
    label: 'Operação',
    items: [
      { href: '/admin', label: 'Visão geral' },
      { href: '/admin/merchants', label: 'Negócios' },
    ],
  },
  {
    label: 'Comercial',
    items: [
      { href: '/admin/plans', label: 'Planos' },
      { href: '/admin/plans/reconciliacao', label: 'Reconciliação' },
    ],
  },
  {
    label: 'Clientes',
    items: [
      { href: '/admin/customers', label: 'Clientes' },
      { href: '/admin/nfc', label: 'Cartões NFC' },
    ],
  },
  {
    label: 'Manutenção',
    items: [
      { href: '/admin/operations', label: 'Operações' },
      { href: '/admin/retention', label: 'Retenção' },
    ],
  },
  {
    label: 'Governança',
    items: [
      { href: '/admin/audit', label: 'Auditoria' },
      { href: '/admin/access', label: 'Acessos' },
    ],
  },
] as const;

/**
 * `/admin` matches exactly; everything else matches by prefix so a merchant
 * detail page still highlights "Negócios".
 *
 * `/admin/plans` is the exception: a prefix match would light it up on
 * `/admin/plans/reconciliacao` too, leaving two entries current at once.
 */
function isCurrent(href: string, pathname: string): boolean {
  if (href === '/admin') return pathname === '/admin';
  if (href === '/admin/plans') {
    return pathname === '/admin/plans' || pathname === '/admin/plans/';
  }
  return pathname === href || pathname.startsWith(`${href}/`);
}

export function AdminNav() {
  const pathname = usePathname();

  return (
    <>
      {GROUPS.map((group) => (
        <div className="sidebar__group" key={group.label}>
          <p className="sidebar__label">{group.label}</p>
          {group.items.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              aria-current={isCurrent(item.href, pathname) ? 'page' : undefined}
            >
              <span className="sidebar__mark" aria-hidden />
              {item.label}
            </Link>
          ))}
        </div>
      ))}
    </>
  );
}
