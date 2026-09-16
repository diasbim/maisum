import Link from 'next/link';
import { Suspense } from 'react';

import {
  fetchMerchantAffiliateMetrics,
  fetchMerchantAffiliateRewards,
  fetchMerchantAffiliates,
} from '@/lib/admin-api';
import {
  affiliateCodeAvailability,
  affiliateCodeAvailabilityLabel,
  affiliateCodeAvailabilityTone,
  affiliateStanding,
  conversionRateText,
  describeBenefit,
  maskAffiliatePhone,
} from '@/lib/affiliate-form';
import { MERCHANT_PAGE_SIZE } from '@/lib/merchant-list';
import {
  affiliateStatusLabel,
  affiliateStatusTone,
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
  MetricsSkeleton,
  Pagination,
  Panel,
  TableSkeleton,
  formatDateTime,
  load,
  parseOffset,
  parseSearch,
} from '../../../ui';

export const metadata = { title: 'Afiliados do negócio | Portal MaisUm' };
export const dynamic = 'force-dynamic';

/**
 * One business's referral programme, as internal staff see it.
 *
 * Read-only, and that is the point: what a code is worth and which rewards are
 * owed are the owner's decisions, taken in `/negocio/afiliados`. This is the
 * view a support call needs — is the programme running, is anything stuck
 * pending, which code did the customer mean — without anybody borrowing the
 * owner's session or touching their data.
 *
 * It reads `/admin/merchants/:merchantId/*`, so the business is named in the
 * path rather than resolved from a token. That is exactly the difference
 * between the two halves of the portal, and the reason these endpoints are
 * separate from the merchant ones.
 */

const STATUSES = [
  { value: '', label: 'Todos' },
  { value: 'ACTIVE', label: 'Ligados' },
  { value: 'INACTIVE', label: 'Desligados' },
];

async function MetricsPanel({ merchantId }: { merchantId: string }) {
  const result = await load(() => fetchMerchantAffiliateMetrics(merchantId));
  if (result.error !== null) return <ErrorState message={result.error} />;
  if (result.data === null) {
    return <EmptyState message="Este negócio ainda não tem atividade de afiliados." />;
  }

  const metrics = result.data;
  const number = (value: number) => value.toLocaleString('pt-PT');
  const cards: Array<[string, string]> = [
    ['Códigos validados', number(metrics.unique_validation_attempts)],
    ['Indicações confirmadas', number(metrics.confirmed_attributions)],
    ['Indicações recusadas', number(metrics.rejected_attributions)],
    ['Taxa de conversão', conversionRateText(metrics)],
    ['Pontos por aprovar', number(metrics.pending_reward_points)],
    ['Pontos aprovados', number(metrics.approved_reward_points)],
  ];

  return (
    <>
      <div className="grid">
        {cards.map(([label, value]) => (
          <div className="card" key={label}>
            <p className="metric-label">{label}</p>
            <p className="metric-value">{value}</p>
          </div>
        ))}
      </div>
      <p className="micro" role="status">
        Última atividade:{' '}
        {metrics.last_activity_at === null
          ? 'sem atividade'
          : formatDateTime(metrics.last_activity_at)}
        {metrics.truncated
          ? ' · calculado sobre uma parte dos registos.'
          : ''}
      </p>
    </>
  );
}

