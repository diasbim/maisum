import { Suspense } from 'react';
import Link from 'next/link';
import { notFound } from 'next/navigation';

import {
  fetchMyCustomer,
  fetchMyCustomerLedger,
  type MerchantSale,
} from '@/lib/merchant-api';
import { SaleStatus } from '../../links';
import {
  ledgerEntryLabel,
  lifecycleLabel,
  relationshipLabel,
  retentionLabel,
} from '@/lib/merchant-labels';
import {
  Badge,
  Card,
  DefinitionList,
  EmptyState,
  ErrorState,
  PageHeader,
  Panel,
  TableSkeleton,
  formatAmount,
  formatDateTime,
  load,
} from '../../../admin/ui';

// Deliberately static rather than a `generateMetadata` that names the
// customer: that would mean a second read of the same document on every open,
// and it would put a customer's name in the browser's history and tab title.
export const metadata = { title: 'Cliente | MaisUm' };
export const dynamic = 'force-dynamic';

export default async function MerchantCustomerPage({
  params,
}: {
  params: Promise<{ customerId: string }>;
}) {
  const { customerId } = await params;
  const result = await load(() => fetchMyCustomer(customerId));

  if (result.error !== null) {
    return (
      <>
        <PageHeader title="Cliente" />
        <Panel>
          <ErrorState message={result.error} />
        </Panel>
      </>
    );
  }

  // A customer id that belongs to somebody else's business never gets here:
  // the API answers 403 before it looks anything up, and that surfaces above.
  // This is the plain "no such customer" case.
  if (result.data === null) notFound();

  const customer = result.data;
  const visits = customer.sales;

  return (
    <>
      <PageHeader
        title={customer.name ?? customer.id}
        subtitle={customer.phone ?? 'Sem telefone registado'}
        action={
          <Link className="btn btn-outline" href="/negocio/clientes">
            ← Todos os clientes
          </Link>
        }
      />

      <Panel>
        <div className="split">
          <Card title="Fidelidade">
            <DefinitionList
              entries={[
                ['Pontos', customer.total_points.toLocaleString('pt-PT')],
                ['Visitas', String(customer.total_visits)],
                ['Total gasto', formatAmount(customer.total_spent, 'MZN')],
                ['Gasto médio', formatAmount(customer.average_spend, 'MZN')],
              ]}
            />
          </Card>

          <Card title="Relação">
            <DefinitionList
              entries={[
                [
                  'Estado',
                  <Badge
                    key="status"
                    label={relationshipLabel(
                      customer.relationship_status ?? 'ACTIVE',
                    )}
                    tone={customer.relationship_status ?? 'ACTIVE'}
                  />,
                ],
                [
                  'Fase',
                  <Badge
                    key="stage"
                    label={lifecycleLabel(customer.lifecycle_stage)}
                    tone={customer.lifecycle_stage}
                  />,
                ],
                [
                  'Retenção',
                  <Badge
                    key="retention"
                    label={retentionLabel(customer.retention_status)}
                    tone={customer.retention_status}
                  />,
                ],
                [
                  'Primeira visita',
                  customer.first_visit_at === null
                    ? 'Nunca'
                    : formatDateTime(customer.first_visit_at),
                ],
                [
                  'Última visita',
                  customer.last_visit_at === null
                    ? 'Nunca'
                    : formatDateTime(customer.last_visit_at),
                ],
                ['Registado em', formatDateTime(customer.created_at)],
              ]}
            />
          </Card>
        </div>
      </Panel>

      <Panel title="Visitas recentes">
        {visits.length === 0 ? (
          <EmptyState message="Ainda não há vendas registadas para este cliente." />
        ) : (
          <div className="card card--flush scroll-x">
            <table>
              <thead>
                <tr>
                  <th scope="col">Data</th>
                  <th className="num" scope="col">
                    Valor
                  </th>
                  <th className="num" scope="col">
                    Pontos
                  </th>
                  <th scope="col">Estado</th>
                </tr>
              </thead>
              <tbody>
                {visits.map((sale) => {
                  return (
                    <tr key={sale.id}>
                      <td>{formatDateTime(sale.created_at)}</td>
                      <td className="num">{formatAmount(sale.amount, 'MZN')}</td>
                      <td className="num">{sale.points ?? '—'}</td>
                      <td>
                        <SaleStatus sale={sale} />
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </Panel>

      <Panel title="Livro de pontos">
        <Suspense fallback={<TableSkeleton rows={4} />}>
          <LedgerPanel customerId={customerId} />
        </Suspense>
      </Panel>
    </>
  );
}

/**
 * Where the points came from and where they went.
 *
 * The console has shown a customer's ledger to internal staff for a while;
 * the business whose points they are could see only a running total and a
 * list of visits. A total nobody can take apart is a number a merchant cannot
 * argue with, which is the opposite of what a ledger is for.
 *
 * Its own Suspense boundary and its own request: this is a second read, and
 * the summary above should not wait for it.
 */
async function LedgerPanel({ customerId }: { customerId: string }) {
  const result = await load(() => fetchMyCustomerLedger(customerId));
  if (result.error !== null) return <ErrorState message={result.error} />;

  const entries = result.data;
  if (entries.length === 0) {
    return (
      <EmptyState message="Ainda não há movimentos de pontos para este cliente." />
    );
  }

  return (
    <div className="card card--flush scroll-x">
      <table>
        <thead>
          <tr>
            <th scope="col">Data</th>
            <th scope="col">Movimento</th>
            <th className="num" scope="col">
              Pontos
            </th>
            <th className="num" scope="col">
              Saldo
            </th>
          </tr>
        </thead>
        <tbody>
          {entries.map((entry) => (
            <tr key={entry.id}>
              <td>{formatDateTime(entry.occurred_at)}</td>
              <td>{ledgerEntryLabel(entry.entry_type) ?? '—'}</td>
              <td className="num">
                {entry.points_delta === null
                  ? '—'
                  : // The sign is the point of the column: a redemption that
                    // read as a plain number would look like an award.
                    `${entry.points_delta > 0 ? '+' : ''}${entry.points_delta.toLocaleString('pt-PT')}`}
              </td>
              <td className="num">
                {entry.balance_after === null
                  ? '—'
                  : entry.balance_after.toLocaleString('pt-PT')}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
