import Link from 'next/link';
import { Suspense } from 'react';

import {
  fetchMyAffiliateRewards,
  fetchMyAffiliates,
  MERCHANT_PAGE_SIZE,
} from '@/lib/merchant-api';
import { getMerchantPermissions } from '@/lib/merchant-session';
import {
  rewardStatusLabel,
  rewardStatusTone,
  rewardTypeLabel,
} from '@/lib/merchant-labels';
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
} from '../../../admin/ui';
import { ResultCount, TruncationNotice } from '../../records';
import {
  AFFILIATES_PATH,
  READ_ONLY_REASON_ID,
  ReadOnlyNotice,
  affiliateHref,
} from '../afiliados';
import { RewardDecision } from './RewardDecision';

export const metadata = { title: 'Recompensas de afiliados | MaisUm' };
export const dynamic = 'force-dynamic';

/**
 * The points this business owes the people who send customers to it.
 *
 * Opens on the pending ones because that is the only state that needs a
 * decision; the others are here so an owner can check what they already
 * decided without leaving the screen.
 *
 * The screen is online-only and says nothing about queues or retries: these
 * are decisions about money owed, taken at a desk, and the app is where the
 * counter's offline work happens. What it does not offer is paying — the API
 * has no such transition from the portal, and pretending otherwise would put
 * the ledger out of step with what was actually handed over.
 */

const REWARDS_PATH = `${AFFILIATES_PATH}/recompensas`;

const STATUS = [
  { value: 'PENDING', label: 'Pendentes' },
  { value: 'APPROVED', label: 'Aprovadas' },
  { value: 'PAID', label: 'Pagas' },
  { value: 'CANCELLED', label: 'Canceladas' },
  { value: 'ALL', label: 'Todas' },
];

async function RewardsTable({
  status,
  offset,
  canManage,
}: {
  status: string;
  offset: number;
  canManage: boolean;
}) {
  const [page, affiliates] = await Promise.all([
    load(() =>
      fetchMyAffiliateRewards({
        status: status === 'ALL' ? undefined : status,
        limit: MERCHANT_PAGE_SIZE,
        offset,
      }),
    ),
    // A reward carries an affiliate id and no name. The names come from one
    // extra read rather than one per row, and a failure costs the names only.
    load(() => fetchMyAffiliates({ limit: 200 })),
  ]);

  if (page.error !== null) return <ErrorState message={page.error} />;

  if (page.data.items.length === 0) {
    return (
      <EmptyState
        action={
          status === 'PENDING' ? undefined : (
            <ClearFilters href={REWARDS_PATH} label="Ver pendentes" />
          )
        }
        message={
          status === 'PENDING'
            ? 'Não há recompensas à espera de decisão.'
            : 'Nenhuma recompensa neste estado.'
        }
      />
    );
  }

  const nameById = new Map(
    (affiliates.error === null ? affiliates.data.items : []).map((affiliate) => [
      affiliate.id,
      affiliate.name,
    ]),
  );

  return (
    <>
      <TruncationNotice truncated={page.data.truncated} />
      <ResultCount
        total={page.data.total}
        singular="recompensa"
        plural="recompensas"
      />

      <div className="card card--flush scroll-x">
        <table>
          <thead>
            <tr>
              <th scope="col">Afiliado</th>
              <th scope="col">Motivo</th>
              <th className="num" scope="col">
                Pontos
              </th>
              <th scope="col">Criada</th>
              <th scope="col">Estado</th>
              <th scope="col">
                <span className="sr-only">Decisão</span>
              </th>
            </tr>
          </thead>
          <tbody>
            {page.data.items.map((reward) => {
              const name = nameById.get(reward.affiliate_id) ?? reward.affiliate_id;
              return (
                <tr key={reward.id}>
                  <td>
                    <Link href={affiliateHref(reward.affiliate_id)}>{name}</Link>
                  </td>
                  <td>{rewardTypeLabel(reward.type) ?? reward.type}</td>
                  <td className="num">{reward.value.toLocaleString('pt-PT')}</td>
                  <td>{formatDateTime(reward.created_at)}</td>
                  <td>
                    <Badge
                      label={rewardStatusLabel(reward.status)}
                      tone={rewardStatusTone(reward.status)}
                    />
                  </td>
                  <td>
                    {reward.status === 'PENDING' ? (
                      <RewardDecision
                        affiliateId={reward.affiliate_id}
                        affiliateName={name}
                        canManage={canManage}
                        points={reward.value}
                        reasonId={canManage ? undefined : READ_ONLY_REASON_ID}
                        rewardId={reward.id}
                      />
                    ) : (
                      <span className="muted">—</span>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <Pagination
        basePath={REWARDS_PATH}
        query={{ status }}
        limit={MERCHANT_PAGE_SIZE}
        offset={offset}
        hasMore={page.data.hasMore}
        returned={page.data.items.length}
      />
    </>
  );
}

export default async function MerchantAffiliateRewardsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  // No filter means the pending ones: this screen exists to be worked through,
  // not browsed.
  const status = (parseSearch(params.status) || 'PENDING').toUpperCase();
  const offset = parseOffset(params.offset);
  const permissions = await getMerchantPermissions();

  return (
    <>
      <PageHeader
        title="Recompensas de afiliados"
        subtitle="Pontos a entregar a quem indicou clientes que compraram."
        action={
          <Link className="btn btn-outline btn-sm" href={AFFILIATES_PATH}>
            ← Todos os afiliados
          </Link>
        }
      />

      <ReadOnlyNotice reason={permissions.reason} />

      <Panel>
        <ChipFilter
          basePath={REWARDS_PATH}
          param="status"
          current={status}
          options={STATUS}
        />
        <p className="micro">
          Aprovar confirma que os pontos são devidos. A entrega é feita por si,
          fora do portal.
        </p>
      </Panel>

      <Panel>
        <Suspense key={`${status}|${offset}`} fallback={<TableSkeleton rows={6} />}>
          <RewardsTable
            canManage={permissions.canManage}
            offset={offset}
            status={status}
          />
        </Suspense>
      </Panel>
    </>
  );
}
