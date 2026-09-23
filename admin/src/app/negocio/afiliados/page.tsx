import Link from 'next/link';
import { Suspense } from 'react';

import {
  fetchMyAffiliateMetrics,
  fetchMyAffiliateRewards,
  fetchMyAffiliates,
  MERCHANT_PAGE_SIZE,
} from '@/lib/merchant-api';
import { getMerchantPermissions, getMerchantSession } from '@/lib/merchant-session';
import { lastAffiliateActivityAt } from '@/lib/affiliate-form';
import {
  ChipFilter,
  ClearFilters,
  EmptyState,
  ErrorState,
  MetricsSkeleton,
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
import {
  AFFILIATES_PATH,
  AffiliateMetrics,
  AffiliateStanding,
  CodeBadge,
  CodeText,
  ReadOnlyNotice,
  ShareCode,
  affiliateHref,
  benefitText,
  maskedPhone,
} from './afiliados';

export const metadata = { title: 'Afiliados | MaisUm' };
export const dynamic = 'force-dynamic';

/**
 * Who brings customers to this business, and what that has been worth.
 *
 * The list and the numbers are two reads and two Suspense boundaries: the
 * metrics are computed over every event the business has and are the slower of
 * the two, and holding the names back until they arrive would be the wrong way
 * round — the names are what the owner came for.
 *
 * `status` here filters the link, which is the part the owner controls. A
 * suspension is a platform decision and still shows in the badge, so a
 * suspended affiliate cannot hide inside "Ativos".
 */

const STATUS = [
  { value: '', label: 'Todos' },
  { value: 'ACTIVE', label: 'Ativos' },
  { value: 'INACTIVE', label: 'Inativos' },
];

async function MetricsPanel() {
  const result = await load(() => fetchMyAffiliateMetrics());
  if (result.error !== null) return <ErrorState message={result.error} />;
  if (result.data === null) {
    return (
      <EmptyState message="Ainda não há números para mostrar. Aparecem assim que o primeiro código for usado." />
    );
  }
  return <AffiliateMetrics metrics={result.data} />;
}

async function AffiliatesTable({
  search,
  status,
  offset,
  canManage,
}: {
  search: string;
  status: string;
  offset: number;
  canManage: boolean;
}) {
  const [page, rewards, session] = await Promise.all([
    load(() =>
      fetchMyAffiliates({
        search: search || undefined,
        status: status || undefined,
        limit: MERCHANT_PAGE_SIZE,
        offset,
      }),
    ),
    // The pending count is a second read and is allowed to fail on its own: an
    // owner who opened this screen wants to know who their affiliates are, and
    // hiding all of them because one secondary count is missing would be a
    // worse answer than showing them with the column marked unavailable.
    load(() => fetchMyAffiliateRewards({ status: 'PENDING', limit: 200 })),
    load(() => getMerchantSession()),
  ]);

  if (page.error !== null) return <ErrorState message={page.error} />;

  const filtered = search !== '' || status !== '';
  if (page.data.items.length === 0) {
    return (
      <EmptyState
        action={
          filtered ? (
            <ClearFilters href={AFFILIATES_PATH} />
          ) : canManage ? (
            <Link className="btn btn-navy btn-sm" href={`${AFFILIATES_PATH}/novo`}>
              Adicionar afiliado
            </Link>
          ) : undefined
        }
        message={
          filtered
            ? 'Nenhum afiliado corresponde a esta procura.'
            : 'Ainda não há afiliados. Adicione o primeiro e partilhe o código dele por WhatsApp.'
        }
      />
    );
  }

  const pendingByAffiliate = new Map<string, number>();
  for (const reward of rewards.error === null ? rewards.data.items : []) {
    if (reward.status !== 'PENDING') continue;
    pendingByAffiliate.set(
      reward.affiliate_id,
      (pendingByAffiliate.get(reward.affiliate_id) ?? 0) + 1,
    );
  }
  const pendingCountsIncomplete =
    rewards.error !== null ||
    rewards.data.hasMore ||
    rewards.data.truncated;

  const businessName =
    session.error === null && session.data !== null
      ? (session.data.active.name ?? '')
      : '';

  return (
    <>
      <TruncationNotice
        truncated={
          page.data.truncated || (rewards.error === null && rewards.data.truncated)
        }
      />
      <ResultCount total={page.data.total} singular="afiliado" plural="afiliados" />
      {pendingCountsIncomplete ? (
        <p className="notice notice--warn" role="status">
          Não foi possível contar todas as recompensas pendentes. A coluna
          fica por saber.
        </p>
      ) : null}

      <div className="card card--flush scroll-x">
        <table>
          <thead>
            <tr>
              <th scope="col">Afiliado</th>
              <th scope="col">Telefone</th>
              <th scope="col">Código</th>
              <th scope="col">Benefício</th>
              <th className="num" scope="col">
                Indicações
              </th>
              <th className="num" scope="col">
                Por aprovar
              </th>
              <th scope="col">Última atividade</th>
              <th scope="col">Estado</th>
              <th scope="col">
                <span className="sr-only">Ações</span>
              </th>
            </tr>
          </thead>
          <tbody>
            {page.data.items.map((affiliate) => {
              const activity = lastAffiliateActivityAt(affiliate);
              return (
                <tr key={affiliate.id}>
                  <td>
                    <Link href={affiliateHref(affiliate.id)}>{affiliate.name}</Link>
                  </td>
                  <td>{maskedPhone(affiliate)}</td>
                  <td>
                    <CodeText code={affiliate.code} />{' '}
                    <CodeBadge code={affiliate.code} />
                  </td>
                  <td>{benefitText(affiliate.code)}</td>
                  <td className="num">
                    {(affiliate.code?.usage_count ?? 0).toLocaleString('pt-PT')}
                  </td>
                  <td className="num">
                    {pendingCountsIncomplete
                      ? '—'
                      : (pendingByAffiliate.get(affiliate.id) ?? 0).toLocaleString(
                          'pt-PT',
                        )}
                  </td>
                  <td>
                    {activity === null ? 'Sem atividade' : formatDateTime(activity)}
                  </td>
                  <td>
                    <AffiliateStanding affiliate={affiliate} />
                  </td>
                  <td>
                    <ShareCode affiliate={affiliate} businessName={businessName} />
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <Pagination
        basePath={AFFILIATES_PATH}
        query={{ search: search || undefined, status: status || undefined }}
        limit={MERCHANT_PAGE_SIZE}
        offset={offset}
        hasMore={page.data.hasMore}
        returned={page.data.items.length}
      />
    </>
  );
}

export default async function MerchantAffiliatesPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const search = parseSearch(params.search);
  const status = parseSearch(params.status).toUpperCase();
  const offset = parseOffset(params.offset);
  const permissions = await getMerchantPermissions();

  return (
    <>
      <PageHeader
        title="Afiliados"
        subtitle="Quem indica clientes ao seu negócio, com que código e quanto já rendeu."
        action={
          permissions.canManage ? (
            <Link className="btn btn-navy" href={`${AFFILIATES_PATH}/novo`}>
              Adicionar afiliado
            </Link>
          ) : undefined
        }
      />

      <ReadOnlyNotice reason={permissions.reason} />

      <Panel>
        <Suspense fallback={<MetricsSkeleton count={6} />}>
          <MetricsPanel />
        </Suspense>
      </Panel>

      <Panel>
        <SearchForm
          action={AFFILIATES_PATH}
          label="Procurar afiliados"
          placeholder="Nome, código ou últimos 4 dígitos"
          value={search}
          keep={{ status: status || undefined }}
        />
        <ChipFilter
          basePath={AFFILIATES_PATH}
          param="status"
          current={status}
          options={STATUS}
          keep={{ search: search || undefined }}
        />
        <p className="micro">
          <Link href={`${AFFILIATES_PATH}/recompensas`}>
            Recompensas por aprovar
          </Link>
          {' · '}
          <Link href={`${AFFILIATES_PATH}/indicacoes`}>
            Indicações registadas
          </Link>
        </p>
      </Panel>

      <Panel>
        <Suspense
          key={`${search}|${status}|${offset}`}
          fallback={<TableSkeleton rows={6} />}
        >
          <AffiliatesTable
            canManage={permissions.canManage}
            offset={offset}
            search={search}
            status={status}
          />
        </Suspense>
      </Panel>
    </>
  );
}
