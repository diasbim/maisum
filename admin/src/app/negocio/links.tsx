import Link from 'next/link';

import type { MerchantSale } from '@/lib/merchant-api';
import { Badge } from '../admin/ui';

/**
 * The pieces more than one business screen needs.
 *
 * `saleState` used to live inside the customer page, which was right while
 * the customer page was the only place a sale appeared. The sales list shows
 * the same rows, and two copies of "what counts as cancelled" is exactly the
 * kind of pair that drifts.
 */

/**
 * A cancelled sale is still a row in the collection.
 *
 * Printing it as an ordinary visit would overstate a customer's history, and
 * hiding it would make the points not add up. So it is shown, marked.
 */
export function saleState(
  sale: Pick<MerchantSale, 'cancellation_status' | 'confirmation_status'>,
): { label: string; tone: string } | null {
  const cancelled = (sale.cancellation_status ?? '').toUpperCase();
  if (cancelled === 'CANCELLED') {
    return { label: 'Cancelada', tone: 'CANCELLED' };
  }
  const confirmation = (sale.confirmation_status ?? '').toUpperCase();
  if (confirmation === 'PENDING') {
    return { label: 'Por confirmar', tone: 'PENDING' };
  }
  if (confirmation === 'FAILED' || confirmation === 'REJECTED') {
    return { label: 'Falhou', tone: 'FAILED' };
  }
  return null;
}

export function SaleStatus({
  sale,
}: {
  sale: Pick<MerchantSale, 'cancellation_status' | 'confirmation_status'>;
}) {
  const state = saleState(sale);
  if (state === null) return <span className="muted">Concluída</span>;
  return <Badge label={state.label} tone={state.tone} />;
}

/**
 * A customer, by the name their owner knows them by.
 *
 * The rows behind these screens are written against the customer id, because
 * that is what the app stores. Printing the id was a real cost: the retention
 * board exists to say who to call and it said `c3`. The API now joins the name
 * on the way out, so the name is what shows and the id stays as the link.
 *
 * A row whose customer was deleted, or whose name was never filled in, still
 * has to lead somewhere — so the id remains the fallback, set in monospace to
 * say plainly that it is an identifier and not somebody's name.
 */
export function CustomerLink({
  id,
  name = null,
}: {
  id: string | null;
  name?: string | null;
}) {
  if (!id) return <span className="muted">—</span>;

  const href = `/negocio/clientes/${encodeURIComponent(id)}`;
  if (name !== null && name.trim() !== '') {
    return <Link href={href}>{name}</Link>;
  }

  return (
    <Link href={href}>
      <code>{id.length > 12 ? `${id.slice(0, 12)}…` : id}</code>
    </Link>
  );
}
