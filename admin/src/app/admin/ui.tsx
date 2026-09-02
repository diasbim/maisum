import Link from 'next/link';

import { AdminApiError } from '@/lib/admin-api';
import { RetryButton } from './RetryButton';

/**
 * Shared presentation for the read surfaces, built on the design system tokens
 * in globals.css.
 *
 * Every panel renders one of three states — data, empty, or error. The Flutter
 * shell had these states but applied them unevenly; keeping them in one place
 * is what stops that drifting again.
 */

export type Loaded<T> =
  | { data: T; error: null }
  | { data: null; error: string };

export async function load<T>(loader: () => Promise<T>): Promise<Loaded<T>> {
  try {
    return { data: await loader(), error: null };
  } catch (caught) {
    if (caught instanceof AdminApiError) {
      return { data: null, error: caught.message };
    }
    return { data: null, error: 'Erro inesperado ao carregar.' };
  }
}

export function formatDateTime(millis: number | null): string {
  if (millis == null) return '—';
  return new Date(millis).toLocaleString('pt-PT', {
    dateStyle: 'short',
    timeStyle: 'short',
  });
}

/** Amounts are stored as whole MZN, not cents. */
export function formatAmount(amount: number | null, currency: string | null) {
  if (amount == null) return '—';
  return `${amount.toLocaleString('pt-PT')} ${currency ?? ''}`.trim();
}

export function PageHeader({
  title,
  subtitle,
  action,
}: {
  title: string;
  subtitle?: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="page-head">
      <div>
        <h1>{title}</h1>
        {subtitle ? <p>{subtitle}</p> : null}
      </div>
      {action}
    </div>
  );
}

export function Panel({
  title,
  error,
  children,
}: {
  title?: string;
  error?: string | null;
  children?: React.ReactNode;
}) {
  return (
    <section className="panel">
      {title ? <p className="section-label">{title}</p> : null}
      {error ? <ErrorState message={error} /> : children}
    </section>
  );
}

/**
 * A failed panel, with the way out attached.
 *
 * Every read surface funnels its failures through here rather than rendering
 * the message and stopping, so an operator is never left with a dead panel and
 * no indication that reloading is the only recourse. `role="alert"` because
 * these stream in on their own Suspense boundary, well after the page has
 * settled and the operator has looked away.
 */
export function ErrorState({
  message,
  action,
}: {
  message: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="state state--error" role="alert">
      <p className="state__message">
        <span aria-hidden>⚠</span> {message}
      </p>
      <div className="state__actions">{action ?? <RetryButton />}</div>
    </div>
  );
}

/**
 * An empty panel.
 *
 * `action` is what fills it, or clears the filter that emptied it — an empty
 * state that only explains leaves the operator to work out the way forward on
 * their own.
 */
export function EmptyState({
  message,
  action,
}: {
  message: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="state state--empty">
      <p className="state__message">{message}</p>
      {action ? <div className="state__actions">{action}</div> : null}
    </div>
  );
}

/** A link back to the unfiltered view, for empties caused by a filter. */
export function ClearFilters({
  href,
  label = 'Limpar filtros',
}: {
  href: string;
  label?: string;
}) {
  return (
    <Link className="btn btn-outline btn-sm" href={href}>
      {label}
    </Link>
  );
}

/**
 * Subscription status as a design-system badge.
 *
 * The tone carries meaning an operator scans for, so the mapping is explicit
 * rather than derived: anything unrecognized stays neutral instead of being
 * coloured by accident.
 */
export function Badge({ label }: { label: string | null }) {
  if (!label) return <span className="muted">—</span>;

  const tone = label.trim().toUpperCase();
  const variant =
    tone === 'ACTIVE'
      ? 'badge-green'
      : tone === 'TRIAL'
        ? 'badge-amber'
        : tone === 'PAST_DUE' || tone === 'CANCELLED' || tone === 'CANCELED'
          ? 'badge-red'
          : 'badge-navy';

  return <span className={`badge ${variant}`}>{label}</span>;
}

export function DefinitionList({
  entries,
}: {
  entries: Array<[string, React.ReactNode]>;
}) {
  return (
    <dl className="dl">
      {entries.map(([label, value]) => (
        <div className="dl__row" key={label}>
          <dt>{label}</dt>
          <dd>{value}</dd>
        </div>
      ))}
    </dl>
  );
}

/**
 * Offset pagination over the API's `paging` envelope.
 *
 * The admin endpoints have always accepted `limit` and `offset`; the Flutter
 * shell passed neither and silently showed only the first page.
 */
export function Pagination({
  basePath,
  query,
  limit,
  offset,
  hasMore,
  returned,
}: {
  basePath: string;
  query?: Record<string, string | undefined>;
  limit: number;
  offset: number;
  hasMore: boolean;
  returned: number;
}) {
  if (offset === 0 && !hasMore) return null;

  const href = (nextOffset: number) => {
    const params = new URLSearchParams();
    for (const [key, value] of Object.entries(query ?? {})) {
      if (value) params.set(key, value);
    }
    if (nextOffset > 0) params.set('offset', String(nextOffset));
    const qs = params.toString();
    return qs ? `${basePath}?${qs}` : basePath;
  };

  const from = returned === 0 ? 0 : offset + 1;
  const to = offset + returned;

  // A disabled end of the range is a real disabled button, not a faded span:
  // the span was neither focusable nor announced, and 0.4 opacity put the text
  // well under the contrast floor.
  return (
    <nav aria-label="Paginação" className="pager">
      <span className="micro">
        {from}–{to}
      </span>
      <span className="pager__controls">
        {offset > 0 ? (
          <Link
            className="btn btn-outline btn-sm"
            href={href(Math.max(0, offset - limit))}
          >
            ← Anteriores
          </Link>
        ) : (
          <button className="btn btn-outline btn-sm" disabled type="button">
            ← Anteriores
          </button>
        )}
        {hasMore ? (
          <Link className="btn btn-outline btn-sm" href={href(offset + limit)}>
            Seguintes →
          </Link>
        ) : (
          <button className="btn btn-outline btn-sm" disabled type="button">
            Seguintes →
          </button>
        )}
      </span>
    </nav>
  );
}

