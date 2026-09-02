import { Suspense } from 'react';
import Link from 'next/link';

import { fetchMerchants } from '@/lib/admin-api';
import {
  Badge,
  ChipFilter,
  ClearFilters,
  EmptyState,
  ErrorState,
  formatDateTime,
  load,
  PageHeader,
  Pagination,
  Panel,
  parseOffset,
  parseSearch,
  TableSkeleton,
} from '../ui';
import { MerchantSearch } from './MerchantSearch';

export const metadata = { title: 'Negócios | Portal MaisUm' };
export const dynamic = 'force-dynamic';

const PAGE_SIZE = 25;

/**
 * The statuses `subscription_state.status` actually holds. Kept explicit rather
 * than derived from the current page: a filter list built from whatever
 * happened to load would lose "PAST_DUE" on the day nobody is past due, which
 * is exactly the day someone goes looking for it.
 */
const STATUSES = [
  { value: '', label: 'Todos' },
  { value: 'ACTIVE', label: 'Ativos' },
  { value: 'TRIAL', label: 'Em avaliação' },
  { value: 'PAST_DUE', label: 'Em atraso' },
  { value: 'CANCELLED', label: 'Cancelados' },
];

async function MerchantTable({
  search,
  status,
  offset,
}: {
  search: string;
  status: string;
  offset: number;
}) {
  const result = await load(() =>
    fetchMerchants({
      search: search || undefined,
      status: status || undefined,
      limit: PAGE_SIZE,
      offset,
    }),
  );

  if (result.error !== null) return <ErrorState message={result.error} />;

  if (result.data.items.length === 0) {
    const filtered = Boolean(search || status);
    return (
      <EmptyState
        action={filtered ? <ClearFilters href="/admin/merchants" /> : undefined}
        message={
          filtered
            ? 'Nenhum negócio corresponde a estes filtros.'
            : 'Ainda não há negócios registados na plataforma.'
        }
      />
    );
  }

  return (
    <>
      <div className="card card--flush scroll-x">
        <table>
          <thead>
            <tr>
              <th scope="col">Negócio</th>
              <th scope="col">Telefone</th>
              <th scope="col">Plano</th>
              <th scope="col">Subscrição</th>
              <th scope="col">Equipa</th>
              <th scope="col">Atualizado</th>
            </tr>
          </thead>
          <tbody>
            {result.data.items.map((merchant) => (
              <tr key={merchant.id}>
                <td>
                  <Link
                    href={`/admin/merchants/${encodeURIComponent(merchant.id)}`}
                  >
                    {merchant.name || merchant.id}
                  </Link>
                  <div style={{ color: 'var(--g500)', fontSize: '0.75rem' }}>
                    {merchant.id}
                  </div>
                </td>
                <td>{merchant.phone ?? '—'}</td>
                <td>{merchant.plan_name ?? merchant.plan_code ?? '—'}</td>
                <td>
                  <Badge label={merchant.subscription_status} />
                </td>
                <td>
                  {merchant.active_staff_count}/{merchant.staff_count}
                </td>
                <td>{formatDateTime(merchant.last_operational_update_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <Pagination
        basePath="/admin/merchants"
        query={{ search: search || undefined, status: status || undefined }}
        limit={PAGE_SIZE}
        offset={offset}
        hasMore={result.data.paging?.has_more ?? false}
        returned={result.data.items.length}
      />
    </>
  );
}

export default async function MerchantsPage({
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
        title="Negócios"
        subtitle="Diretório de negócios registados."
        action={<MerchantSearch />}
      />

      <div className="toolbar">
        <ChipFilter
          basePath="/admin/merchants"
          param="status"
          current={status}
          options={STATUSES}
          keep={{ search: search || undefined }}
        />
      </div>

      <Panel>
        {/* Keyed on the filters so changing them shows the skeleton again
            instead of leaving the previous page's rows on screen while the new
            ones load. */}
        <Suspense
          key={`${search}|${status}|${offset}`}
          fallback={<TableSkeleton rows={8} />}
        >
          <MerchantTable search={search} status={status} offset={offset} />
        </Suspense>
      </Panel>
    </>
  );
}
