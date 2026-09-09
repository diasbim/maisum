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
 * A customer id, as a way to get to the customer.
 *
 * These rows carry an id and no name — sales, appointments and risk scores
 * are all written against the id — and an id on its own is not something an
 * owner recognises. Linking it at least makes it one click from the name.
 */
export function CustomerLink({ id }: { id: string | null }) {
  if (!id) return <span className="muted">—</span>;
  return (
    <Link href={`/negocio/clientes/${encodeURIComponent(id)}`}>
      <code>{id.length > 12 ? `${id.slice(0, 12)}…` : id}</code>
    </Link>
  );
}
