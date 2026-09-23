import Link from 'next/link';
import { Suspense } from 'react';

import {
  fetchMyAffiliates,
  fetchMyReferrals,
  MERCHANT_PAGE_SIZE,
} from '@/lib/merchant-api';
import {
  attributionStatusLabel,
  attributionStatusTone,
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
import { AFFILIATES_PATH, affiliateHref } from '../afiliados';

export const metadata = { title: 'Indicações | MaisUm' };
export const dynamic = 'force-dynamic';

/**
 * The customers the programme actually brought in.
 *
 * The rewards screen answers "who do I owe"; this one answers the question
 * that comes before it — "did any of this work?". An owner deciding whether to
 * keep paying affiliates needs the list of people who walked in because
 * somebody sent them, not a points total.
 *
 * `GET /merchant/referrals` has existed since the API shipped and nothing
 * called it: the engine recorded every attribution and no screen in the
 * product could show one.
 *
 * Opens on all of them rather than on one state, unlike the rewards screen.
 * Rewards are a queue to be worked through; this is a record to be read, and
 * the refused ones are the most interesting rows on it — a merchant who thinks
 * the programme is not working is usually looking at referrals that were
 * rejected for a reason nobody ever showed them.
 */

const REFERRALS_PATH = `${AFFILIATES_PATH}/indicacoes`;

const STATUS = [
  { value: 'ALL', label: 'Todas' },
  { value: 'CONFIRMED', label: 'Confirmadas' },
  { value: 'REJECTED', label: 'Recusadas' },
  { value: 'CANCELLED', label: 'Canceladas' },
];

async function ReferralsTable({
  status,
  offset,
}: {
  status: string;
  offset: number;
}) {
  const [page, affiliates] = await Promise.all([
    load(() =>
      fetchMyReferrals({
        status: status === 'ALL' ? undefined : status,
        limit: MERCHANT_PAGE_SIZE,
        offset,
      }),
    ),
    // An attribution carries an affiliate id and no name, exactly as a reward
    // does. One extra read for the names rather than one per row, and a
    // failure here costs the names and nothing else.
    load(() => fetchMyAffiliates({ limit: 200 })),
  ]);

  if (page.error !== null) return <ErrorState message={page.error} />;

  if (page.data.items.length === 0) {
    return (
      <EmptyState
        action={
          status === 'ALL' ? undefined : (
            <ClearFilters href={REFERRALS_PATH} label="Ver todas" />
          )
        }
        message={
          status === 'ALL'
            ? 'Ainda não há indicações. Aparecem aqui quando um cliente novo comprar com um código de afiliado.'
            : 'Nenhuma indicação neste estado.'
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
        singular="indicação"
        plural="indicações"
      />

      <div className="card card--flush scroll-x">
        <table>
          <thead>
            <tr>
              <th scope="col">Afiliado</th>
              <th scope="col">Cliente</th>
              <th scope="col">Data</th>
              <th scope="col">Estado</th>
            </tr>
          </thead>
          <tbody>
            {page.data.items.map((referral) => {
              const name = nameById.get(referral.affiliate_id) ?? null;
              return (
                <tr key={referral.id}>
                  <td>
                    <Link href={affiliateHref(referral.affiliate_id)}>
                      {name ?? <code className="inline">{referral.affiliate_id}</code>}
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
                    {formatDateTime(referral.attributed_at ?? referral.created_at)}
                  </td>
                  <td>
                    <Badge
                      label={attributionStatusLabel(referral.status)}
                      tone={attributionStatusTone(referral.status)}
                    />
                    {referral.rejection_reason === null ? null : (
                      // Shown, not hidden. "Recusada" with no reason is the
                      // answer that generates the support call.
                      <div className="micro">{referral.rejection_reason}</div>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <Pagination
        basePath={REFERRALS_PATH}
        hasMore={page.data.hasMore}
        limit={MERCHANT_PAGE_SIZE}
        offset={offset}
        query={{ status: status === 'ALL' ? undefined : status }}
        returned={page.data.items.length}
      />
    </>
  );
}

export default async function MerchantReferralsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const status = (parseSearch(params.status) || 'ALL').toUpperCase();
  const offset = parseOffset(params.offset);

  return (
    <>
      <PageHeader
        title="Indicações"
        subtitle="Clientes novos que compraram com o código de um afiliado."
        action={
          <Link className="btn btn-outline btn-sm" href={AFFILIATES_PATH}>
            ← Todos os afiliados
          </Link>
        }
      />

      <Panel>
        <ChipFilter
          basePath={REFERRALS_PATH}
          param="status"
          current={status}
          options={STATUS}
        />
        <p className="micro">
          Uma indicação é registada na primeira compra de um cliente novo. Uma
          recusa não anula a venda — só não gera recompensa.
        </p>
      </Panel>

      <Panel>
        <Suspense key={`${status}|${offset}`} fallback={<TableSkeleton rows={6} />}>
          <ReferralsTable offset={offset} status={status} />
        </Suspense>
      </Panel>
    </>
  );
}
