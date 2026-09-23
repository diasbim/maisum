import Link from 'next/link';

import { fetchCustomerLedger } from '@/lib/admin-api';
import {
  Badge,
  Card,
  EmptyState,
  ErrorState,
  formatDateTime,
  load,
  PageHeader,
  Panel,
  parseSearch,
} from '../../ui';

export const metadata = { title: 'Livro de pontos | Portal MaisUm' };
export const dynamic = 'force-dynamic';

/**
 * One customer's points ledger at one business.
 *
 * This is the screen that was missing when a customer disputes a balance. The
 * reconcile job could already correct drift, but nothing could show what the
 * entries say — so the only way to answer "why do I have 40 points" was to
 * trust the number and hope.
 */
export default async function CustomerLedgerPage({
  params,
  searchParams,
}: {
  params: Promise<{ customerId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { customerId } = await params;
  const query = await searchParams;
  const merchantId = parseSearch(query.merchant_id);
  const businessCustomerId = parseSearch(query.customer_id);

  if (!merchantId) {
    return (
      <>
        <PageHeader title="Livro de pontos" />
        <Panel>
          <EmptyState message="Indique o negócio. O livro é uma subcoleção do negócio, por isso não existe uma vista global." />
        </Panel>
      </>
    );
  }

  const result = await load(() =>
    fetchCustomerLedger({
      canonicalCustomerId: customerId,
      merchantId,
      businessCustomerId: businessCustomerId || undefined,
    }),
  );

  return (
    <>
      <PageHeader
        title="Livro de pontos"
        subtitle={`${merchantId}${businessCustomerId ? ` · ${businessCustomerId}` : ''}`}
        action={
          <Link className="btn btn-outline btn-sm" href="/admin/customers">
            ← Procurar cliente
          </Link>
        }
      />

      <Panel>
        {result.error !== null ? (
          <ErrorState message={result.error} />
        ) : result.data === null || result.data.entries.length === 0 ? (
          <EmptyState message="Sem entradas no livro para este cliente neste negócio." />
        ) : (
          <>
            <div className="grid" style={{ marginBottom: 18 }}>
              <Card>
                <p className="metric-label">Entradas</p>
                <p className="metric-value">{result.data.entry_count}</p>
              </Card>
              <Card>
                <p className="metric-label">Saldo pela soma do livro</p>
                <p className="metric-value">{result.data.net_points}</p>
              </Card>
            </div>

            <div className="card card--flush scroll-x">
              <table>
                <thead>
                  <tr>
                    <th scope="col">Quando</th>
                    <th scope="col">Tipo</th>
                    <th scope="col">Origem</th>
                    <th style={{ textAlign: 'right' }}>Pontos</th>
                    <th style={{ textAlign: 'right' }}>Saldo</th>
                    <th style={{ textAlign: 'right' }}>Valor</th>
                  </tr>
                </thead>
                <tbody>
                  {result.data.entries.map((entry) => (
                    <tr key={entry.id}>
                      <td style={{ whiteSpace: 'nowrap' }}>
                        {formatDateTime(entry.occurred_at)}
                      </td>
                      <td>
                        <Badge label={entry.entry_type} />
                        {entry.reversal_of_entry_id ? (
                          <div className="micro">
                            estorna {entry.reversal_of_entry_id}
                            {entry.reversal_reason
                              ? ` · ${entry.reversal_reason}`
                              : ''}
                          </div>
                        ) : null}
                      </td>
                      <td>
                        {entry.source_type}
                        <div className="micro">{entry.source_id}</div>
                      </td>
                      <td
                        style={{
                          textAlign: 'right',
                          fontWeight: 700,
                          // Sign carries the meaning here, but colour makes a
                          // redemption findable in a long list at a glance.
                          color:
                            entry.points_delta < 0
                              ? 'var(--red)'
                              : 'var(--green)',
                        }}
                      >
                        {entry.points_delta > 0 ? '+' : ''}
                        {entry.points_delta}
                      </td>
                      <td style={{ textAlign: 'right' }}>
                        {entry.balance_after}
                      </td>
                      <td style={{ textAlign: 'right' }}>
                        {entry.amount_mzn ? `${entry.amount_mzn} MZN` : '—'}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <p className="micro" style={{ marginTop: 12 }}>
              O saldo acima é a soma das entradas. Se não bater com o total
              guardado no cliente, é isso que a reconciliação em{' '}
              <Link href="/admin/operations">Operações</Link> corrige.
            </p>
          </>
        )}
      </Panel>
    </>
  );
}
