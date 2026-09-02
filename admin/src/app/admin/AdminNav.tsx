'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useCallback, useEffect, useId, useRef, useState } from 'react';

/**
 * The console's map.
 *
 * Grouped rather than flat because the sections answer different questions:
 * "how is the platform doing" is a different job from "fix this business's
 * ledger", and mixing them in one list makes the destructive jobs sit one slip
 * away from the read-only screens.
 */
export const GROUPS = [
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

/**
 * The account, which is reachable from the topbar and the drawer footer rather
 * than from the section list — it is not one of the console's jobs.
 */
const ACCOUNT = { href: '/admin/perfil', label: 'A minha conta' } as const;

/** The entry the current route sits under, for the collapsed nav's label. */
export function currentEntry(pathname: string) {
  for (const group of GROUPS) {
    for (const item of group.items) {
      if (isCurrent(item.href, pathname)) return { group, item };
    }
  }
  if (isCurrent(ACCOUNT.href, pathname)) {
    return { group: { label: 'Conta' }, item: ACCOUNT };
  }
  return null;
}

function NavList({ onNavigate }: { onNavigate?: () => void }) {
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
              onClick={onNavigate}
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

export function AdminNav() {
  return <NavList />;
}

/**
 * The nav below the shell breakpoint.
 *
 * The strip this replaces put all ten destinations in one horizontal scroller
 * with the group labels hidden, so the only way to find "Reconciliação" was to
 * scroll a row of identical pills and read every one. A drawer keeps the
 * grouping the desktop nav has, and the trigger states where you currently are
 * rather than being an unlabelled icon.
 */
export function MobileNav({ account }: { account: string }) {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  const panelId = useId();
  const toggleRef = useRef<HTMLButtonElement>(null);
  const panelRef = useRef<HTMLDivElement>(null);

  const close = useCallback(() => setOpen(false), []);

  // Any navigation closes the drawer. Without this, tapping a destination
  // leaves the panel sitting over the page it just loaded.
  useEffect(() => {
    setOpen(false);
  }, [pathname]);

  useEffect(() => {
    if (!open) return;

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        setOpen(false);
        toggleRef.current?.focus();
        return;
      }

      // `aria-modal` tells a screen reader the rest of the page is inert, but
      // it does nothing for Tab — without this the focus ring walks straight
      // out of the drawer and onto the page it is covering.
      if (event.key !== 'Tab') return;

      const panel = panelRef.current;
      if (!panel) return;

      const focusable = panel.querySelectorAll<HTMLElement>(
        'a[href], button:not(:disabled)',
      );
      if (focusable.length === 0) return;

      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      const active = document.activeElement;

      if (event.shiftKey && (active === first || active === panel)) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && active === last) {
        event.preventDefault();
        first.focus();
      }
    };

    document.addEventListener('keydown', onKeyDown);
    // The page behind must not scroll under the drawer.
    const previous = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    // Focus the panel itself rather than the first link, so the drawer's
    // purpose is announced before its contents are read out.
    panelRef.current?.focus();

    return () => {
      document.removeEventListener('keydown', onKeyDown);
      document.body.style.overflow = previous;
    };
  }, [open]);

  const here = currentEntry(pathname);

  return (
    <div className="mobile-nav">
      <button
        ref={toggleRef}
        className="mobile-nav__toggle"
        type="button"
        aria-controls={panelId}
        aria-expanded={open}
        onClick={() => setOpen((value) => !value)}
      >
        <span className="mobile-nav__icon" aria-hidden>
          <span />
          <span />
          <span />
        </span>
        <span className="mobile-nav__where">
          {/* The group is dropped when it repeats the entry — "Clientes /
              Clientes" reads as a rendering fault rather than a location. */}
          {here && here.group.label !== here.item.label ? (
            <span className="mobile-nav__group">{here.group.label}</span>
          ) : null}
          <span className="mobile-nav__item">
            {here?.item.label ?? 'Secções'}
          </span>
        </span>
      </button>

      {open ? (
        <div
          className="mobile-nav__backdrop"
          onClick={close}
          // The backdrop is a convenience for pointer users; Escape and the
          // close button are the real exits, so it stays out of the tree.
          aria-hidden
        />
      ) : null}

      <div
        ref={panelRef}
        className={`mobile-nav__panel${open ? ' is-open' : ''}`}
        id={panelId}
        role="dialog"
        aria-modal="true"
        aria-label="Secções"
        tabIndex={-1}
        hidden={!open}
      >
        <div className="mobile-nav__head">
          <p className="mobile-nav__title">Secções</p>
          <button
            className="mobile-nav__close"
            type="button"
            onClick={() => {
              close();
              toggleRef.current?.focus();
            }}
          >
            <span aria-hidden>✕</span>
            <span className="sr-only">Fechar menu</span>
          </button>
        </div>

        <nav aria-label="Secções">
          <NavList onNavigate={close} />
        </nav>

        {/* The topbar drops the account at this width, so it is stated here
            rather than leaving no way to tell which login is in use — and it
            is the way to the profile, as it is on the topbar. */}
        <Link
          className="mobile-nav__account"
          href={ACCOUNT.href}
          onClick={close}
          aria-current={isCurrent(ACCOUNT.href, pathname) ? 'page' : undefined}
        >
          <span className="mobile-nav__account-label">A minha conta</span>
          <span className="mobile-nav__account-email">{account}</span>
        </Link>
      </div>
    </div>
  );
}
