'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useCallback, useEffect, useId, useRef, useState } from 'react';

/**
 * The business area's map.
 *
 * Grouped by the question being asked rather than by where the data lives:
 * "Operação" is what happens day to day and is where an owner spends their
 * time, so it leads; "Negócio" is the account itself, visited rarely.
 */
const GROUPS = [
  {
    label: 'Operação',
    items: [
      { href: '/negocio', label: 'Painel' },
      { href: '/negocio/vendas', label: 'Vendas' },
      { href: '/negocio/clientes', label: 'Clientes' },
      { href: '/negocio/marcacoes', label: 'Marcações' },
    ],
  },
  {
    label: 'Fidelidade',
    items: [
      { href: '/negocio/recompensas', label: 'Recompensas' },
      { href: '/negocio/resgates', label: 'Resgates' },
      { href: '/negocio/bonus', label: 'Bónus de retorno' },
      // Referrals live beside the other ways points are earned and spent: an
      // affiliate is paid in points, and the code a customer says at the
      // counter is a loyalty instrument, not a marketing campaign.
      { href: '/negocio/afiliados', label: 'Afiliados' },
    ],
  },
  {
    label: 'Retenção',
    items: [
      { href: '/negocio/retencao', label: 'Clientes em risco' },
      { href: '/negocio/tarefas', label: 'Tarefas' },
      { href: '/negocio/visitas', label: 'Relatórios de visita' },
      { href: '/negocio/inqueritos', label: 'Inquéritos' },
      { href: '/negocio/inqueritos/respostas', label: 'Respostas' },
    ],
  },
  {
    label: 'Negócio',
    items: [
      { href: '/negocio/catalogo', label: 'Catálogo' },
      { href: '/negocio/equipa', label: 'Equipa' },
      { href: '/negocio/perfil', label: 'Perfil' },
      { href: '/negocio/plano', label: 'Plano' },
    ],
  },
] as const;

/** Every href in the map, longest first. */
const HREFS = GROUPS.flatMap((group) => group.items.map((item) => item.href))
  .slice()
  .sort((a, b) => b.length - a.length);

/**
 * Which entry the current path belongs to.
 *
 * A prefix match alone lights up two entries once one item sits under another
 * — `/negocio/inqueritos/respostas` is a prefix match for Inquéritos as well
 * as an exact match for Respostas — and a menu that says you are in two places
 * says nothing. The longest matching href wins, which is always the most
 * specific one.
 */
function isCurrent(href: string, pathname: string): boolean {
  if (href === '/negocio') return pathname === '/negocio';
  const matches = (candidate: string) =>
    candidate !== '/negocio' &&
    (pathname === candidate || pathname.startsWith(`${candidate}/`));
  return HREFS.find(matches) === href;
}

/**
 * Where the drawer trigger says you are.
 *
 * Both halves, because with two groups the section alone is ambiguous: the
 * group is the part that says whether you are looking at the day's work or at
 * the account.
 */
function currentWhere(pathname: string): { group: string | null; item: string } {
  for (const group of GROUPS) {
    for (const item of group.items) {
      if (isCurrent(item.href, pathname)) {
        return { group: group.label, item: item.label };
      }
    }
  }
  return { group: null, item: 'Secções' };
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
  const where = currentWhere(pathname);
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
          {where.group ? (
            <span className="mobile-nav__group">{where.group}</span>
          ) : null}
          <span className="mobile-nav__item">{where.item}</span>
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