async function AffiliatesPanel({
  merchantId,
  search,
  status,
  offset,
  basePath,
}: {
  merchantId: string;
  search: string;
  status: string;
  offset: number;
  basePath: string;
}) {
  const result = await load(() =>
    fetchMerchantAffiliates(merchantId, {
      search: search || undefined,
      status: status || undefined,
      limit: MERCHANT_PAGE_SIZE,
      offset,
    }),
  );
  if (result.error !== null) return <ErrorState message={result.error} />;

  if (result.data.items.length === 0) {
    const filtered = Boolean(search || status);
    return (
      <EmptyState
        action={filtered ? <ClearFilters href={basePath} /> : undefined}
        message={
          filtered
            ? 'Nenhum afiliado corresponde a estes filtros.'
            : 'Este negócio ainda não tem afiliados.'
        }
      />
    );
  }

  return (
    <>
      {result.data.truncated ? (
        <p className="notice notice--warn" role="status">
          A leitura atingiu o limite. Os totais estão incompletos; use a procura.
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
                Utilizações
              </th>
              <th scope="col">Código ativo</th>
              <th scope="col">Estado</th>
            </tr>
          </thead>
          <tbody>
            {result.data.items.map((affiliate) => {
              const standing = affiliateStanding(affiliate);
              const codeAvailability =
                affiliate.code === null
                  ? null
                  : affiliateCodeAvailability(affiliate.code);
              return (
                <tr key={affiliate.id}>
                  <td>
                    <Link
                      href={`/admin/afiliados/${encodeURIComponent(affiliate.id)}`}
                    >
                      {affiliate.name || affiliate.id}
                    </Link>
                  </td>
                  <td>
                    {maskAffiliatePhone(affiliate.phone, affiliate.phone_last4)}
                  </td>
                  <td>
                    {affiliate.code === null ? (
                      <span className="muted">—</span>
                    ) : (
                      <code className="inline">{affiliate.code.code}</code>
                    )}
                  </td>
                  <td>
                    {affiliate.code === null
                      ? '—'
                      : (describeBenefit(
                          affiliate.code.benefit_type,
                          affiliate.code.benefit_value,
                        ) ?? affiliate.code.benefit_type)}
                  </td>
                  <td className="num">
                    {(affiliate.code?.usage_count ?? 0).toLocaleString('pt-PT')}
                  </td>
                  <td>
                    {codeAvailability === null ? (
                      <span className="muted">—</span>
                    ) : (
                      <Badge
                        label={affiliateCodeAvailabilityLabel(codeAvailability)}
                        tone={affiliateCodeAvailabilityTone(codeAvailability)}
                      />
                    )}
                  </td>
                  <td>
                    <Badge
                      label={affiliateStatusLabel(standing)}
                      tone={affiliateStatusTone(standing)}
                    />
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <Pagination
        basePath={basePath}
        query={{ search: search || undefined, status: status || undefined }}
        limit={MERCHANT_PAGE_SIZE}
        offset={offset}
        hasMore={result.data.hasMore}
        returned={result.data.items.length}
      />
    </>
  );
}

async function RewardsPanel({ merchantId }: { merchantId: string }) {
  const result = await load(() =>
    fetchMerchantAffiliateRewards(merchantId, { status: 'PENDING', limit: 25 }),
  );
  if (result.error !== null) return <ErrorState message={result.error} />;

  if (result.data.items.length === 0) {
    return <EmptyState message="Não há recompensas pendentes neste negócio." />;
  }

  return (
    <>
      <p className="micro">
        Aprovar ou cancelar é decisão do responsável do negócio, no portal dele.
      </p>
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
            </tr>
          </thead>
          <tbody>
            {result.data.items.map((reward) => (
              <tr key={reward.id}>
                <td>
                  <Link
                    href={`/admin/afiliados/${encodeURIComponent(reward.affiliate_id)}`}
                  >
                    <code className="inline">{reward.affiliate_id}</code>
                  </Link>
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
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}

export default async function AdminMerchantAffiliatesPage({
  params,
  searchParams,
}: {
  params: Promise<{ merchantId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { merchantId } = await params;
  const query = await searchParams;
  const search = parseSearch(query.search);
  const status = parseSearch(query.status).toUpperCase();
  const offset = parseOffset(query.offset);
  const basePath = `/admin/merchants/${encodeURIComponent(merchantId)}/afiliados`;

  return (
    <div className="stack">
      <Panel title="Programa de indicações">
        <Suspense fallback={<MetricsSkeleton count={6} />}>
          <MetricsPanel merchantId={merchantId} />
        </Suspense>
      </Panel>

      <Panel title="Afiliados deste negócio">
        <ChipFilter
          basePath={basePath}
          param="status"
          current={status}
          options={STATUSES}
          keep={{ search: search || undefined }}
        />
        <Suspense
          key={`${search}|${status}|${offset}`}
          fallback={<TableSkeleton rows={6} />}
        >
          <AffiliatesPanel
            basePath={basePath}
            merchantId={merchantId}
            offset={offset}
            search={search}
            status={status}
          />
        </Suspense>
      </Panel>

      <Panel title="Recompensas pendentes">
        <Suspense fallback={<TableSkeleton rows={4} />}>
          <RewardsPanel merchantId={merchantId} />
        </Suspense>
      </Panel>
    </div>
  );
}
