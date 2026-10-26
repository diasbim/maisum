import Link from 'next/link';
import { Suspense } from 'react';

import {
  fetchMerchantAffiliateMetrics,
  fetchMerchantAffiliateRewards,
  fetchMerchantAffiliates,
  fetchMerchantReferrals,
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
  attributionStatusLabel,
  attributionStatusTone,
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

/** `ATTRIBUTION_STATUS`, plus the "everything" chip the other filters have. */
const REFERRAL_STATUSES = [
  { value: '', label: 'Todas' },
  { value: 'CONFIRMED', label: 'Confirmadas' },
  { value: 'REJECTED', label: 'Recusadas' },
  { value: 'CANCELLED', label: 'Canceladas' },
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

/**
 * The attributions behind the totals.
 *
 * The panel above says an affiliate has pending rewards; this one says which
 * sales produced them. It is the screen that turns "the engine credited João
 * 400 points" from a number an operator has to trust into a list they can read
 * — and it is the only place a rejected attribution is visible at all, which
 * is the case somebody actually calls about.
 *
 * `REJECTED` rows carry their reason, and are not hidden. A referral that was
 * refused is the outcome a merchant most wants explained, and a table that
 * only showed the confirmed ones would answer the easy question.
 */
async function ReferralsPanel({
  basePath,
  merchantId,
  offset,
  status,
}: {
  basePath: string;
  merchantId: string;
  offset: number;
  status: string;
}) {
  const result = await load(() =>
    fetchMerchantReferrals(merchantId, {
      status: status || undefined,
      limit: MERCHANT_PAGE_SIZE,
      offset,
    }),
  );
  if (result.error !== null) return <ErrorState message={result.error} />;

  if (result.data.items.length === 0) {
    return (
      <EmptyState
        message={
          status === ''
            ? 'Este negócio ainda não tem indicações.'
            : 'Nenhuma indicação neste estado.'
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
              <th scope="col">Afiliado</th>
              <th scope="col">Cliente</th>
              <th scope="col">Venda</th>
              <th scope="col">Atribuída</th>
              <th scope="col">Estado</th>
            </tr>
          </thead>
          <tbody>
            {result.data.items.map((referral) => (
              <tr key={referral.id}>
                <td>
                  <Link
                    href={`/admin/afiliados/${encodeURIComponent(referral.affiliate_id)}`}
                  >
                    <code className="inline">{referral.affiliate_id}</code>
                  </Link>
                </td>
                <td>
                  {referral.customer_id === null ? (
                    <span className="muted">—</span>
                  ) : (
                    <code className="inline">{referral.customer_id}</code>
                  )}
                </td>
                <td>
                  {referral.first_sale_id === null ? (
                    <span className="muted">—</span>
                  ) : (
                    <code className="inline">{referral.first_sale_id}</code>
                  )}
                </td>
                <td>{formatDateTime(referral.attributed_at ?? referral.created_at)}</td>
                <td>
                  <Badge
                    label={attributionStatusLabel(referral.status)}
                    tone={attributionStatusTone(referral.status)}
                  />
                  {referral.rejection_reason === null ? null : (
                    <div className="micro">{referral.rejection_reason}</div>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <Pagination
        basePath={basePath}
        hasMore={result.data.hasMore}
        limit={MERCHANT_PAGE_SIZE}
        offset={offset}
        offsetParam="referral_offset"
        query={{ referral_status: status || undefined }}
        returned={result.data.items.length}
      />
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
  // Separate params from the affiliates table above, so filtering one panel
  // does not silently reset the other — both live on the same URL.
  const referralStatus = parseSearch(query.referral_status).toUpperCase();
  const referralOffset = parseOffset(query.referral_offset);
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
          // The referral filter is kept: `ChipFilter` rebuilds the URL from
          // scratch, so anything not listed here is dropped — and two panels
          // on one URL means filtering this table would silently clear the
          // other one.
          keep={{
            search: search || undefined,
            referral_status: referralStatus || undefined,
          }}
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

      <Panel title="Indicações">
        <ChipFilter
          basePath={basePath}
          param="referral_status"
          current={referralStatus}
          options={REFERRAL_STATUSES}
          keep={{ search: search || undefined, status: status || undefined }}
        />
        <Suspense key={`${referralStatus}|${referralOffset}`} fallback={<TableSkeleton rows={6} />}>
          <ReferralsPanel
            basePath={basePath}
            merchantId={merchantId}
            offset={referralOffset}
            status={referralStatus}
          />
        </Suspense>
      </Panel>
    </div>
  );
}
