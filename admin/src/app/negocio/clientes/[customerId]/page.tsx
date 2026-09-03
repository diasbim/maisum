import Link from 'next/link';
import { notFound } from 'next/navigation';

import { fetchMyCustomer, type MerchantSale } from '@/lib/merchant-api';
import { lifecycleLabel, relationshipLabel, retentionLabel } from '@/lib/merchant-labels';
import {
  Badge,
  Card,
  DefinitionList,
  EmptyState,
  ErrorState,
  PageHeader,
  Panel,
  formatAmount,
  formatDateTime,
  load,
} from '../../../admin/ui';

// Deliberately static rather than a `generateMetadata` that names the
// customer: that would mean a second read of the same document on every open,
// and it would put a customer's name in the browser's history and tab title.
export const metadata = { title: 'Cliente | MaisUm' };
export const dynamic = 'force-dynamic';

/**
 * A cancelled sale is still a row in the collection.
 *
 * Printing it as an ordinary visit would overstate a customer's history, and
 * hiding it would make the points not add up. So it is shown, marked.
 */
function saleState(
  sale: MerchantSale,
): { label: string; tone: string } | null {
  const cancelled = (sale.cancellation_status ?? '').toUpperCase();
  if (cancelled === 'CANCELLED') {
    return { label: 'Cancelada', tone: 'CANCELLED' };
  }
  const confirmation = (sale.confirmation_status ?? '').toUpperCase();
  if (confirmation === 'PENDING') {
    return { label: 'Por confirmar', tone: 'PENDING' };
  }
  if (confirmation === 'FAILED') {
    return { label: 'Falhou', tone: 'FAILED' };
  }
  return null;
}

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
                  const state = saleState(sale);
                  return (
                    <tr key={sale.id}>
                      <td>{formatDateTime(sale.created_at)}</td>
                      <td className="num">{formatAmount(sale.amount, 'MZN')}</td>
                      <td className="num">{sale.points ?? '—'}</td>
                      <td>
                        {state === null ? (
                          <span className="muted">Concluída</span>
                        ) : (
                          <Badge label={state.label} tone={state.tone} />
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </Panel>
    </>
  );
}