/** Parses an `offset` search param, rejecting anything not a whole number. */
export function parseOffset(raw: string | string[] | undefined): number {
  const value = Array.isArray(raw) ? raw[0] : raw;
  if (!value) return 0;
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
}

export function parseSearch(raw: string | string[] | undefined): string {
  const value = Array.isArray(raw) ? raw[0] : raw;
  return typeof value === 'string' ? value.trim() : '';
}

/* ------------------------------------------------------------------ streaming */

/**
 * Placeholders for the Suspense boundaries.
 *
 * Every panel that hits the API streams in on its own boundary, so a slow
 * merchant query no longer holds back the metrics beside it. The skeletons are
 * sized to the content they replace so the page does not jump when data lands.
 */
/**
 * Says that a fetch is in flight, for anyone who cannot see the bars move.
 *
 * The bars themselves stay `aria-hidden` — they are decoration — but hiding
 * them without putting anything in their place left screen reader users with
 * silence between navigation and content.
 */
function Loading({ label = 'A carregar…' }: { label?: string }) {
  return (
    <p className="sr-only" role="status">
      {label}
    </p>
  );
}

export function Skeleton({
  lines = 3,
  label,
}: {
  lines?: number;
  label?: string;
}) {
  return (
    <div>
      <Loading label={label} />
      <div aria-hidden>
        {Array.from({ length: lines }, (_, index) => (
          <div
            className="skeleton skeleton--line"
            key={index}
            style={{ width: `${100 - index * 9}%` }}
          />
        ))}
      </div>
    </div>
  );
}

export function TableSkeleton({
  rows = 6,
  label,
}: {
  rows?: number;
  label?: string;
}) {
  return (
    <div>
      <Loading label={label} />
      <div className="card" aria-hidden>
        {Array.from({ length: rows }, (_, index) => (
          <div className="skeleton skeleton--row" key={index} />
        ))}
      </div>
    </div>
  );
}

export function MetricsSkeleton({
  count = 10,
  label,
}: {
  count?: number;
  label?: string;
}) {
  return (
    <div>
      <Loading label={label} />
      <div className="grid" aria-hidden>
        {Array.from({ length: count }, (_, index) => (
          <div className="card" key={index}>
            <div className="skeleton skeleton--line" style={{ width: '70%' }} />
            <div
              className="skeleton skeleton--line"
              style={{ width: '40%', height: 26 }}
            />
          </div>
        ))}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ navigation */

export function Tabs({
  items,
  current,
}: {
  items: Array<{ href: string; label: string }>;
  current: string;
}) {
  return (
    <nav className="tabs" aria-label="Vistas">
      {items.map((item) => (
        <Link
          key={item.href}
          href={item.href}
          aria-current={item.href === current ? 'page' : undefined}
        >
          {item.label}
        </Link>
      ))}
    </nav>
  );
}

/**
 * Filter chips that are plain links.
 *
 * Filtering through the URL rather than client state means a filtered view can
 * be pasted into a chat, bookmarked, and reloaded — which is how operators
 * actually hand a problem to each other.
 */
export function ChipFilter({
  basePath,
  param,
  current,
  options,
  keep,
}: {
  basePath: string;
  param: string;
  current: string;
  options: Array<{ value: string; label: string }>;
  keep?: Record<string, string | undefined>;
}) {
  const href = (value: string) => {
    const params = new URLSearchParams();
    for (const [key, kept] of Object.entries(keep ?? {})) {
      if (kept) params.set(key, kept);
    }
    if (value) params.set(param, value);
    const qs = params.toString();
    return qs ? `${basePath}?${qs}` : basePath;
  };

  return (
    <div className="chip-row" role="group" aria-label="Filtros">
      {options.map((option) => (
        <Link
          className="chip"
          key={option.value || 'all'}
          href={href(option.value)}
          aria-current={option.value === current ? 'true' : undefined}
        >
          {option.label}
        </Link>
      ))}
    </div>
  );
}

/* ---------------------------------------------------------------- presentation */

export function Card({
  title,
  hint,
  children,
}: {
  title?: string;
  hint?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <div className="card">
      {title ? <p className="card__title">{title}</p> : null}
      {hint ? <p className="card__hint">{hint}</p> : null}
      {children}
    </div>
  );
}

export type VerdictTone = 'ok' | 'gap' | 'open' | 'na';

const VERDICT_MARK: Record<VerdictTone, string> = {
  ok: '✓',
  gap: '!',
  open: '?',
  na: '–',
};

/**
 * A verdict with a glyph as well as a colour.
 *
 * The reconciliation matrix is the one screen someone screenshots into a
 * conversation about what a plan promises, so it has to survive losing colour.
 */
export function Verdict({
  tone,
  label,
  title,
}: {
  tone: VerdictTone;
  label: string;
  title?: string;
}) {
  return (
    <span className={`verdict verdict--${tone}`} title={title}>
      <span className="verdict__mark" aria-hidden>
        {VERDICT_MARK[tone]}
      </span>
      {label}
    </span>
  );
}
