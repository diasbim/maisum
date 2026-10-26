import { Suspense } from 'react';

import { fetchMyRewards, MERCHANT_PAGE_SIZE } from '@/lib/merchant-api';
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
  formatDateTime,
  load,
  parseOffset,
  parseSearch,
} from '../../admin/ui';
import { ResultCount, SearchForm, TruncationNotice } from '../records';

export const metadata = { title: 'Recompensas | MaisUm' };
export const dynamic = 'force-dynamic';

const FILTERS = [
  { value: '', label: 'Todas' },
  { value: 'ACTIVE', label: 'Ativas' },
  { value: 'INACTIVE', label: 'Inativas' },
];

async function RewardsTable({
  search,
  status,
  offset,
}: {
  search: string;
  status: string;
  offset: number;
}) {
  const result = await load(() =>
    fetchMyRewards({
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
            <ClearFilters href="/negocio/recompensas" label="Limpar filtros" />
          ) : undefined
        }
        message={
          filtered
            ? 'Nenhuma recompensa corresponde a esta procura.'
            : 'Ainda não há recompensas. Sem elas, os pontos que os clientes acumulam não têm onde ser trocados — crie a primeira na aplicação.'
        }
      />
    );
  }

  return (
    <>
      <TruncationNotice truncated={page.truncated} />
      <ResultCount total={page.total} singular="recompensa" plural="recompensas" />

      <div className="card card--flush scroll-x">
        <table>
          <thead>
            <tr>
              <th scope="col">Recompensa</th>
              <th className="num" scope="col">
                Pontos
              </th>
              <th scope="col">Estado</th>
              <th scope="col">Criada</th>
            </tr>
          </thead>
          <tbody>
            {page.items.map((reward) => (
              <tr key={reward.id}>
                <td>
                  {reward.name ?? reward.id}
                  {reward.description ? (
                    <p className="micro" style={{ marginTop: 4 }}>
                      {reward.description}
                    </p>
                  ) : null}
                </td>
                <td className="num">
                  {reward.points_required === null
                    ? '—'
                    : reward.points_required.toLocaleString('pt-PT')}
                </td>
                <td>
                  <Badge
                    label={reward.is_active === false ? 'Inativa' : 'Ativa'}
                    tone={reward.is_active === false ? 'INACTIVE' : 'ACTIVE'}
                  />
                </td>
                <td>{formatDateTime(reward.created_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <Pagination
        basePath="/negocio/recompensas"
        query={{ search: search || undefined, status: status || undefined }}
        limit={MERCHANT_PAGE_SIZE}
        offset={offset}
        hasMore={page.hasMore}
        returned={page.items.length}
      />
    </>
  );
}

export default async function MerchantRewardsPage({
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
        title="Recompensas"
        subtitle="O que os seus clientes podem trocar pelos pontos que acumulam."
      />

      <Panel>
        <SearchForm
          action="/negocio/recompensas"
          label="Procurar recompensas"
          placeholder="Nome da recompensa"
          value={search}
          keep={{ status: status || undefined }}
        />
        <ChipFilter
          basePath="/negocio/recompensas"
          param="status"
          current={status}
          options={FILTERS}
          keep={{ search: search || undefined }}
        />
      </Panel>

      <Panel>
        <Suspense
          key={`${search}|${status}|${offset}`}
          fallback={<TableSkeleton rows={5} />}
        >
          <RewardsTable search={search} status={status} offset={offset} />
        </Suspense>
      </Panel>
    </>
  );
}
