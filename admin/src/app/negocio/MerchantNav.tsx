'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useCallback, useEffect, useId, useRef, useState } from 'react';

/**
 * The business area's map.
 *
 * Two entries today. It is grouped anyway, and shaped like the console's nav,
 * because the plan adds clientes, catálogo, recompensas and equipa to the same
 * structure — a flat list now would have to be rebuilt then.
 */
const GROUPS = [
  {
    label: 'Negócio',
    items: [
      { href: '/negocio', label: 'Perfil' },
      { href: '/negocio/plano', label: 'Plano' },
    ],
  },
] as const;

function isCurrent(href: string, pathname: string): boolean {
  if (href === '/negocio') return pathname === '/negocio';
  return pathname === href || pathname.startsWith(`${href}/`);
}

function currentLabel(pathname: string): string {
  for (const group of GROUPS) {
    for (const item of group.items) {
      if (isCurrent(item.href, pathname)) return item.label;
    }
  }
  return 'Secções';
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

export function MerchantNav() {
  return <NavList />;
}

/** The same drawer the console uses, so the two areas behave identically. */
export function MerchantMobileNav({ business }: { business: string }) {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  const panelId = useId();
  const toggleRef = useRef<HTMLButtonElement>(null);
  const panelRef = useRef<HTMLDivElement>(null);

  const close = useCallback(() => setOpen(false), []);

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
    const previous = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    panelRef.current?.focus();

    return () => {
      document.removeEventListener('keydown', onKeyDown);
      document.body.style.overflow = previous;
    };
  }, [open]);

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
          <span className="mobile-nav__group">Negócio</span>
          <span className="mobile-nav__item">{currentLabel(pathname)}</span>
        </span>
      </button>

      {open ? (
        <div className="mobile-nav__backdrop" onClick={close} aria-hidden />
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

        <p className="mobile-nav__account">
          <span className="mobile-nav__account-label">Negócio</span>
          <span className="mobile-nav__account-email">{business}</span>
        </p>
      </div>
    </div>
  );
}
