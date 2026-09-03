import { Suspense } from 'react';

import {
  fetchMyTeam,
  MERCHANT_PAGE_SIZE,
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
  formatDateTime,
  load,
  parseOffset,
  parseSearch,
} from '../../admin/ui';
import { staffRoleLabel, staffStatusLabel } from '../labels';
import { ResultCount, SearchForm, TruncationNotice } from '../records';

export const metadata = { title: 'Equipa | MaisUm' };
export const dynamic = 'force-dynamic';

const FILTERS = [
  { value: '', label: 'Todos' },
  { value: 'ACTIVE', label: 'Ativos' },
  { value: 'INACTIVE', label: 'Inativos' },
];

async function TeamTable({
  search,
  status,
  offset,
}: {
  search: string;
  status: string;
  offset: number;
}) {
  const result = await load(() =>
    fetchMyTeam({
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
            <ClearFilters href="/negocio/equipa" label="Limpar filtros" />
          ) : undefined
        }
        message={
          filtered
            ? 'Ninguém corresponde a esta procura.'
            : 'Ainda não há ninguém na equipa além de si.'
        }
      />
    );
  }

  return (
    <>
      <TruncationNotice truncated={page.truncated} />
      <ResultCount total={page.total} singular="membro" plural="membros" />

      <div className="card card--flush scroll-x">
        <table>
          <thead>
            <tr>
              <th scope="col">Telefone</th>
              <th scope="col">Função</th>
              <th scope="col">Estado</th>
              <th scope="col">Última entrada</th>
              <th scope="col">Na equipa desde</th>
            </tr>
          </thead>
          <tbody>
            {page.items.map((member) => (
              <tr key={member.id}>
                <td>{member.phone ?? member.id}</td>
                <td>{staffRoleLabel(member.role) ?? '—'}</td>
                <td>
                  <Badge
                    label={staffStatusLabel(member.status ?? 'ACTIVE')}
                    tone={member.status ?? 'ACTIVE'}
                  />
                </td>
                <td>
                  {member.last_login_at === null
                    ? 'Nunca'
                    : formatDateTime(member.last_login_at)}
                </td>
                <td>{formatDateTime(member.created_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <Pagination
        basePath="/negocio/equipa"
        query={{ search: search || undefined, status: status || undefined }}
        limit={MERCHANT_PAGE_SIZE}
        offset={offset}
        hasMore={page.hasMore}
        returned={page.items.length}
      />
    </>
  );
}

export default async function MerchantTeamPage({
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
        title="Equipa"
        subtitle="Quem atende no seu negócio e quando entrou pela última vez."
      />

      <Panel>
        <SearchForm
          action="/negocio/equipa"
          label="Procurar na equipa"
          placeholder="Telefone"
          value={search}
          keep={{ status: status || undefined }}
        />
        <ChipFilter
          basePath="/negocio/equipa"
          param="status"
          current={status}
          options={FILTERS}
          keep={{ search: search || undefined }}
        />
      </Panel>

      <Panel>
        <Suspense
          key={`${search}|${status}|${offset}`}
          fallback={<TableSkeleton rows={4} />}
        >
          <TeamTable search={search} status={status} offset={offset} />
        </Suspense>
      </Panel>

      <p className="micro">
        Adicionar ou remover pessoas continua a fazer-se na aplicação. Esta
        página mostra a equipa, não a altera.
      </p>
    </>
  );
}
