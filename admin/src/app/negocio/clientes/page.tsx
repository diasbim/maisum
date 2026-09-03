import Link from 'next/link';
import { Suspense } from 'react';

import {
  fetchMyCustomers,
  MERCHANT_PAGE_SIZE,
  type MerchantCustomer,
} from '@/lib/merchant-api';
import {
  Badge,
  ChipFilter,
  ClearFilters,
  EmptyState,
  ErrorState,
  PageHeader,
  Pagination,
  Panel,
  TableSkeleton,
  formatAmount,
  formatDateTime,
  load,
  parseOffset,
  parseSearch,
} from '../../admin/ui';
import { relationshipLabel } from '../labels';
import { ResultCount, SearchForm, TruncationNotice } from '../records';

export const metadata = { title: 'Clientes | MaisUm' };
export const dynamic = 'force-dynamic';

const STATUS = [
  { value: '', label: 'Todos' },
  { value: 'ACTIVE', label: 'Ativos' },
  { value: 'BLOCKED', label: 'Bloqueados' },
  { value: 'ARCHIVED', label: 'Arquivados' },
];

/** "Nunca" reads better than a dash for a customer who has not been in yet. */
function lastVisit(customer: MerchantCustomer): string {
  return customer.last_visit_at === null
    ? 'Nunca'
    : formatDateTime(customer.last_visit_at);
}

async function CustomersTable({
  search,
  status,
  offset,
}: {
  search: string;
  status: string;
  offset: number;
}) {
  const result = await load(() =>
    fetchMyCustomers({
      search: search || undefined,
      status: status || undefined,
      limit: MERCHANT_PAGE_SIZE,
      offset,
    }),
  );
  if (result.error !== null) return <ErrorState message={result.error} />;

  const page = result.data;
  const filtered = search !== '' || status !== '';

  if (page.items.length === 0) {
    return (
      <EmptyState
        action={
          filtered ? (
            <ClearFilters href="/negocio/clientes" label="Limpar filtros" />
          ) : undefined
        }
        message={
          filtered
            ? 'Nenhum cliente corresponde a esta procura.'
            : 'Ainda não há clientes registados. Aparecem aqui assim que registar o primeiro na aplicação.'
        }
      />
    );
  }

  return (
    <>
      <TruncationNotice truncated={page.truncated} />
      <ResultCount total={page.total} singular="cliente" plural="clientes" />

      <div className="card card--flush scroll-x">
        <table>
          <thead>
            <tr>
              <th scope="col">Cliente</th>
              <th scope="col">Telefone</th>
              <th className="num" scope="col">
                Pontos
              </th>
              <th className="num" scope="col">
                Visitas
              </th>
              <th className="num" scope="col">
                Total gasto
              </th>
              <th scope="col">Última visita</th>
              <th scope="col">Estado</th>
            </tr>
          </thead>
          <tbody>
            {page.items.map((customer) => (
              <tr key={customer.id}>
                <td>
                  <Link
                    href={`/negocio/clientes/${encodeURIComponent(customer.id)}`}
                  >
                    {customer.name ?? customer.id}
                  </Link>
                </td>
                <td>{customer.phone ?? '—'}</td>
                <td className="num">
                  {customer.total_points.toLocaleString('pt-PT')}
                </td>
                <td className="num">{customer.total_visits}</td>
                <td className="num">
                  {formatAmount(customer.total_spent, 'MZN')}
                </td>
                <td>{lastVisit(customer)}</td>
                <td>
                  <Badge
                    label={relationshipLabel(
                      customer.relationship_status ?? 'ACTIVE',
                    )}
                    tone={customer.relationship_status ?? 'ACTIVE'}
                  />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <Pagination
        basePath="/negocio/clientes"
        query={{ search: search || undefined, status: status || undefined }}
        limit={MERCHANT_PAGE_SIZE}
        offset={offset}
        hasMore={page.hasMore}
        returned={page.items.length}
      />
    </>
  );
}

/**
 * The business's own customer list.
 *
 * The console has no screen like this and should not: internal staff reach one
 * customer at a time, by phone. The business that serves them is the one party
 * the rules have always let read the whole list, and the till already holds it
 * offline — this is the same data on a bigger screen.
 */
export default async function MerchantCustomersPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const search = parseSearch(params.search);
  const status = parseSearch(params.status).toUpperCase();
  const offset = parseOffset(params.offset);

  return (
    <>
      <PageHeader
        title="Clientes"
        subtitle="Quem passa pelo seu negócio, e quando esteve cá pela última vez."
      />

      <Panel>
        <SearchForm
          action="/negocio/clientes"
          label="Procurar clientes"
          placeholder="Nome ou telefone"
          value={search}
          keep={{ status: status || undefined }}
        />
        <ChipFilter
          basePath="/negocio/clientes"
          param="status"
          current={status}
          options={STATUS}
          keep={{ search: search || undefined }}
        />
      </Panel>

      <Panel>
        <Suspense
          key={`${search}|${status}|${offset}`}
          fallback={<TableSkeleton rows={6} />}
        >
          <CustomersTable search={search} status={status} offset={offset} />
        </Suspense>
      </Panel>
    </>
  );
}
